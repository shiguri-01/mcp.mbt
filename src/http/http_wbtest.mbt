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
  let old = Json::object({
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
    standard_validation_error(request, old)
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
  try! server.json_tool(name="regional", input_schema=annotated_schema(), (_, _) => {
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
      @mcp.tools_list_changed_notification(subscription_id=subscription.id()),
    ),
  )
  assert_true(
    !subscription_event_allowed(
      subscription,
      @mcp.prompts_list_changed_notification(subscription_id=subscription.id()),
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
      @mcp.tools_list_changed_notification(subscription_id=subscription.id()),
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
      @mcp.tools_list_changed_notification(subscription_id=subscription.id()),
    )
    is Notification(_),
  )
  let outside_filter = try
    state.consume(
      @mcp.prompts_list_changed_notification(subscription_id=subscription.id()),
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
