///|
test "initialize returns server metadata and capabilities" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  let response = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("initialize"),
      "params": Json::object({}),
    }),
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
}

///|
test "raw tool can be listed and called" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  let schema = @mcp.object([
    @mcp.string_prop(name="name", description="Name to greet", required=true),
  ])
  try! server.tool(
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

  let list_response = try! server.handle("tools/list", None)
  guard list_response is Some(Object(list)) else {
    fail("expected tools/list result")
  }
  guard list["tools"] is Array([Object(tool)]) else {
    fail("expected one tool")
  }
  assert_true(tool["name"] == Json::string("greet"))

  let call_response = try! server.handle(
    "tools/call",
    Some(
      Json::object({
        "name": Json::string("greet"),
        "arguments": Json::object({ "name": Json::string("MoonBit") }),
      }),
    ),
  )
  guard call_response is Some(Object(call)) else {
    fail("expected tools/call result")
  }
  guard call["content"] is Array([Object(text)]) else {
    fail("expected text content")
  }
  assert_true(text["text"] == Json::string("Hello, MoonBit!"))
}

///|
struct EchoInput {
  text : String
} derive(FromJson)

///|
struct EchoOutput {
  echoed : String
} derive(FromJson, ToJson)

///|
test "typed tool decodes input and encodes structured content" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  try! server.typed_tool(
    name="echo",
    input_schema=@mcp.object([@mcp.string_prop(name="text", required=true)]),
    fn(input : EchoInput) {
      @mcp.CallToolResult::structured(({ echoed: input.text } : EchoOutput))
    },
  )
  let response = try! server.handle(
    "tools/call",
    Some(
      Json::object({
        "name": Json::string("echo"),
        "arguments": Json::object({ "text": Json::string("ok") }),
      }),
    ),
  )
  guard response is Some(Object(result)) else { fail("expected result") }
  assert_true(
    result["structuredContent"] ==
    Json::object({ "echoed": Json::string("ok") }),
  )
}

///|
test "typed text tool decodes input and returns text content" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  try! server.typed_tool(
    name="echo_text",
    input_schema=@mcp.object([@mcp.string_prop(name="text", required=true)]),
    fn(input : EchoInput) { @mcp.CallToolResult::text(input.text) },
  )
  let response = try! server.handle(
    "tools/call",
    Some(
      Json::object({
        "name": Json::string("echo_text"),
        "arguments": Json::object({ "text": Json::string("ok") }),
      }),
    ),
  )
  guard response is Some(Object({ "content": Array([Object(content)]), .. })) else {
    fail("expected text content")
  }
  assert_true(content["text"] == Json::string("ok"))
}

///|
struct PromptInput {
  topic : String
} derive(FromJson)

///|
test "typed text prompt decodes string arguments" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  try! server.typed_prompt(
    name="summarize_typed",
    arguments=[@mcp.PromptArgument(name="topic", required=true)],
    fn(input : PromptInput) {
      @mcp.GetPromptResult::user("Summarize \{input.topic}.")
    },
  )
  let prompt = try! server.handle(
    "prompts/get",
    Some(
      Json::object({
        "name": Json::string("summarize_typed"),
        "arguments": Json::object({ "topic": Json::string("MCP") }),
      }),
    ),
  )
  guard prompt is Some(Object({ "messages": Array([Object(message)]), .. })) else {
    fail("expected prompt message")
  }
  guard message["content"] is Object(content) else {
    fail("expected prompt content")
  }
  assert_true(content["text"] == Json::string("Summarize MCP."))
}

///|
test "resources and prompts are dispatchable" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  try! server.resource(
    uri="memory://status",
    name="status",
    description="Current status",
    mime_type="text/plain",
    fn(uri) {
      @mcp.ReadResourceResult::text(uri~, text="ready", mime_type="text/plain")
    },
  )
  try! server.prompt(
    name="summarize",
    description="Build a summarize prompt",
    arguments=[@mcp.PromptArgument(name="topic", required=true)],
    fn(arguments) raise @mcp.McpError {
      match arguments.get("topic") {
        Some(topic) => @mcp.GetPromptResult::user("Summarize \{topic}.")
        None => raise @mcp.InvalidParams("topic is required")
      }
    },
  )
  let resources = try! server.handle("resources/list", None)
  guard resources
    is Some(Object({ "resources": Array([Object(resource)]), .. })) else {
    fail("expected one resource")
  }
  assert_true(resource["uri"] == Json::string("memory://status"))
  let read = try! server.handle(
    "resources/read",
    Some(Json::object({ "uri": Json::string("memory://status") })),
  )
  guard read is Some(Object({ "contents": Array([Object(content)]), .. })) else {
    fail("expected resource content")
  }
  assert_true(content["text"] == Json::string("ready"))
  let prompt = try! server.handle(
    "prompts/get",
    Some(
      Json::object({
        "name": Json::string("summarize"),
        "arguments": Json::object({ "topic": Json::string("MCP") }),
      }),
    ),
  )
  guard prompt is Some(Object({ "messages": Array([Object(message)]), .. })) else {
    fail("expected prompt message")
  }
  guard message["content"] is Object(prompt_content) else {
    fail("expected prompt text content")
  }
  assert_true(prompt_content["text"] == Json::string("Summarize MCP."))
}

///|
test "client builds protocol requests" {
  let client = @mcp.Client()
  let initialize = client.initialize_request(
    client_name="test-client",
    client_version="0.1.0",
  )
  guard initialize is Object(init) else { fail("expected initialize request") }
  assert_true(init["method"] == Json::string("initialize"))
  let call = client.call_tool_request(
    name="echo",
    arguments=Json::object({ "text": Json::string("hi") }),
  )
  guard call is Object(call_fields) else { fail("expected call request") }
  assert_true(call_fields["method"] == Json::string("tools/call"))
  guard call_fields["params"] is Object(params) else { fail("expected params") }
  assert_true(params["name"] == Json::string("echo"))
}

///|
test "ergonomic helpers build useful schemas and decode structured content" {
  let schema = @mcp.object([
    @mcp.integer_prop(
      name="count",
      description="Number of items",
      required=true,
    ),
    @mcp.string_enum_prop(
      name="mode",
      values=["fast", "safe"],
      description="Run mode",
    ),
    @mcp.array_prop(
      name="flags",
      items=@mcp.string(),
      description="Feature flags",
    ),
  ])
  guard schema is Object({ "properties": Object(properties), .. }) else {
    fail("expected object schema")
  }
  assert_true(properties.contains("count"))
  let decoded : EchoOutput = try! @mcp.decode_structured_content(
    Json::object({
      "content": Json::array([]),
      "structuredContent": Json::object({ "echoed": Json::string("ok") }),
    }),
  )
  assert_true(decoded.echoed == "ok")
}
