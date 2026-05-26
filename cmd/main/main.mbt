///|
fn main {
  let server = @mcp.Server(name="example", version="0.1.0")
  try! server.tool(name="hello", description="Return a greeting", fn(_) {
    @mcp.CallToolResult::text("Hello from MoonBit MCP")
  })
  let result = try! server.handle("tools/list", None)
  println(result.unwrap().stringify(indent=2))
}
