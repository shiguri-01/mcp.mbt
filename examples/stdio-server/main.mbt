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
  try! server.typed_text_tool(
    name="hello",
    description="Return a greeting",
    input_schema=@mcp.object([
      @mcp.string_prop(name="name", description="Name to greet", required=true),
    ]),
    fn(input : HelloInput) { "Hello, \{input.name}!" },
  )
  try! server.text_resource(
    uri="memory://status",
    name="status",
    description="Server status",
    mime_type="text/plain",
    fn(_) { "ready" },
  )
  try! server.typed_text_prompt(
    name="summarize",
    description="Create a short summarization prompt",
    arguments=[@mcp.PromptArgument(name="topic", required=true)],
    fn(input : SummarizeInput) {
      "Summarize \{input.topic} in three concise bullets."
    },
  )
  @mcp_stdio.serve(server)
}
