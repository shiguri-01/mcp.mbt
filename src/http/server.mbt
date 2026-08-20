///|
fn jsonrpc_error(id : Json, error : @mcp.McpError) -> Json {
  let request_id : @jsonrpc.RequestId? = match id {
    String(s) => Some(@jsonrpc.RequestId::string(s))
    Number(num, repr~) =>
      Some(@jsonrpc.RequestId::number(num, repr?)) catch {
        _ => None
      }
    _ => None
  }
  error.to_response(id?=request_id).to_json()
}

///|
fn encode_json_response(body : Json) -> (String, Int) {
  let text = body.stringify()
  (text, @utf8.encode(text).length())
}

///|
async fn send_json(
  conn : @async_http.ServerConnection,
  status : Int,
  reason : String,
  body : Json,
  extra_headers? : Map[@async_http.CaseInsensitiveString, String] = Map([]),
) -> Unit {
  extra_headers["Content-Type"] = "application/json"
  let (text, content_length) = encode_json_response(body)
  extra_headers["Content-Length"] = content_length.to_string()
  conn.send_response(status, reason, extra_headers~)
  conn.write(text)
  conn.end_response()
}

///|
async fn send_empty(
  conn : @async_http.ServerConnection,
  status : Int,
  reason : String,
) -> Unit {
  conn.send_response(status, reason)
  conn.end_response()
}

///|
fn sse_message(message : Json) -> String {
  "event: message\r\ndata: \{message.stringify()}\r\n\r\n"
}

///|
async fn send_subscription_stream(
  conn : @async_http.ServerConnection,
  subscription : @server.Subscription,
  on_subscription : async (@server.Subscription, async (Json) -> Unit) -> Unit,
) -> Unit {
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    "X-Accel-Buffering": "no",
  })
  let outbound : @aqueue.Queue[String?] = Queue(kind=Unbounded)
  let stopped = Ref(false)
  let producer_error : Ref[String?] = Ref(None)
  // Every subscription stream begins with its acknowledgement.
  outbound.put(Some(sse_message(subscription.acknowledgement())))
  @async.with_task_group(group => {
    let producer = group.spawn(
      async fn() {
        on_subscription(subscription, async fn(event) {
          if !stopped.val && subscription.allows_event(event) {
            outbound.put(Some(sse_message(event)))
          }
        }) catch {
          error => producer_error.val = Some(error.to_string())
        }
      },
      allow_failure=true,
    )
    let writer = group.spawn(
      async fn() {
        while outbound.get() is Some(frame) {
          try {
            conn.write(frame)
            conn.flush()
          } catch {
            _ => {
              stopped.val = true
              producer.cancel()
              outbound.close(clear=true)
              return
            }
          }
        }
      },
      allow_failure=true,
    )
    // SSE comments keep an otherwise idle subscription observable. A failed
    // heartbeat is the transport's disconnect signal and cancels its producer.
    let heartbeat = group.spawn(
      async fn() {
        while !stopped.val {
          @async.sleep(15000)
          if !stopped.val {
            outbound.put(Some(": keepalive\r\n\r\n"))
          }
        }
      },
      allow_failure=true,
    )
    producer.wait()
    heartbeat.cancel()
    if !stopped.val {
      let final_response = match producer_error.val {
        Some(message) =>
          jsonrpc_error(
            subscription.id,
            @mcp.InternalError("subscription producer failed: \{message}"),
          )
        None => subscription.close_response()
      }
      outbound.put(Some(sse_message(final_response)))
      outbound.put(None)
    }
    writer.wait()
  })
  conn.end_response() catch {
    _ => ()
  }
}

///|
async fn send_request_stream(
  conn : @async_http.ServerConnection,
  server : @server.Server,
  request : @async_http.Request,
  message : Json,
) -> Unit {
  let cancelled = Ref(false)
  let streaming = Ref(false)
  let outbound : @aqueue.Queue[String?] = Queue(kind=Unbounded)
  let transport_meta = Json::object({
    "httpMethod": Json::string("POST"),
    "path": Json::string(request.path),
    "headers": request.headers.to_json(),
  })
  let hooks = @mcp.RequestHooks(
    emit_notification=async fn(notification) raise @mcp.McpError {
      if cancelled.val {
        raise @mcp.InternalError("HTTP response stream is closed")
      }
      if !streaming.val {
        try {
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
          })
          conn.flush()
          streaming.val = true
        } catch {
          error => {
            cancelled.val = true
            raise @mcp.InternalError(error.to_string())
          }
        }
      }
      outbound.put(Some(sse_message(notification))) catch {
        error => {
          cancelled.val = true
          raise @mcp.InternalError(error.to_string())
        }
      }
    },
    is_cancelled=() => cancelled.val,
    transport_meta~,
  )
  @async.with_task_group(group => {
    let handler = group.spawn(
      async fn() { server.handle_jsonrpc_with_hooks(message, hooks~) },
      allow_failure=true,
    )
    let writer = group.spawn(
      async fn() {
        while outbound.get() is Some(frame) {
          try {
            conn.write(frame)
            conn.flush()
          } catch {
            _ => {
              cancelled.val = true
              handler.cancel()
              outbound.close(clear=true)
              return
            }
          }
        }
      },
      allow_failure=true,
    )
    let heartbeat = group.spawn(
      async fn() {
        while !cancelled.val {
          @async.sleep(15000)
          if !cancelled.val && streaming.val {
            outbound.put(Some(": keepalive\r\n\r\n"))
          }
        }
      },
      allow_failure=true,
    )
    let response = handler.wait() catch { _ => None }
    heartbeat.cancel()
    match response {
      Some(response) if !cancelled.val && streaming.val => {
        outbound.put(Some(sse_message(response)))
        outbound.put(None)
        writer.wait()
      }
      Some(response) if !cancelled.val => {
        writer.cancel()
        // Error responses retain their HTTP status when no progress stream was
        // committed.
        let (status, reason) = response_status(response)
        send_json(conn, status, reason, response)
        return
      }
      None if !cancelled.val && !streaming.val => {
        writer.cancel()
        send_empty(conn, 202, "Accepted")
        return
      }
      _ => writer.cancel()
    }
    if !cancelled.val {
      conn.end_response()
    }
  })
}

///|
async fn send_mcp_error(
  conn : @async_http.ServerConnection,
  status : Int,
  reason : String,
  id : Json,
  error : @mcp.McpError,
) -> Unit {
  send_json(conn, status, reason, jsonrpc_error(id, error))
}

///|
fn response_status(response : Json) -> (Int, String) {
  match jsonrpc_error_code(response) {
    Some(-32601.0) => (404, "Not Found")
    Some(-32602.0 | -32020.0 | -32021.0 | -32022.0) => (400, "Bad Request")
    _ => (200, "OK")
  }
}

///|
fn origin_allowed(
  headers : Map[@async_http.CaseInsensitiveString, String],
  allowed : Set[String],
) -> Bool {
  match unique_header(headers, "Origin") {
    Ok(Some(origin)) => {
      if allowed.contains(origin) {
        return true
      }
      if !allowed.is_empty() {
        return false
      }
      guard unique_header(headers, "Host") is Ok(Some(host)) else {
        return false
      }
      let authority = host.to_lower()
      let hostname = if authority.has_prefix("["[:]) {
        match authority.find("]") {
          Some(end) => authority[:end + 1].to_owned()
          None => authority
        }
      } else {
        match authority.find(":") {
          Some(port) => authority[:port].to_owned()
          None => authority
        }
      }
      let loopback = hostname == "localhost" ||
        hostname == "127.0.0.1" ||
        hostname == "[::1]"
      loopback &&
      (
        origin.to_lower() == "http://\{authority}" ||
        origin.to_lower() == "https://\{authority}"
      )
    }
    Ok(None) => true
    Err(_) => false
  }
}

///|

///|
fn parse_request_metadata(
  message : Json,
) -> @mcp.RequestMeta? raise @mcp.McpError {
  guard is_jsonrpc_request(message) else { return None }
  guard message is Object({ "params": Object({ "_meta": meta, .. }), .. }) else {
    raise @mcp.InvalidParams("request params._meta is required")
  }
  Some(@mcp.RequestMeta::from_json(meta))
}

///|
fn common_request_error(
  request : @async_http.Request,
  options : ServerOptions,
) -> String? {
  if !origin_allowed(request.headers, options.allowed_origins) {
    return Some("Origin is not allowed")
  }
  None
}

///|
fn validate_tool_call_headers(
  server : @server.Server,
  request : @async_http.Request,
  message : Json,
) -> Unit raise @mcp.McpError {
  guard message
    is Object(
      {
        "method": String("tools/call"),
        "params": Object({ "name": String(name), "arguments"? : arguments, .. }),
        ..
      }
    ) else {
    return
  }
  let arguments = match arguments {
    Some(value) => value
    None => Json::object({})
  }
  match server.tool_descriptor(name) {
    Some(tool) => {
      let schema = tool.input_schema
      validate_tool_argument_headers(request.headers, schema, arguments) catch {
        InvalidHeaderSchema(message) => raise @mcp.InternalError(message)
        InvalidHeaderValue(message) | HeaderMismatch(message) =>
          raise @mcp.HeaderMismatch(message)
      }
    }
    None => ()
  }
}

///|
fn validate_post_media(
  request : @async_http.Request,
) -> Unit raise @mcp.McpError {
  let accepts_required_types = match header(request.headers, "Accept") {
    Some(accept) =>
      has_media_type(accept, "application/json") &&
      has_media_type(accept, "text/event-stream")
    None => false
  }
  if !accepts_required_types {
    raise @mcp.InvalidRequest(
      "Accept header must include application/json and text/event-stream",
    )
  }
  match header(request.headers, "Content-Type") {
    Some(content_type) if has_media_type(content_type, "application/json") => ()
    _ => raise @mcp.InvalidRequest("Content-Type must be application/json")
  }
}

///|
fn validate_post_request(
  request : @async_http.Request,
  message : Json,
  server : @server.Server,
) -> Unit raise @mcp.McpError {
  validate_post_media(request)
  ignore(parse_request_metadata(message))
  // The MCP dispatcher owns the server's version policy. HTTP only checks
  // header/body agreement here; an empty list disables the helper's default
  // standalone policy.
  validate_standard_headers_without_version_policy(request, message)
  validate_tool_call_headers(server, request, message)
}

///|

///|
fn decode_http_client_message(
  message : Json,
) -> @jsonrpc.Message raise @mcp.McpError {
  let decoded = @mcp.decode_message(message)
  match decoded {
    Request(_) | Notification(_) => decoded
    Response(_) =>
      raise @mcp.InvalidRequest(
        "Streamable HTTP accepts client JSON-RPC requests or notifications only",
      )
  }
}

///|
async fn handle_post(
  server : @server.Server,
  options : ServerOptions,
  request : @async_http.Request,
  body : &@io.Reader,
  conn : @async_http.ServerConnection,
) -> Unit {
  if header(request.headers, "Content-Length") is Some(content_length) &&
    decimal_header_exceeds(content_length, options.max_request_body_bytes) {
    send_mcp_error(
      conn,
      413,
      "Content Too Large",
      Json::null(),
      @mcp.InvalidRequest(
        "MCP HTTP request body exceeds the configured limit of \{options.max_request_body_bytes} bytes",
      ),
    )
    return
  }
  let text = read_bounded_text(
    body,
    options.max_request_body_bytes,
    "MCP HTTP request body",
  ) catch {
    BodyTooLarge(..) as error => {
      send_mcp_error(
        conn,
        413,
        "Content Too Large",
        Json::null(),
        body_read_error_to_mcp(error),
      )
      return
    }
    BodyInvalidUtf8(..) as error => {
      send_mcp_error(
        conn,
        400,
        "Bad Request",
        Json::null(),
        body_read_error_to_mcp(error),
      )
      return
    }
    BodyReadFailed(..) => return
  }
  let message = @json.parse(text) catch {
    error => {
      send_mcp_error(
        conn,
        400,
        "Bad Request",
        Json::null(),
        @mcp.ParseError(error.to_string()),
      )
      return
    }
  }
  let decoded_message = decode_http_client_message(message) catch {
    error => {
      send_mcp_error(
        conn,
        400,
        "Bad Request",
        request_id(message).unwrap_or(Json::null()),
        error,
      )
      return
    }
  }
  validate_post_request(request, message, server) catch {
    error => {
      send_mcp_error(
        conn,
        400,
        "Bad Request",
        request_id(message).unwrap_or(Json::null()),
        error,
      )
      return
    }
  }
  if decoded_message is Notification(_) {
    (options.on_notification)(message) catch {
      _ => ()
    }
    send_empty(conn, 202, "Accepted")
    return
  }
  if server.is_subscription_request(message) {
    let subscription = server.accept_subscription(message) catch {
      error => {
        send_json(
          conn,
          200,
          "OK",
          jsonrpc_error(request_id(message).unwrap_or(Json::null()), error),
        )
        return
      }
    }
    send_subscription_stream(conn, subscription, options.on_subscription)
    return
  }
  if options.stream_responses {
    send_request_stream(conn, server, request, message)
    return
  }
  match server.handle_jsonrpc(message) {
    Some(response) => {
      let (status, reason) = response_status(response)
      send_json(conn, status, reason, response)
    }
    None => send_empty(conn, 202, "Accepted")
  }
}

///|
async fn handle_request(
  server : @server.Server,
  options : ServerOptions,
  request : @async_http.Request,
  body : &@io.Reader,
  conn : @async_http.ServerConnection,
) -> Unit {
  guard request.path == options.endpoint_path else {
    send_empty(conn, 404, "Not Found")
    return
  }
  if common_request_error(request, options) is Some(_) {
    send_empty(conn, 403, "Forbidden")
    return
  }
  match request.meth {
    Post => handle_post(server, options, request, body, conn)
    _ => send_empty(conn, 405, "Method Not Allowed")
  }
}

///|
/// Serve a stateless MCP 2026-07-28 registry at one POST endpoint.
///
/// GET streams, DELETE session termination, and `MCP-Session-Id` are not part
/// of the MCP 2026-07-28 transport contract. Ordinary responses are JSON unless
/// `ServerOptions(stream_responses=true)` is selected; that mode sends
/// request-scoped progress notifications and the final response over SSE.
pub async fn serve(
  http_server : @async_http.Server,
  server : @server.Server,
  options? : ServerOptions = ServerOptions(),
) -> Unit {
  http_server.run_forever() <| ((request, body, conn) => {
    handle_request(server, options, request, body, conn)
  })
}
