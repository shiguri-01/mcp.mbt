///|
fn post_request(headers~ : Map[String, String]) -> @async_http.Request {
  { meth: Post, path: "/mcp", headers }
}

///|
fn metadata_request(
  method_name : String,
  params? : Map[String, Json] = Map([]),
) -> Json {
  params["_meta"] = Json::object({
    "io.modelcontextprotocol/protocolVersion": Json::string(
      @mcp.latest_protocol_version,
    ),
    "io.modelcontextprotocol/clientCapabilities": Json::object({}),
  })
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "method": Json::string(method_name),
    "params": Json::object(params),
  })
}

///|
fn standard_validation_error(
  request : @async_http.Request,
  message : Json,
) -> @mcp.McpError? {
  try {
    validate_standard_headers(request, message)
    None
  } catch {
    error => Some(error)
  }
}

///|
test "standard request headers are required and match body metadata" {
  let ping = metadata_request("ping")
  assert_true(
    standard_validation_error(post_request(headers=Map([])), ping)
    is Some(@mcp.HeaderMismatch(_)),
  )
  let headers = standard_request_headers(ping, @mcp.latest_protocol_version)
  let request = post_request(headers~)
  assert_true(standard_validation_error(request, ping) is None)
  headers["Mcp-Method"] = "PING"
  assert_true(
    standard_validation_error(post_request(headers~), ping)
    is Some(@mcp.HeaderMismatch(_)),
  )
}

///|
test "standard headers require matching protocol metadata in the body" {
  let message = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "method": Json::string("server/discover"),
    "params": Json::object({}),
  })
  let request = post_request(headers={
    "MCP-Protocol-Version": @mcp.latest_protocol_version,
    "Mcp-Method": "server/discover",
  })
  assert_true(
    standard_validation_error(request, message) is Some(@mcp.HeaderMismatch(_)),
  )
}

///|
test "standard header names ignore case but values do not" {
  let ping = metadata_request("ping")
  let accepted = post_request(headers={
    "mcp-protocol-version": @mcp.latest_protocol_version,
    "MCP-METHOD": "ping",
  })
  assert_true(standard_validation_error(accepted, ping) is None)
  let duplicate = post_request(headers={
    "MCP-Protocol-Version": @mcp.latest_protocol_version,
    "mcp-protocol-version": @mcp.latest_protocol_version,
    "Mcp-Method": "ping",
  })
  assert_true(
    standard_validation_error(duplicate, ping) is Some(@mcp.HeaderMismatch(_)),
  )
}

///|
test "unsupported protocol version is distinct from header mismatch" {
  let unsupported_request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "method": Json::string("ping"),
    "params": Json::object({
      "_meta": Json::object({
        "io.modelcontextprotocol/protocolVersion": Json::string("2025-11-25"),
      }),
    }),
  })
  let request = post_request(headers={
    "MCP-Protocol-Version": "2025-11-25",
    "Mcp-Method": "ping",
  })
  assert_true(
    standard_validation_error(request, unsupported_request)
    is Some(@mcp.UnsupportedProtocolVersion(..)),
  )
}

///|
test "Mcp-Name is conditional and Base64 decoded before comparison" {
  let read = metadata_request("resources/read", params={
    "uri": Json::string("memory://東京"),
  })
  let headers = standard_request_headers(read, @mcp.latest_protocol_version)
  assert_eq(headers["Mcp-Name"], "=?base64?bWVtb3J5Oi8v5p2x5Lqs?=")
  assert_true(standard_validation_error(post_request(headers~), read) is None)
  headers.remove("Mcp-Name")
  assert_true(
    standard_validation_error(post_request(headers~), read)
    is Some(@mcp.HeaderMismatch(_)),
  )
  let ping = metadata_request("ping")
  let extra = standard_request_headers(ping, @mcp.latest_protocol_version)
  extra["Mcp-Name"] = "unexpected"
  assert_true(
    standard_validation_error(post_request(headers=extra), ping)
    is Some(@mcp.HeaderMismatch(_)),
  )
}

///|
test "MCP Base64 sentinel encoding is unambiguous and UTF-8 safe" {
  assert_eq(encode_mcp_header_value("us-west1"), "us-west1")
  assert_eq(
    encode_mcp_header_value("Hello, 世界"),
    "=?base64?SGVsbG8sIOS4lueVjA==?=",
  )
  assert_eq(encode_mcp_header_value(" padded "), "=?base64?IHBhZGRlZCA=?=")
  assert_eq(
    encode_mcp_header_value("=?base64?literal?="),
    "=?base64?PT9iYXNlNjQ/bGl0ZXJhbD89?=",
  )
  assert_eq(
    try! decode_mcp_header_value("=?base64?SGVsbG8sIOS4lueVjA==?="),
    "Hello, 世界",
  )
  let malformed = try decode_mcp_header_value("=?base64?%%%?=") catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(malformed)
}

///|
fn annotated_schema() -> Json {
  Json::object({
    "type": Json::string("object"),
    "properties": Json::object({
      "region": Json::object({
        "type": Json::string("string"),
        "x-mcp-header": Json::string("Region"),
      }),
      "options": Json::object({
        "type": Json::string("object"),
        "properties": Json::object({
          "attempt": Json::object({
            "type": Json::string("integer"),
            "x-mcp-header": Json::string("Attempt"),
          }),
          "enabled": Json::object({
            "type": Json::string("boolean"),
            "x-mcp-header": Json::string("Enabled"),
          }),
        }),
      }),
    }),
  })
}

///|
test "annotated nested primitive arguments become Mcp-Param headers" {
  let arguments = Json::object({
    "region": Json::string("東京"),
    "options": Json::object({
      "attempt": Json::number(42.0, repr="42"),
      "enabled": Json::boolean(false),
    }),
  })
  let headers = try! tool_argument_headers(annotated_schema(), arguments)
  assert_eq(headers["Mcp-Param-Region"], "=?base64?5p2x5Lqs?=")
  assert_eq(headers["Mcp-Param-Attempt"], "42")
  assert_eq(headers["Mcp-Param-Enabled"], "false")
  try! validate_tool_argument_headers(headers, annotated_schema(), arguments)
  headers["Mcp-Param-Attempt"] = "42.0"
  try! validate_tool_argument_headers(headers, annotated_schema(), arguments)
}

///|
test "null and absent arguments omit custom headers" {
  let arguments = Json::object({ "region": Json::null() })
  let headers = try! tool_argument_headers(annotated_schema(), arguments)
  assert_true(headers.is_empty())
  try! validate_tool_argument_headers(headers, annotated_schema(), arguments)
  let mismatch = try
    validate_tool_argument_headers(
      { "Mcp-Param-Region": "unexpected" },
      annotated_schema(),
      arguments,
    )
  catch {
    HeaderMismatch(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(mismatch)
}

///|
test "x-mcp-header rejects duplicate names, invalid types, and bad paths" {
  let duplicate = Json::object({
    "type": Json::string("object"),
    "properties": Json::object({
      "one": Json::object({
        "type": Json::string("string"),
        "x-mcp-header": Json::string("Tenant"),
      }),
      "two": Json::object({
        "type": Json::string("boolean"),
        "x-mcp-header": Json::string("tenant"),
      }),
    }),
  })
  let duplicate_invalid = try validate_tool_header_schema(duplicate) catch {
    InvalidHeaderSchema(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(duplicate_invalid)
  let under_items = Json::object({
    "type": Json::string("object"),
    "properties": Json::object({
      "values": Json::object({
        "type": Json::string("array"),
        "items": Json::object({
          "type": Json::string("string"),
          "x-mcp-header": Json::string("Value"),
        }),
      }),
    }),
  })
  let path_invalid = try validate_tool_header_schema(under_items) catch {
    InvalidHeaderSchema(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(path_invalid)
  let number = Json::object({
    "type": Json::string("object"),
    "properties": Json::object({
      "value": Json::object({
        "type": Json::string("number"),
        "x-mcp-header": Json::string("Value"),
      }),
    }),
  })
  let type_invalid = try validate_tool_header_schema(number) catch {
    InvalidHeaderSchema(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(type_invalid)
}

///|
test "annotated integer enforces JavaScript safe range" {
  let arguments = Json::object({
    "options": Json::object({
      "attempt": Json::number(9007199254740992.0, repr="9007199254740992"),
    }),
  })
  let invalid = try tool_argument_headers(annotated_schema(), arguments) catch {
    InvalidHeaderValue(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(invalid)
}

///|
test "POST requests require both JSON and SSE response media types" {
  let server = try! @mcp.Server(name="test", version="0.1.0")
  let message = metadata_request("server/discover")
  let accepted_headers = standard_request_headers(
    message, @mcp.latest_protocol_version,
  )
  accepted_headers["Accept"] = "application/json, text/event-stream"
  accepted_headers["Content-Type"] = "application/json; charset=utf-8"
  let accepted = post_request(headers=accepted_headers)
  let accepted_result = try
    validate_post_request(accepted, message, server)
  catch {
    _ => false
  } noraise {
    _ => true
  }
  assert_true(accepted_result)
  accepted_headers["Accept"] = "application/json"
  let rejected = try
    validate_post_request(
      post_request(headers=accepted_headers),
      message,
      server,
    )
  catch {
    @mcp.InvalidRequest(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "Mcp-Param headers match annotated tool arguments" {
  let server = try! @mcp.Server(name="tool-header-test", version="0.1.0")
  try! server.tool_json(name="regional", input_schema=annotated_schema(), (_, _) => {
    @mcp.Complete(@mcp.CallToolResult::text("ok"))
  })
  let arguments = Json::object({
    "region": Json::string("東京"),
    "options": Json::object({
      "attempt": Json::number(1.0),
      "enabled": Json::boolean(true),
    }),
  })
  let message = metadata_request("tools/call", params={
    "name": Json::string("regional"),
    "arguments": arguments,
  })
  let missing = try
    validate_tool_call_headers(server, post_request(headers=Map([])), message)
  catch {
    @mcp.HeaderMismatch(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(missing)
  let custom = try! tool_argument_headers(annotated_schema(), arguments)
  try! validate_tool_call_headers(server, post_request(headers=custom), message)
}

///|
test "Streamable HTTP rejects origins outside the configured allowlist" {
  let origin = post_request(headers={ "Origin": "https://client.example" })
  assert_true(
    common_request_error(origin, ServerOptions()) ==
    Some("Origin is not allowed"),
  )
  assert_true(
    common_request_error(
      origin,
      ServerOptions(allowed_origins=Set::from_array(["https://client.example"])),
    ) ==
    None,
  )
}

///|
test "Streamable HTTP accepts only matching loopback origins by default" {
  let loopback = post_request(headers={
    "Host": "127.0.0.1:8080",
    "Origin": "http://127.0.0.1:8080",
  })
  assert_eq(common_request_error(loopback, ServerOptions()), None)
  let rebinding = post_request(headers={
    "Host": "evil.example.com",
    "Origin": "http://evil.example.com",
  })
  assert_eq(
    common_request_error(rebinding, ServerOptions()),
    Some("Origin is not allowed"),
  )
}

///|
test "standard header values ignore surrounding HTTP whitespace" {
  let request = metadata_request("tools/call", params={
    "name": Json::string("greet"),
  })
  let headers = standard_request_headers(request, @mcp.latest_protocol_version)
  headers["Mcp-Name"] = "  greet\t"
  try! validate_standard_headers(post_request(headers~), request)
}

///|
test "invalid request metadata is reported before header mismatch" {
  let message = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1),
    "method": Json::string("tools/list"),
    "params": Json::object({}),
  })
  let server = try! @mcp.Server(name="server", version="1")
  let headers : Map[String, String] = {
    "Accept": "application/json, text/event-stream",
    "Content-Type": "application/json",
  }
  let error = try
    validate_post_request(post_request(headers~), message, server)
  catch {
    error => Some(error)
  } noraise {
    _ => None
  }
  assert_true(error is Some(@mcp.InvalidParams(_)))
}

///|
test "client derives standard and tool parameter headers" {
  let client = Client("http://127.0.0.1:8080/mcp")
  let request = client.core.call_tool_request(
    name="echo",
    arguments=Json::object({ "region": Json::string("東京") }),
  )
  let schema = Json::object({
    "type": Json::string("object"),
    "properties": Json::object({
      "region": Json::object({
        "type": Json::string("string"),
        "x-mcp-header": Json::string("Region"),
      }),
    }),
  })
  let headers = try! client.headers(request, input_schema=schema)
  assert_eq(headers["MCP-Protocol-Version"], @mcp.latest_protocol_version)
  assert_eq(headers["Mcp-Method"], "tools/call")
  assert_eq(headers["Mcp-Name"], "echo")
  assert_eq(headers["Mcp-Param-Region"], "=?base64?5p2x5Lqs?=")
}

///|
test "protocol negotiation rewrites metadata and uses a fresh request id" {
  let client = try! Client("http://127.0.0.1:8080/mcp", supported_protocol_versions=[
    "2026-07-28", "2026-01-01",
  ])
  let request = client.core.list_tools_request()
  let rewritten = try! request_with_protocol_version(
    request, "2026-01-01", true,
  )
  guard request
    is Object(
      {
        "id": original_id,
        "params": Object(
          {
            "_meta": Object(
              {
                "io.modelcontextprotocol/protocolVersion": String("2026-07-28"),
                ..
              }
            ),
            ..
          }
        ),
        ..
      }
    ) &&
    rewritten
    is Object(
      {
        "id": retry_id,
        "params": Object(
          {
            "_meta": Object(
              {
                "io.modelcontextprotocol/protocolVersion": String("2026-01-01"),
                "io.modelcontextprotocol/clientCapabilities": Object(_),
                ..
              }
            ),
            ..
          }
        ),
        ..
      }
    ) else {
    fail("expected rewritten protocol metadata")
  }
  assert_true(original_id != retry_id)
  assert_eq(
    client.mutually_supported_protocol_version([
      "2025-11-25", "2026-01-01", "2026-07-28",
    ]),
    Some("2026-07-28"),
  )
  assert_eq(client.mutually_supported_protocol_version(["2025-11-25"]), None)
}

///|
test "HTTP clients require at least one supported protocol version" {
  let rejected = try
    Client("http://127.0.0.1:8080/mcp", supported_protocol_versions=[])
  catch {
    @mcp.InvalidParams(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "HTTP notifications carry standard headers and accept only empty 202" {
  let client = try! Client("http://127.0.0.1:8080/mcp")
  let notification = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/cancelled"),
    "params": Json::object({}),
  })
  let prepared = try! notification_with_protocol_version(
    notification, @mcp.latest_protocol_version,
  )
  let headers = try! client.headers(prepared)
  assert_eq(headers["MCP-Protocol-Version"], @mcp.latest_protocol_version)
  assert_eq(headers["Mcp-Method"], "notifications/cancelled")
  let notification_with_meta = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/cancelled"),
    "params": Json::object({
      "_meta": Json::object({
        "io.modelcontextprotocol/protocolVersion": Json::string("1900-01-01"),
        "com.example/trace": Json::string("kept"),
      }),
    }),
  })
  assert_true(
    (try! notification_with_protocol_version(
      notification_with_meta, @mcp.latest_protocol_version,
    ))
    is Object(
      {
        "id"? : None,
        "params": Object(
          {
            "_meta": Object(
              {
                "io.modelcontextprotocol/protocolVersion": String("2026-07-28"),
                "com.example/trace": String("kept"),
                ..
              }
            ),
            ..
          }
        ),
        ..
      }
    ),
  )
  let accepted_response : @async_http.Response = {
    code: 202,
    reason: "Accepted",
    headers: {},
    cookies: [],
  }
  try! validate_notification_response(accepted_response, "")
  let body_rejected = try
    validate_notification_response(accepted_response, "{}")
  catch {
    @mcp.InvalidRequest(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(body_rejected)
  let wrong_status : @async_http.Response = {
    code: 200,
    reason: "OK",
    headers: {},
    cookies: [],
  }
  let status_rejected = try
    validate_notification_response(wrong_status, "")
  catch {
    @mcp.InvalidRequest(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(status_rejected)
}

///|
test "JSON and request-scoped SSE response bodies are parsed" {
  let json = parse_http_messages(
    {
      code: 200,
      reason: "OK",
      headers: { "Content-Type": "application/json" },
      cookies: [],
    },
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}",
  )
  assert_eq(json.length(), 1)
  let events = parse_http_messages(
    {
      code: 200,
      reason: "OK",
      headers: { "Content-Type": "text/event-stream; charset=utf-8" },
      cookies: [],
    },
    (
      #|: keep-alive
      #|event: message
      #|data: {"jsonrpc":"2.0","method":"notifications/progress","params":{}}
      #|
      #|event: message
      #|data: {"jsonrpc":"2.0","id":1,"result":{}}
      #|
    ),
  )
  assert_eq(events.length(), 2)
  assert_true(is_jsonrpc_response(events[1]))
}

///|
test "JSON response Content-Length is the UTF-8 octet count" {
  let (text, content_length) = encode_json_response(
    Json::object({ "text": Json::string("世界—😀") }),
  )
  assert_eq(text, "{\"text\":\"世界—😀\"}")
  assert_eq(content_length, 24)
}

///|
test "method-not-found responses map to HTTP 404" {
  let (status, reason) = response_status(
    jsonrpc_error(Json::null(), @mcp.MethodNotFound("missing")),
  )
  assert_eq(status, 404)
  assert_eq(reason, "Not Found")
  let (invalid_status, invalid_reason) = response_status(
    jsonrpc_error(Json::null(), @mcp.InvalidParams("missing metadata")),
  )
  assert_eq(invalid_status, 400)
  assert_eq(invalid_reason, "Bad Request")
  let (header_status, _) = response_status(
    jsonrpc_error(Json::null(), @mcp.HeaderMismatch("missing header")),
  )
  assert_eq(header_status, 400)
}

///|
test "subscription SSE starts with acknowledgement and ends with response" {
  let server = try! @mcp.Server(
    name="subscription-test",
    version="0.1.0",
    tool_list_changed=true,
  )
  let client = @mcp.Client(name="test", version="0.1.0")
  let request = client.listen_request(
    notifications=@mcp.SubscriptionFilter(tools_list_changed=true),
  )
  let subscription = try! server.accept_subscription(request)
  let ack = sse_message(subscription.acknowledgement())
  let close = sse_message(subscription.close_response())
  assert_true(ack.has_prefix("event: message\r\ndata:"[:]))
  assert_true(ack.contains("notifications/subscriptions/acknowledged"))
  assert_true(close.contains("\"result\""))
  assert_true(
    subscription_event_allowed(
      subscription,
      @mcp.tools_list_changed_notification(subscription_id=subscription.id),
    ),
  )
  assert_true(
    !subscription_event_allowed(
      subscription,
      @mcp.prompts_list_changed_notification(subscription_id=subscription.id),
    ),
  )
  assert_true(
    !subscription_event_allowed(
      subscription,
      @mcp.tools_list_changed_notification(subscription_id=Json::number(99.0)),
    ),
  )
}

///|
test "request response streaming is opt-in" {
  assert_true(!ServerOptions().stream_responses)
  assert_true(ServerOptions(stream_responses=true).stream_responses)
}

///|
test "HTTP body limits are positive and have safe defaults" {
  assert_eq(
    ServerOptions().max_request_body_bytes,
    default_max_request_body_bytes,
  )
  ignore(try! Client("http://127.0.0.1:8080/mcp"))
  try ignore(ServerOptions(max_request_body_bytes=0)) catch {
    @mcp.InvalidParams(_) => ()
    _ => fail("expected an invalid request body limit")
  } noraise {
    _ => fail("accepted a zero request body limit")
  }
  try
    ignore(Client("http://127.0.0.1:8080/mcp", max_response_body_bytes=0))
  catch {
    @mcp.InvalidParams(_) => ()
    _ => fail("expected an invalid response body limit")
  } noraise {
    _ => fail("accepted a zero response body limit")
  }
  try ignore(Client("http://127.0.0.1:8080/mcp", max_sse_event_bytes=0)) catch {
    @mcp.InvalidParams(_) => ()
    _ => fail("expected an invalid SSE event limit")
  } noraise {
    _ => fail("accepted a zero SSE event limit")
  }
  assert_true(decimal_header_exceeds("4194305", 4194304))
  assert_true(!decimal_header_exceeds("4194304", 4194304))
  assert_true(decimal_header_exceeds("999999999999999999999", 4194304))
  assert_true(!decimal_header_exceeds("not-a-length", 4194304))
}

///|
async test "HTTP JSON body limit counts UTF-8 octets during the read" {
  let (reader, writer) = @io.pipe()
  defer reader.close()
  defer writer.close()
  @async.with_task_group(group => {
    let producer = group.spawn(
      async fn() {
        writer.write("世界")
        writer.close()
      },
      allow_failure=true,
    )
    let rejected = try {
      ignore(read_bounded_text(reader, 5, "test body"))
      false
    } catch {
      BodyTooLarge(subject="test body", limit=5) => true
      _ => false
    }
    assert_true(rejected)
    producer.wait()
  })
}

///|
async test "SSE limit applies independently to every event" {
  let (reader, writer) = @io.pipe()
  defer reader.close()
  defer writer.close()
  @async.with_task_group(group => {
    let producer = group.spawn(
      async fn() { writer.write("data: first\n\ndata: second\n\n") },
      allow_failure=true,
    )
    let state = SseReadState::new()
    assert_eq(try! read_sse_data(reader, state, 14), Some("first"))
    assert_eq(try! read_sse_data(reader, state, 14), Some("second"))
    producer.wait()
  })
  let (oversized_reader, oversized_writer) = @io.pipe()
  defer oversized_reader.close()
  defer oversized_writer.close()
  @async.with_task_group(group => {
    let producer = group.spawn(
      async fn() { oversized_writer.write("data: too-large\n\n") },
      allow_failure=true,
    )
    let rejected = try {
      ignore(read_sse_data(oversized_reader, SseReadState::new(), 10))
      false
    } catch {
      BodyTooLarge(subject="MCP SSE event", limit=10) => true
      _ => false
    }
    assert_true(rejected)
    producer.wait()
  })
}

///|
test "accepted notifications still require every standard header" {
  let server = try! @mcp.Server(name="notification-test", version="0.1.0")
  let message = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/cancelled"),
    "params": Json::object({
      "_meta": Json::object({
        "io.modelcontextprotocol/protocolVersion": Json::string(
          @mcp.latest_protocol_version,
        ),
      }),
    }),
  })
  let headers = standard_request_headers(message, @mcp.latest_protocol_version)
  headers["Accept"] = "application/json, text/event-stream"
  headers["Content-Type"] = "application/json"
  try! validate_post_request(post_request(headers~), message, server)
  headers["Mcp-Method"] = "notifications/progress"
  let mismatch = try
    validate_post_request(post_request(headers~), message, server)
  catch {
    error => Some(error)
  } noraise {
    _ => None
  }
  guard mismatch is Some(error) else {
    fail("expected notification header mismatch")
  }
  assert_eq(error.code(), -32020)
  headers["Mcp-Method"] = "notifications/cancelled"
  headers["MCP-Protocol-Version"] = "2025-01-01"
  let version_mismatch = try
    validate_post_request(post_request(headers~), message, server)
  catch {
    error => Some(error)
  } noraise {
    _ => None
  }
  guard version_mismatch is Some(version_error) else {
    fail("expected notification protocol version mismatch")
  }
  assert_eq(version_error.code(), -32020)
}

///|
test "response ids are checked before decoding results" {
  let response = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(2.0, repr="2"),
    "result": Json::object({}),
  })
  let mismatch = try
    validate_response_id(response, Json::number(1.0, repr="1"), "HTTP")
  catch {
    @mcp.InvalidRequest(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(mismatch)
}

///|
test "subscription client enforces acknowledgement and stream identity" {
  let server = try! @mcp.Server(
    name="subscription-state-test",
    version="0.1.0",
    tool_list_changed=true,
  )
  let core = @mcp.Client(name="test", version="0.1.0")
  let requested = @mcp.SubscriptionFilter(tools_list_changed=true)
  let request = core.listen_request(notifications=requested)
  let expected_id = request_id(request).unwrap()
  let subscription = try! server.accept_subscription(request)
  let before_ack = SubscriptionStreamState::new(expected_id, requested)
  let premature = try
    before_ack.consume(
      @mcp.tools_list_changed_notification(subscription_id=subscription.id),
    )
  catch {
    @mcp.InvalidRequest(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(premature)
  let state = SubscriptionStreamState::new(expected_id, requested)
  assert_true(state.consume(subscription.acknowledgement()) is Acknowledged)
  assert_true(
    state.consume(
      @mcp.tools_list_changed_notification(subscription_id=subscription.id),
    )
    is Notification(_),
  )
  let outside_filter = try
    state.consume(
      @mcp.prompts_list_changed_notification(subscription_id=subscription.id),
    )
  catch {
    @mcp.InvalidRequest(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(outside_filter)
  let wrong_id = try
    state.consume(
      @mcp.tools_list_changed_notification(subscription_id=Json::number(99.0)),
    )
  catch {
    @mcp.InvalidRequest(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(wrong_id)
  assert_true(state.consume(subscription.close_response()) is Final(_))
}

///|
test "subscription producer errors retain their JSON-RPC identity" {
  let expected_id = Json::number(7.0, repr="7")
  let state = SubscriptionStreamState::new(
    expected_id,
    @mcp.SubscriptionFilter(tools_list_changed=true),
  )
  let acknowledgement = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/subscriptions/acknowledged"),
    "params": Json::object({
      "notifications": @mcp.SubscriptionFilter(tools_list_changed=true).to_json(),
      "_meta": Json::object({
        "io.modelcontextprotocol/subscriptionId": expected_id,
      }),
    }),
  })
  assert_true(state.consume(acknowledgement) is Acknowledged)
  let error = jsonrpc_error(expected_id, @mcp.InternalError("producer failed"))
  assert_true(state.consume(error) is Final(_))
}

///|
test "subscription client rejects unhonored filters and wrong final id" {
  let expected_id = Json::number(1.0, repr="1")
  let requested = @mcp.SubscriptionFilter(tools_list_changed=true)
  let invalid_ack = @mcp.subscriptions_acknowledged_notification(
    subscription_id=expected_id,
    notifications=@mcp.SubscriptionFilter(prompts_list_changed=true),
  )
  let invalid_state = SubscriptionStreamState::new(expected_id, requested)
  let unrequested = try invalid_state.consume(invalid_ack) catch {
    @mcp.InvalidRequest(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(unrequested)
  let state = SubscriptionStreamState::new(expected_id, requested)
  let ack = @mcp.subscriptions_acknowledged_notification(
    subscription_id=expected_id,
    notifications=requested,
  )
  ignore(try! state.consume(ack))
  let wrong_final = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(2.0, repr="2"),
    "result": Json::object({
      "resultType": Json::string("complete"),
      "_meta": Json::object({
        "io.modelcontextprotocol/subscriptionId": expected_id,
      }),
    }),
  })
  let rejected = try state.consume(wrong_final) catch {
    @mcp.InvalidRequest(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
  let wrong_subscription = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": expected_id,
    "result": Json::object({
      "resultType": Json::string("complete"),
      "_meta": Json::object({
        "io.modelcontextprotocol/subscriptionId": Json::number(99.0),
      }),
    }),
  })
  let rejected_subscription = try state.consume(wrong_subscription) catch {
    @mcp.InvalidRequest(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected_subscription)
}

///|
test "Streamable HTTP accepts notification shapes but rejects responses" {
  let notification = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/cancelled"),
    "params": Json::object({}),
  })
  try! validate_http_client_message(notification)
  let response = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0),
    "result": Json::object({}),
  })
  let rejected_response = try validate_http_client_message(response) catch {
    @mcp.InvalidRequest(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected_response)
}

///|
fn test_authorization_provider() -> @auth.AuthorizationProvider {
  @auth.AuthorizationProvider(
    send_request=_ => @auth.HttpResponse(status=500),
    open_authorization_url=url => url,
    random_bytes=size => Bytes::make(size, 1),
  )
}

///|
test "authorization configuration requires an absolute redirect URI" {
  try
    ignore(
      AuthorizationOptions(
        provider=test_authorization_provider(),
        redirect_uri="/callback",
      ),
    )
  catch {
    @mcp.InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("expected invalid redirect URI to be rejected")
  }
}

///|
test "Bearer credentials are attached only as an Authorization header" {
  let options = try! AuthorizationOptions(
    provider=test_authorization_provider(),
    redirect_uri="https://client.example/callback",
  )
  let client = try! Client("https://rs.example/mcp", authorization=options)
  let issuer = "https://as.example"
  client.authorization_issuer = Some(issuer)
  client.token_cache.put(
    try! @auth.OAuthTokens(access_token="top-secret"),
    issuer~,
    resource="https://rs.example/mcp",
  )
  let request = metadata_request("tools/list")
  let headers = try! client.headers(request)
  assert_eq(headers.get("Authorization"), Some("Bearer top-secret"))
  assert_false(client.endpoint.contains("top-secret"[:]))
  assert_false(request.stringify().contains("top-secret"[:]))
}

///|
test "Bearer credentials are not reused across resource bindings" {
  let options = try! AuthorizationOptions(
    provider=test_authorization_provider(),
    redirect_uri="https://client.example/callback",
  )
  let client = try! Client("https://rs.example/mcp", authorization=options)
  let issuer = "https://as.example"
  client.authorization_issuer = Some(issuer)
  client.token_cache.put(
    try! @auth.OAuthTokens(access_token="wrong-resource"),
    issuer~,
    resource="https://rs.example/other",
  )
  assert_true(
    try! (client.headers(metadata_request("tools/list")).get("Authorization")
    is None),
  )
}

///|
async test "401 without a challenge falls back to protected-resource discovery" {
  let auth_requests : Array[@auth.HttpRequest] = []
  let opened : Array[String] = []
  let provider = @auth.AuthorizationProvider(
    send_request=request => {
      auth_requests.push(request)
      match request.url {
        "https://rs.example/.well-known/oauth-protected-resource" =>
          @auth.HttpResponse(
            status=200,
            headers=Map([("Content-Type", "application/json")]),
            body=Json::object({
              "resource": "https://rs.example",
              "authorization_servers": ["https://as.example"],
              "scopes_supported": ["read"],
            }).stringify(),
          )
        "https://as.example/.well-known/oauth-authorization-server" =>
          @auth.HttpResponse(
            status=200,
            headers=Map([("content-type", "Application/JSON; charset=utf-8")]),
            body=Json::object({
              "issuer": "https://as.example",
              "authorization_endpoint": "https://as.example/authorize",
              "token_endpoint": "https://as.example/token",
              "token_endpoint_auth_methods_supported": ["none"],
              "code_challenge_methods_supported": ["S256"],
              "authorization_response_iss_parameter_supported": true,
            }).stringify(),
          )
        "https://as.example/token" =>
          @auth.HttpResponse(
            status=200,
            headers=Map([("Content-Type", "application/json")]),
            body=Json::object({
              "access_token": "bound-access",
              "token_type": "Bearer",
              "scope": "read",
            }).stringify(),
          )
        _ => @auth.HttpResponse(status=404)
      }
    },
    open_authorization_url=url => {
      opened.push(url)
      let parsed = @auth.parse_absolute_uri(url)
      let state = @auth.parse_query(parsed.query.unwrap_or(""))
        .get("state")
        .unwrap()
      "https://client.example/callback?code=code-1&state=" +
      @auth.percent_encode(state) +
      "&iss=https%3A%2F%2Fas.example"
    },
    random_bytes=size => Bytes::make(size, 9),
  )
  let credentials = try! @auth.ClientCredentials(client_id="registered")
  let options = try! AuthorizationOptions(
    provider~,
    redirect_uri="https://client.example/callback",
    pre_registered=Map([("https://as.example", credentials)]),
  )
  let client = try! Client("https://rs.example/mcp", authorization=options)
  let response : @async_http.Response = {
    code: 401,
    reason: "Unauthorized",
    headers: Map([]),
    cookies: [],
  }
  client.authorize_challenge(response, "tools/list") catch {
    _ => abort("authorization failed")
  }
  let headers = try! client.headers(metadata_request("tools/list"))
  assert_eq(headers.get("Authorization"), Some("Bearer bound-access"))
  assert_eq(opened.length(), 1)
  assert_false(opened[0].contains("bound-access"[:]))
  guard auth_requests.last() is Some(token_request) else {
    abort("missing token request")
  }
  assert_true(
    token_request.body.contains("resource=https%3A%2F%2Frs.example%2Fmcp"[:]),
  )
}

///|
test "generic 403 is not treated as scope step-up" {
  let generic : @async_http.Response = {
    code: 403,
    reason: "Forbidden",
    headers: Map([]),
    cookies: [],
  }
  let step_up : @async_http.Response = {
    code: 403,
    reason: "Forbidden",
    headers: Map([
      (
        "WWW-Authenticate", "Bearer error=\"insufficient_scope\", scope=\"write\"",
      ),
    ]),
    cookies: [],
  }
  assert_false(response_requires_authorization(generic))
  assert_true(response_requires_authorization(step_up))
}

///|
test "authorization endpoint policy is enforced when Client is constructed" {
  let strict = try! AuthorizationOptions(
    provider=test_authorization_provider(),
    redirect_uri="https://client.example/callback",
  )
  try ignore(Client("http://127.0.0.1:8080/mcp", authorization=strict)) catch {
    @mcp.InvalidRequest(_) => ()
    _ => fail("expected authorization destination rejection")
  } noraise {
    _ => fail("authorization bypassed endpoint policy")
  }
  let loopback_provider = @auth.AuthorizationProvider(
    send_request=_ => @auth.HttpResponse(status=500),
    open_authorization_url=url => url,
    random_bytes=size => Bytes::make(size, 1),
    allow_insecure_loopback=true,
  )
  let loopback = try! AuthorizationOptions(
    provider=loopback_provider,
    redirect_uri="http://127.0.0.1:9000/callback",
  )
  ignore(try! Client("http://127.0.0.1:8080/mcp", authorization=loopback))
}

///|
test "authorization resource override preserves a significant trailing slash" {
  let options = try! AuthorizationOptions(
    provider=test_authorization_provider(),
    redirect_uri="https://client.example/callback",
    resource_uri="https://rs.example/mcp/",
  )
  let client = try! Client("https://rs.example/mcp", authorization=options)
  assert_eq(client.authorization_resource, "https://rs.example/mcp/")
  assert_true(client.authorization_resource_exact)
  let issuer = "https://as.example"
  client.authorization_issuer = Some(issuer)
  client.token_cache.put(
    try! @auth.OAuthTokens(access_token="slash-bound"),
    issuer~,
    resource="https://rs.example/mcp/",
  )
  assert_eq(
    (try! client.headers(metadata_request("tools/list"))).get("Authorization"),
    Some("Bearer slash-bound"),
  )
}

///|
test "authorization resource override obeys destination security policy" {
  let options = try! AuthorizationOptions(
    provider=test_authorization_provider(),
    redirect_uri="https://client.example/callback",
    resource_uri="https://169.254.169.254/mcp/",
  )
  try ignore(Client("https://rs.example/mcp", authorization=options)) catch {
    @mcp.InvalidRequest(_) => ()
    _ => fail("expected resource policy rejection")
  } noraise {
    _ => fail("private resource override was accepted")
  }
}
