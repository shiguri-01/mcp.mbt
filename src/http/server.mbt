///|
fn jsonrpc_error(id : Json, code : Int, message : String) -> Json {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id,
    "error": Json::object({
      "code": Json::number(code.to_double(), repr="\{code}"),
      "message": Json::string(message),
    }),
  })
}

///|
async fn send_json(
  conn : @async_http.ServerConnection,
  status : Int,
  reason : String,
  body : Json,
  extra_headers? : Map[String, String] = {},
) -> Unit {
  extra_headers["Content-Type"] = "application/json"
  let text = body.stringify()
  // Content-Length must be the UTF-8 byte count of the body, not the UTF-16
  // code-unit count String::length() returns — the body is written as UTF-8
  // (see conn.write below, and the client's own @utf8.encode at client.mbt).
  // A non-ASCII char (em-dash, CJK, emoji) makes length() under-count, and
  // the async writer raises on the body/Content-Length mismatch → dropped
  // connection. Count the same bytes the writer sends.
  extra_headers["Content-Length"] = @utf8.encode(text).length().to_string()
  conn.send_response(status, reason, extra_headers~)
  conn.write(text)
  conn.end_response()
}

///|
async fn send_empty(
  conn : @async_http.ServerConnection,
  status : Int,
  reason : String,
  extra_headers? : Map[String, String] = {},
) -> Unit {
  conn.send_response(status, reason, extra_headers~)
  conn.end_response()
}

///|
async fn send_http_error(
  conn : @async_http.ServerConnection,
  status : Int,
  reason : String,
  message : String,
) -> Unit {
  send_json(
    conn,
    status,
    reason,
    jsonrpc_error(Json::null(), HEADER_MISMATCH_CODE, message),
  )
}

///|
fn response_status(response : Json) -> (Int, String) {
  if jsonrpc_error_code(response) is Some(-32601.0) {
    (404, "Not Found")
  } else {
    (200, "OK")
  }
}

///|
fn origin_allowed(headers : Map[String, String], allowed : Set[String]) -> Bool {
  match header(headers, "Origin") {
    Some(origin) => allowed.contains(origin)
    None => true
  }
}

///|
fn common_request_error(
  request : @async_http.Request,
  options : ServerOptions,
) -> String? {
  if !origin_allowed(request.headers, options.allowed_origins) {
    return Some("Origin is not allowed")
  }
  if !(options.authenticate)(request_context(request)) {
    return Some("Unauthorized")
  }
  None
}

///|
fn response_protocol_version(
  server : @mcp.Server,
  fallback : String?,
) -> String? {
  match server.negotiated_protocol_version() {
    Some(version) => Some(version)
    None => fallback
  }
}

///|
async fn handle_delete(
  store : SessionStore,
  request : @async_http.Request,
  conn : @async_http.ServerConnection,
) -> Unit {
  match header(request.headers, "MCP-Session-Id") {
    Some(session_id) if store.remove(session_id) =>
      send_empty(conn, 202, "Accepted")
    Some(_) => send_empty(conn, 404, "Not Found")
    None =>
      send_http_error(
        conn, 400, "Bad Request", "MCP-Session-Id header is required",
      )
  }
}

///|
fn validate_post_request(
  request : @async_http.Request,
  message : Json,
  options : ServerOptions,
  server : @mcp.Server?,
) -> String? {
  ignore(options)
  let accepts_required_types = match header(request.headers, "Accept") {
    Some(accept) =>
      has_media_type(accept, "application/json") &&
      has_media_type(accept, "text/event-stream")
    None => false
  }
  if !accepts_required_types {
    return Some(
      "Accept header must include application/json and text/event-stream",
    )
  }
  let protocol_version = match server {
    Some(server) =>
      response_protocol_version(server, protocol_version_from_message(message))
    None => protocol_version_from_message(message)
  }
  if validate_standard_headers(request, message, protocol_version?)
    is Some(error) {
    return Some(error)
  }
  None
}

///|
async fn handle_post(
  store : SessionStore,
  make_server : () -> @mcp.Server,
  options : ServerOptions,
  request : @async_http.Request,
  body : &@io.Reader,
  conn : @async_http.ServerConnection,
) -> Unit {
  let text = body.read_all().text()
  let message = @json.parse(text) catch {
    error => {
      send_json(
        conn,
        400,
        "Bad Request",
        jsonrpc_error(
          Json::null(),
          @mcp.ParseError(error.to_string()).code(),
          error.to_string(),
        ),
      )
      return
    }
  }
  let is_initialize = request_method_name(message) == Some("initialize")
  let server = if is_initialize {
    make_server()
  } else {
    match header(request.headers, "MCP-Session-Id") {
      Some(session_id) =>
        match store.get(session_id) {
          Some(session) => session.server
          None => {
            send_empty(conn, 404, "Not Found")
            return
          }
        }
      None => {
        if options.require_session {
          send_http_error(
            conn, 400, "Bad Request", "MCP-Session-Id header is required",
          )
          return
        }
        make_server()
      }
    }
  }
  if validate_post_request(request, message, options, Some(server))
    is Some(error) {
    let status = if error == "Origin is not allowed" { 403 } else { 400 }
    let reason = if status == 403 { "Forbidden" } else { "Bad Request" }
    send_http_error(conn, status, reason, error)
    return
  }
  if is_jsonrpc_notification(message) || is_jsonrpc_response(message) {
    ignore(server.handle_jsonrpc(message))
    send_empty(conn, 202, "Accepted")
    return
  }
  if !is_jsonrpc_request(message) {
    send_json(
      conn,
      400,
      "Bad Request",
      jsonrpc_error(
        Json::null(),
        @mcp.InvalidRequest("invalid JSON-RPC message").code(),
        "invalid JSON-RPC message",
      ),
    )
    return
  }
  match server.handle_jsonrpc(message) {
    Some(response) => {
      let headers : Map[String, String] = {}
      if is_initialize {
        let session_id = (options.session_id_generator)()
        if !visible_ascii(session_id) {
          send_json(
            conn,
            500,
            "Internal Server Error",
            jsonrpc_error(
              request_id(message).unwrap_or(Json::null()),
              @mcp.InternalError(
                "session ID generator returned non-visible ASCII",
              ).code(),
              "session ID generator returned non-visible ASCII",
            ),
          )
          return
        }
        store.insert(session_id, server)
        headers["MCP-Session-Id"] = session_id
      }
      let (status, reason) = response_status(response)
      send_json(conn, status, reason, response, extra_headers=headers)
    }
    None => send_empty(conn, 202, "Accepted")
  }
}

///|
async fn handle_request(
  store : SessionStore,
  make_server : () -> @mcp.Server,
  options : ServerOptions,
  request : @async_http.Request,
  body : &@io.Reader,
  conn : @async_http.ServerConnection,
) -> Unit {
  guard request.path == options.endpoint_path else {
    send_empty(conn, 404, "Not Found")
    return
  }
  if common_request_error(request, options) is Some(error) {
    if error == "Origin is not allowed" {
      send_http_error(conn, 403, "Forbidden", error)
    } else {
      send_empty(conn, 401, "Unauthorized")
    }
    return
  }
  match request.meth {
    Post => handle_post(store, make_server, options, request, body, conn)
    Delete => handle_delete(store, request, conn)
    Get => send_empty(conn, 405, "Method Not Allowed")
    _ => send_empty(conn, 405, "Method Not Allowed")
  }
}

///|
/// Serve MCP Streamable HTTP on a single endpoint.
///
/// This implementation supports the required POST request path and session
/// lifecycle. GET/SSE streams are intentionally reported as `405 Method Not
/// Allowed`, which the 2025-11-25 transport specification permits for servers
/// that do not offer a standalone SSE stream.
///
/// Specification:
/// https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
pub async fn serve(
  http_server : @async_http.Server,
  make_server : () -> @mcp.Server,
  options? : ServerOptions = ServerOptions(),
) -> Unit {
  let store = SessionStore()
  http_server.run_forever() <| ((request, body, conn) => {
    handle_request(store, make_server, options, request, body, conn)
  })
}
