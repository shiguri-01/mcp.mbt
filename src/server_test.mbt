///|
async test "initialize returns server metadata and capabilities" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  let client = @mcp.Client()
  let response = server.handle_jsonrpc(
    client.initialize_request(client_name="test-client", client_version="0.1.0"),
  )
  guard response is Some(Object(fields)) else {
    fail("expected JSON-RPC response")
  }
  guard fields["result"] is Object(result) else {
    fail("expected initialize result")
  }
  assert_true(
    result["protocolVersion"] == Json::string(@mcp.latest_protocol_version),
  )
  guard result["serverInfo"] is Object(info) else {
    fail("expected serverInfo")
  }
  assert_true(info["name"] == Json::string("test-server"))
  assert_true(server.is_initialized() == false)
  assert_true(
    server.negotiated_protocol_version() == Some(@mcp.latest_protocol_version),
  )
  guard server.client_info() is Some(client_info) else {
    fail("expected stored client info")
  }
  assert_true(client_info.name == "test-client")
}

///|
async test "normal requests require initialized notification" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  try! server.json_tool(name="ok", fn(_) { @mcp.CallToolResult::text("ok") })
  let blocked = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("tools/list"),
    }),
  )
  guard blocked is Some(Object({ "error": Object(error), .. })) else {
    fail("expected pre-initialize error")
  }
  assert_true(error["code"] == Json::number(-32600.0, repr="-32600"))

  let client = @mcp.Client()
  ignore(
    server.handle_jsonrpc(
      client.initialize_request(
        client_name="test-client",
        client_version="0.1.0",
      ),
    ),
  )
  let not_ready = server.handle_jsonrpc(client.list_tools_request())
  guard not_ready is Some(Object({ "error": Object(not_ready_error), .. })) else {
    fail("expected pre-ready error")
  }
  assert_true(not_ready_error["code"] == Json::number(-32600.0, repr="-32600"))

  let initialized = server.handle_jsonrpc(client.initialized_notification())
  assert_true(initialized == None)
  assert_true(server.is_initialized())
  let ready = server.handle_jsonrpc(client.list_tools_request())
  guard ready is Some(Object({ "result": Object(_), .. })) else {
    fail("expected ready tools list")
  }
}

///|
async test "resource not found errors use MCP resource error shape" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  let client = @mcp.Client()
  ignore(
    server.handle_jsonrpc(
      client.initialize_request(
        client_name="test-client",
        client_version="0.1.0",
      ),
    ),
  )
  ignore(server.handle_jsonrpc(client.initialized_notification()))
  let response = server.handle_jsonrpc(
    client.read_resource_request(uri="memory://missing"),
  )
  guard response is Some(Object({ "error": Object(error), .. })) else {
    fail("expected resource error")
  }
  assert_true(error["code"] == Json::number(-32002.0, repr="-32002"))
  assert_true(error["message"] == Json::string("Resource not found"))
  assert_true(
    error["data"] == Json::object({ "uri": Json::string("memory://missing") }),
  )
}

///|
async test "initialize negotiates unsupported protocol version to server latest" {
  let server = @mcp.Server(
    name="test-server",
    version="0.1.0",
    title="Test Server",
    description="Lifecycle test server",
    icons=[Icon(src="https://example.com/icon.svg", sizes=["any"])],
    website_url="https://example.com/server",
  )
  let response = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("initialize"),
      "params": Json::object({
        "protocolVersion": Json::string("1900-01-01"),
        "capabilities": Json::object({ "roots": Json::object({}) }),
        "clientInfo": Json::object({
          "name": Json::string("old-client"),
          "version": Json::string("0.0.1"),
          "websiteUrl": Json::string("https://example.com/client"),
        }),
      }),
    }),
  )
  guard response is Some(Object({ "result": Object(result), .. })) else {
    fail("expected initialize result")
  }
  assert_true(
    result["protocolVersion"] == Json::string(@mcp.latest_protocol_version),
  )
  guard result["serverInfo"] is Object(server_info) else {
    fail("expected serverInfo")
  }
  assert_true(server_info["title"] == Json::string("Test Server"))
  assert_true(
    server_info["websiteUrl"] == Json::string("https://example.com/server"),
  )
  guard server.client_capabilities() is Some(capabilities) else {
    fail("expected stored client capabilities")
  }
  assert_true(capabilities.roots is Some(_))
}
