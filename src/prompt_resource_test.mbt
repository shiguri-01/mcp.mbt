///|
struct PromptInput {
  topic : String
} derive(FromJson)

///|
impl @mcp.PromptArguments for PromptInput with fn prompt_arguments() {
  [@mcp.PromptArgument(name="topic", required=true)]
}

///|
async fn initialize_prompt_resource_test_server(server : @mcp.Server) -> Unit {
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
async test "prompt decodes string arguments" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  try! server.prompt(name="summarize_typed", fn(input : PromptInput) {
    @mcp.GetPromptResult::user("Summarize \{input.topic}.")
  })
  initialize_prompt_resource_test_server(server)
  let prompt = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("prompts/get"),
      "params": Json::object({
        "name": Json::string("summarize_typed"),
        "arguments": Json::object({ "topic": Json::string("MCP") }),
      }),
    }),
  )
  guard prompt
    is Some(
      Object(
        { "result": Object({ "messages": Array([Object(message)]), .. }), .. }
      )
    ) else {
    fail("expected prompt message")
  }
  guard message["content"] is Object(content) else {
    fail("expected prompt content")
  }
  assert_true(content["text"] == Json::string("Summarize MCP."))
}

///|
async test "resources and string prompts are dispatchable" {
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
  initialize_prompt_resource_test_server(server)
  let resources = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("resources/list"),
    }),
  )
  guard resources
    is Some(
      Object(
        { "result": Object({ "resources": Array([Object(resource)]), .. }), .. }
      )
    ) else {
    fail("expected one resource")
  }
  assert_true(resource["uri"] == Json::string("memory://status"))
  let read = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(2.0, repr="2"),
      "method": Json::string("resources/read"),
      "params": Json::object({ "uri": Json::string("memory://status") }),
    }),
  )
  guard read
    is Some(
      Object(
        { "result": Object({ "contents": Array([Object(content)]), .. }), .. }
      )
    ) else {
    fail("expected resource content")
  }
  assert_true(content["text"] == Json::string("ready"))
  let prompt = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(3.0, repr="3"),
      "method": Json::string("prompts/get"),
      "params": Json::object({
        "name": Json::string("summarize"),
        "arguments": Json::object({ "topic": Json::string("MCP") }),
      }),
    }),
  )
  guard prompt
    is Some(
      Object(
        { "result": Object({ "messages": Array([Object(message)]), .. }), .. }
      )
    ) else {
    fail("expected prompt message")
  }
  guard message["content"] is Object(prompt_content) else {
    fail("expected prompt text content")
  }
  assert_true(prompt_content["text"] == Json::string("Summarize MCP."))
}
