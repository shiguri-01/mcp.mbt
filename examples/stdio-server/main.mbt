///|
async fn main {
  let server = @mcp.Server::new(
    name="stdio-example",
    version="0.1.0",
    instructions="A minimal MoonBit MCP server over stdio.",
  )
  try! server.add_text_tool(
    @mcp.Tool::new(
      name="hello",
      description="Return a greeting",
      input_schema=@mcp.object_schema(
        properties={
          "name": @mcp.string_property_schema(description="Name to greet"),
        },
        required=["name"],
      ),
    ),
    fn(arguments) -> String raise @mcp.McpError {
      match arguments {
        Some(Object({ "name": String(name), .. })) => "Hello, \{name}!"
        _ => raise @mcp.InvalidParams("name must be a string")
      }
    },
  )
  @mcp_stdio.serve(server)
}
