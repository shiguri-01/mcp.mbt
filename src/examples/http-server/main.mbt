///|
struct GreetInput {
  name : String
} derive(FromJson)

///|
impl @schema.JsonSchema for GreetInput with fn json_schema() -> @schema.Schema raise @schema.SchemaError {
  @schema.object([
    @schema.string(name="name", description="Name to greet", required=true),
  ])
}

///|
fn make_server() -> @mcp.Server {
  let server = try! @mcp.Server(
    name="http-greeter",
    version="1.0.0",
    instructions="Call greet with a name to receive a greeting.",
  )
  try! server.tool(name="greet", description="Greet someone by name", fn(
    _context,
    input : GreetInput,
  ) -> @mcp.HandlerOutcome[@mcp.CallToolResult] {
    @mcp.Complete(@mcp.CallToolResult::text("Hello, \{input.name}!"))
  })
  server
}

///|
async fn main {
  let http_server = @async_http.Server(@socket.Addr::parse("127.0.0.1:8080"))
  let server = make_server()
  println("MCP endpoint: http://127.0.0.1:8080/mcp")
  @mcp_http.serve(
    http_server,
    server,
    options=@mcp_http.ServerOptions(endpoint_path="/mcp"),
  )
}
