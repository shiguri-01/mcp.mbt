///|
struct GreetInput {
  name : String
} derive(FromJson)

///|
impl @schema.JsonSchema for GreetInput with fn json_schema() {
  @schema.schema([
    @schema.string(name="name", description="Name to greet", required=true),
  ])
}

///|
async fn main {
  let server = try! @mcp.Server(
    name="stdio-greeter",
    version="1.0.0",
    instructions="Call greet with a name to receive a greeting.",
  )
  try! server.simple_tool(name="greet", description="Greet someone by name", (
    input : GreetInput,
  ) => @mcp.CallToolResult::text("Hello, \{input.name}!"))
  @mcp_stdio.serve(server)
}
