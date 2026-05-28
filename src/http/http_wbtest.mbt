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
}

///|
test "Origin header requires configured allow list" {
  let rejected = post_request(headers={
    "Accept": "application/json, text/event-stream",
    "Origin": "https://evil.example",
  })
  assert_true(
    validate_post_request(rejected, initialize_message(), ServerOptions(), None) ==
    Some("Origin is not allowed"),
  )
  let allowed = post_request(headers={
    "Accept": "application/json, text/event-stream",
    "Origin": "https://client.example",
  })
  assert_true(
    validate_post_request(
      allowed,
      initialize_message(),
      ServerOptions(allowed_origins=Set::from_array(["https://client.example"])),
      None,
    ) ==
    None,
  )
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
test "split endpoint keeps MCP path for DELETE" {
  let (base, path) = try! split_endpoint("http://127.0.0.1:8080/mcp")
  assert_eq(base, "http://127.0.0.1:8080")
  assert_eq(path, "/mcp")
}
