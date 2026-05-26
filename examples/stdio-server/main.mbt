///|
struct HelloInput {
  name : String
} derive(FromJson)

///|
struct SummarizeInput {
  topic : String
} derive(FromJson)

///|
async fn main {
  let server = @mcp.Server(
    name="stdio-example",
    version="0.1.0",
    instructions="A minimal MoonBit MCP server over stdio.",
  )
  try! server.tool(
    name="hello",
    description="Return a greeting",
    input_schema=@mcp.object([
      @mcp.string_prop(name="name", description="Name to greet", required=true),
    ]),
    fn(input : HelloInput) {
      @mcp.CallToolResult::text("Hello, \{input.name}!")
    },
  )
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
    arguments=[@mcp.PromptArgument(name="topic", required=true)],
    fn(input : SummarizeInput) {
      @mcp.GetPromptResult::user(
        "Summarize \{input.topic} in three concise bullets.",
      )
    },
  )
  @mcp_stdio.serve(server)
}
