///|
struct EchoInput {
  text : String
} derive(FromJson)

///|
impl @schema.JsonSchema for EchoInput with fn json_schema() {
  @schema.schema([@schema.string(name="text", required=true)])
}

///|
struct EchoOutput {
  echoed : String
} derive(FromJson, ToJson)

///|
async test "json tool can be listed and called" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  let schema = @schema.schema([
    @schema.string(name="name", description="Name to greet", required=true),
  ])
  try! server.json_tool(
    name="greet",
    description="Return a greeting",
    input_schema=schema,
    fn(arguments) raise @mcp.McpError {
      let fields = match arguments {
        Some(Object(fields)) => fields
        _ => raise @mcp.InvalidParams("arguments are required")
      }
      match fields.get("name") {
        Some(String(name)) => @mcp.CallToolResult::text("Hello, \{name}!")
        _ => raise @mcp.InvalidParams("name is required")
      }
    },
  )

  let list_response = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("tools/list"),
    }),
  )
  guard list_response is Some(Object({ "result": Object(list), .. })) else {
    fail("expected tools/list response")
  }
  guard list["tools"] is Array([Object(tool)]) else {
    fail("expected one tool")
  }
  assert_true(tool["name"] == Json::string("greet"))

  let call_response = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(2.0, repr="2"),
      "method": Json::string("tools/call"),
      "params": Json::object({
        "name": Json::string("greet"),
        "arguments": Json::object({ "name": Json::string("MoonBit") }),
      }),
    }),
  )
  guard call_response is Some(Object({ "result": Object(call), .. })) else {
    fail("expected tools/call response")
  }
  guard call["content"] is Array([Object(text)]) else {
    fail("expected text content")
  }
  assert_true(text["text"] == Json::string("Hello, MoonBit!"))
}

///|
async test "tool decodes input and encodes structured content" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  try! server.tool(name="echo", fn(input : EchoInput) {
    @mcp.CallToolResult::structured(({ echoed: input.text } : EchoOutput))
  })
  let response = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("tools/call"),
      "params": Json::object({
        "name": Json::string("echo"),
        "arguments": Json::object({ "text": Json::string("ok") }),
      }),
    }),
  )
  guard response is Some(Object({ "result": Object(result), .. })) else {
    fail("expected result")
  }
  assert_true(
    result["structuredContent"] ==
    Json::object({ "echoed": Json::string("ok") }),
  )
}

///|
async test "tool decodes input and returns text content" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  try! server.tool(name="echo_text", fn(input : EchoInput) {
    @mcp.CallToolResult::text(input.text)
  })
  let response = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("tools/call"),
      "params": Json::object({
        "name": Json::string("echo_text"),
        "arguments": Json::object({ "text": Json::string("ok") }),
      }),
    }),
  )
  guard response
    is Some(
      Object(
        { "result": Object({ "content": Array([Object(content)]), .. }), .. }
      )
    ) else {
    fail("expected text content")
  }
  assert_true(content["text"] == Json::string("ok"))
}

///|
test "structured content decodes through FromJson" {
  let decoded : EchoOutput = try! @mcp.decode_structured_content(
    Json::object({
      "content": Json::array([]),
      "structuredContent": Json::object({ "echoed": Json::string("ok") }),
    }),
  )
  assert_true(decoded.echoed == "ok")
}
