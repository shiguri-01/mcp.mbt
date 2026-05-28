///|
fn initialize_message() -> Json {
  @mcp.Client().initialize_request(
    client_name="http-client",
    client_version="0.1.0",
  )
}

///|
fn post_request(headers~ : Map[String, String]) -> @async_http.Request {
  { meth: Post, path: "/mcp", headers }
}

///|
test "validate POST Accept header" {
  let options = ServerOptions()
  let missing_event_stream = post_request(headers={
    "Accept": "application/json",
  })
  assert_true(
    validate_post_request(
      missing_event_stream,
      initialize_message(),
      options,
      None,
    ) ==
    Some("Accept header must include application/json and text/event-stream"),
  )
  let accepted = post_request(headers={
    "Accept": "application/json, text/event-stream",
  })
  assert_true(
    validate_post_request(accepted, initialize_message(), options, None) == None,
  )
  let bogus_substrings = post_request(headers={
    "Accept": "application/jsonp, text/event-streamx",
  })
  assert_true(
    validate_post_request(bogus_substrings, initialize_message(), options, None) ==
    Some("Accept header must include application/json and text/event-stream"),
  )
  let accepted_with_parameters = post_request(headers={
    "Accept": "application/json; charset=utf-8, text/event-stream; q=0.9",
  })
  assert_true(
    validate_post_request(
      accepted_with_parameters,
      initialize_message(),
      options,
      None,
    ) ==
    None,
  )
}

///|
test "Origin header requires configured allow list" {
  let rejected = post_request(headers={
    "Accept": "application/json, text/event-stream",
    "Origin": "https://evil.example",
  })
  assert_true(
    common_request_error(rejected, ServerOptions()) ==
    Some("Origin is not allowed"),
  )
  let allowed = post_request(headers={
    "Accept": "application/json, text/event-stream",
    "Origin": "https://client.example",
  })
  assert_true(
    common_request_error(
      allowed,
      ServerOptions(allowed_origins=Set::from_array(["https://client.example"])),
    ) ==
    None,
  )
}

///|
test "common request validation applies auth to non-POST methods" {
  let delete : @async_http.Request = { meth: Delete, path: "/mcp", headers: {} }
  let rejected = ServerOptions(authenticate=fn(context) {
    context.http_method != Delete
  })
  assert_true(common_request_error(delete, rejected) == Some("Unauthorized"))
  let get : @async_http.Request = { meth: Get, path: "/mcp", headers: {} }
  assert_true(common_request_error(get, ServerOptions()) == None)
}

///|
test "standard headers must match JSON-RPC body" {
  let request = post_request(headers={
    "Accept": "application/json, text/event-stream",
    "Mcp-Method": "tools/call",
  })
  assert_true(
    validate_post_request(request, initialize_message(), ServerOptions(), None) ==
    Some("Header mismatch: Mcp-Method does not match body method"),
  )
}

///|
test "standard headers reject unsupported protocol version" {
  let request = post_request(headers={
    "Accept": "application/json, text/event-stream",
    "MCP-Protocol-Version": "2024-11-05",
  })
  assert_true(
    validate_post_request(
      request,
      @mcp.Client().ping_request(),
      ServerOptions(),
      None,
    ) ==
    Some("Unsupported MCP protocol version: 2024-11-05"),
  )
}

///|
test "headers are case-insensitive and session IDs must be visible ASCII" {
  let request = post_request(headers={ "mcp-session-id": "session-123" })
  assert_true(header(request.headers, "MCP-Session-Id") is Some("session-123"))
  assert_true(request_context(request).session_id is Some("session-123"))
  assert_true(visible_ascii("session-123"))
  assert_true(!visible_ascii("has space"))
  assert_true(!visible_ascii("日本語"))
}

///|
test "JSON-RPC message classification requires valid message shapes" {
  assert_true(is_jsonrpc_request(@mcp.Client().ping_request()))
  assert_true(is_jsonrpc_notification(@mcp.Client().initialized_notification()))
  let response = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "result": Json::object({}),
  })
  assert_true(is_jsonrpc_response(response))
  assert_true(!is_jsonrpc_response(Json::object({})))
  assert_true(
    !is_jsonrpc_notification(
      Json::object({ "method": Json::string("notifications/initialized") }),
    ),
  )
}

///|
test "session store insert lookup and remove" {
  let store = SessionStore()
  let server = @mcp.Server(name="session-test", version="0.1.0")
  store.insert("session-1", server)
  assert_true(store.get("session-1") is Some(_))
  assert_true(store.remove("session-1"))
  assert_true(store.get("session-1") is None)
  assert_true(!store.remove("session-1"))
}

///|
test "client derives request headers" {
  let client = Client("http://127.0.0.1:8080/mcp")
  let request = client.core.call_tool_request(
    name="echo",
    arguments=Json::object({}),
  )
  let headers = client.headers(request)
  assert_true(headers["Accept"].contains("application/json"))
  assert_true(headers["Accept"].contains("text/event-stream"))
  assert_eq(headers["Mcp-Method"], "tools/call")
  assert_eq(headers["Mcp-Name"], "echo")
}

///|
test "client derives request names for prompt and resource requests" {
  let client = Client("http://127.0.0.1:8080/mcp")
  let prompt_headers = client.headers(
    client.core.get_prompt_request(name="summarize"),
  )
  assert_eq(prompt_headers["Mcp-Method"], "prompts/get")
  assert_eq(prompt_headers["Mcp-Name"], "summarize")
  let resource_headers = client.headers(
    client.core.read_resource_request(uri="memory://status"),
  )
  assert_eq(resource_headers["Mcp-Method"], "resources/read")
  assert_eq(resource_headers["Mcp-Name"], "memory://status")
}

///|
test "method not found JSON-RPC responses map to HTTP 404" {
  let (status, reason) = response_status(
    jsonrpc_error(Json::null(), -32601, "Method not found"),
  )
  assert_eq(status, 404)
  assert_eq(reason, "Not Found")
}

///|
test "HTTP JSON-RPC errors preserve MCP error category" {
  let error = http_error_to_mcp(
    { code: 400, reason: "Bad Request", headers: {}, cookies: [] },
    jsonrpc_error(Json::null(), -32602, "bad params").stringify(),
  )
  assert_true(error is @mcp.InvalidParams("bad params"))
  let not_found = http_error_to_mcp(
    { code: 404, reason: "Not Found", headers: {}, cookies: [] },
    jsonrpc_error(Json::null(), -32601, "missing").stringify(),
  )
  assert_true(not_found is @mcp.MethodNotFound("missing"))
  let resource_not_found = http_error_to_mcp(
    { code: 404, reason: "Not Found", headers: {}, cookies: [] },
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::null(),
      "error": Json::object({
        "code": Json::number(-32002.0, repr="-32002"),
        "message": Json::string("Resource not found"),
        "data": Json::object({ "uri": Json::string("memory://missing") }),
      }),
    }).stringify(),
  )
  assert_true(resource_not_found is @mcp.ResourceNotFound("memory://missing"))
}

///|
test "client parses JSON-RPC responses from event stream body" {
  let messages = parse_http_messages(
    {
      code: 200,
      reason: "OK",
      headers: { "Content-Type": "text/event-stream; charset=utf-8" },
      cookies: [],
    },
    (
      #|event: prime
      #|data:
      #|
      #|event: message
      #|data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":1,"progress":0.5}}
      #|
      #|event: message
      #|data: {"jsonrpc":"2.0","id":1,"result":{}}
      #|
    ),
  )
  guard messages
    is [
      Object({ "method": String("notifications/progress"), .. }),
      Object({ "result": Object(_), .. }),
    ] else {
    fail("expected notification then response")
  }
}

///|
test "split endpoint keeps MCP path for DELETE" {
  let (base, path) = try! split_endpoint("http://127.0.0.1:8080/mcp")
  assert_eq(base, "http://127.0.0.1:8080")
  assert_eq(path, "/mcp")
}
