///|
struct HelloInput {
  name : String
} derive(FromJson)

///|
impl @schema.JsonSchema for HelloInput with fn json_schema() {
  @schema.schema([
    @schema.string(name="name", description="Name to greet", required=true),
  ])
}

///|
fn make_server() -> @mcp.Server {
  let server = @mcp.Server(
    name="http-example",
    version="0.1.0",
    instructions="A minimal MoonBit MCP server over Streamable HTTP.",
  )
  try! server.tool(name="hello", description="Return a greeting", fn(
    input : HelloInput,
  ) {
    @mcp.CallToolResult::text("Hello, \{input.name}!")
  })
  server
}

///|
async fn main {
  let http_server = @async_http.Server(@socket.Addr::parse("127.0.0.1:8080"))
  println("MCP Streamable HTTP endpoint: http://127.0.0.1:8080/mcp")
  @mcp_http.serve(
    http_server,
    make_server,
    options=@mcp_http.ServerOptions(session_id_generator=fn() {
      "example-\{@async.now()}"
    }),
  )
}
