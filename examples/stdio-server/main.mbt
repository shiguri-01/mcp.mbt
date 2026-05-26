///|
async fn main {
  let server = @mcp.Server(
    name="stdio-example",
    version="0.1.0",
    instructions="A minimal MoonBit MCP server over stdio.",
  )
  try! server.tool_text(
    name="hello",
    description="Return a greeting",
    input_schema=@mcp.object_schema(
      properties={
        "name": @mcp.string_property_schema(description="Name to greet"),
      },
      required=["name"],
    ),
    fn(arguments) -> String raise @mcp.McpError {
      match arguments {
        Some(Object({ "name": String(name), .. })) => "Hello, \{name}!"
        _ => raise @mcp.InvalidParams("name must be a string")
      }
    },
  )
  try! server.resource_text(
    uri="memory://status",
    name="status",
    description="Server status",
    mime_type="text/plain",
    fn(_) { "ready" },
  )
  try! server.prompt_text(
    name="summarize",
    description="Create a short summarization prompt",
    arguments=[
      @mcp.PromptArgument::{
        name: "topic",
        title: None,
        description: None,
        required: true,
      },
    ],
    fn(arguments) raise @mcp.McpError {
      match arguments.get("topic") {
        Some(topic) => "Summarize \{topic} in three concise bullets."
        None => raise @mcp.InvalidParams("topic is required")
      }
    },
  )
  @mcp_stdio.serve(server)
}
