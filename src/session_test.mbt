///|
async fn initialize_server(server : @mcp.Server) -> Unit {
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
}

///|
async test "list requests support cursor pagination" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  for i in 0..<101 {
    try! server.json_tool(name="tool_\{i}", fn(_) {
      @mcp.CallToolResult::text("ok")
    })
  }
  initialize_server(server)
  let first = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("tools/list"),
    }),
  )
  guard first
    is Some(
      Object(
        {
          "result": Object(
            { "tools": Array(tools), "nextCursor": String(cursor), .. }
          ),
          ..
        }
      )
    ) else {
    fail("expected first tools page")
  }
  assert_true(tools.length() == 100)
  let second = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(2.0, repr="2"),
      "method": Json::string("tools/list"),
      "params": Json::object({ "cursor": Json::string(cursor) }),
    }),
  )
  guard second
    is Some(Object({ "result": Object({ "tools": Array(rest), .. }), .. })) else {
    fail("expected second tools page")
  }
  assert_true(rest.length() == 1)
}

///|
async test "resource templates are listable" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  try! server.resource_template(
    uri_template="file:///{path}",
    name="file",
    description="A file resource",
    mime_type="text/plain",
  )
  initialize_server(server)
  let response = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("resources/templates/list"),
    }),
  )
  guard response
    is Some(
      Object(
        {
          "result": Object(
            { "resourceTemplates": Array([Object(template)]), .. }
          ),
          ..
        }
      )
    ) else {
    fail("expected resource template")
  }
  assert_true(template["uriTemplate"] == Json::string("file:///{path}"))
}

///|
async test "completion handlers are dispatchable" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  try! server.completion(reference=@mcp.PromptRef(name="summarize"), fn(
    request,
  ) raise @mcp.McpError {
    if request.argument_name != "topic" || request.argument_value != "M" {
      raise @mcp.InvalidParams("unexpected completion request")
    }
    @mcp.CompleteResult(values=["MCP", "MoonBit"], total=2)
  })
  initialize_server(server)
  let response = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("completion/complete"),
      "params": Json::object({
        "ref": Json::object({
          "type": Json::string("ref/prompt"),
          "name": Json::string("summarize"),
        }),
        "argument": Json::object({
          "name": Json::string("topic"),
          "value": Json::string("M"),
        }),
      }),
    }),
  )
  guard response
    is Some(
      Object(
        {
          "result": Object(
            { "completion": Object({ "values": Array(values), .. }), .. }
          ),
          ..
        }
      )
    ) else {
    fail("expected completion result")
  }
  assert_true(values.length() == 2)
}

///|
async test "logging ping and notification builders follow MCP names" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  let pre_initialize_ping = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(0.0, repr="0"),
      "method": Json::string("ping"),
    }),
  )
  guard pre_initialize_ping is Some(Object({ "result": Object(_), .. })) else {
    fail("expected pre-initialize ping result")
  }
  initialize_server(server)
  let logging = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("logging/setLevel"),
      "params": Json::object({ "level": Json::string("debug") }),
    }),
  )
  guard logging is Some(Object({ "result": Object(_), .. })) else {
    fail("expected empty logging result")
  }
  assert_true(server.logging_level() == @mcp.LoggingLevel::Debug)
  let ping = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(2.0, repr="2"),
      "method": Json::string("ping"),
    }),
  )
  guard ping is Some(Object({ "result": Object(_), .. })) else {
    fail("expected empty ping result")
  }
  let notification = @mcp.progress_notification(
    progress_token=Json::string("token"),
    progress=0.5,
    total=1.0,
    message="half",
  )
  guard notification
    is Object(
      {
        "method": String("notifications/progress"),
        "params": Object({ "message": String("half"), .. }),
        ..
      }
    ) else {
    fail("expected progress notification")
  }
}
