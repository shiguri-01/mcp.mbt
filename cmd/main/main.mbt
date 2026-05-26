///|
fn main {
  let server = @mcp.Server::new(name="example", version="0.1.0")
  try! server.add_text_tool(
    @mcp.Tool::Tool(
      name="hello",
      description="Return a greeting",
      input_schema=@mcp.empty_object_schema(),
    ),
    fn(_) { "Hello from MoonBit MCP" },
  )
  let result = try! server.handle("tools/list", None)
  println(result.unwrap().stringify(indent=2))
}
