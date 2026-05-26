///|
struct PromptInput {
  topic : String
} derive(FromJson)

///|
impl @mcp.PromptArguments for PromptInput with fn prompt_arguments() {
  [@mcp.PromptArgument(name="topic", required=true)]
}

///|
test "prompt decodes string arguments" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  try! server.prompt(name="summarize_typed", fn(input : PromptInput) {
    @mcp.GetPromptResult::user("Summarize \{input.topic}.")
  })
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
test "resources and string prompts are dispatchable" {
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
  try! server.string_prompt(
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
