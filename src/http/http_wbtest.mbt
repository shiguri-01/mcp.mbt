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
test "split endpoint keeps MCP path for DELETE" {
  let (base, path) = try! split_endpoint("http://127.0.0.1:8080/mcp")
  assert_eq(base, "http://127.0.0.1:8080")
  assert_eq(path, "/mcp")
}
