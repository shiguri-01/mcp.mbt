///|
struct HelloInput {
  name : String
} derive(FromJson)

///|
impl @schema.JsonSchema for HelloInput with fn json_schema() {
  @schema.schema([
    @schema.string_field(
      name="name",
      description="Name to greet",
      required=true,
    ),
  ])
}

///|
struct SummarizeInput {
  topic : String
} derive(FromJson)

///|
impl @mcp.PromptArguments for SummarizeInput with fn prompt_arguments() {
  [@mcp.PromptArgument(name="topic", required=true)]
}

///|
async fn main {
  let server = @mcp.Server(
    name="stdio-example",
    version="0.1.0",
    instructions="A minimal MoonBit MCP server over stdio.",
  )
  try! server.tool(name="hello", description="Return a greeting", fn(
    input : HelloInput,
  ) {
    @mcp.CallToolResult::text("Hello, \{input.name}!")
  })
  try! server.resource(
    uri="memory://status",
    name="status",
    description="Server status",
    mime_type="text/plain",
    fn(uri) {
      @mcp.ReadResourceResult::text(uri~, text="ready", mime_type="text/plain")
    },
  )
  try! server.prompt(
    name="summarize",
    description="Create a short summarization prompt",
    fn(input : SummarizeInput) {
      @mcp.GetPromptResult::user(
        "Summarize \{input.topic} in three concise bullets.",
      )
    },
  )
  @mcp_stdio.serve(server)
}
