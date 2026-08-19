///|
struct GreetInput {
  name : String
} derive(FromJson)

///|

///|
impl @schema.JsonSchema for GreetInput with fn json_schema() -> @schema.Schema {
  @schema.Schema::object(
    properties={ "name": @schema.Schema::string(description="Name to greet") },
    required=["name"],
  )
}

///|
async fn main {
  let builder = try! @mcp_server.ServerBuilder(
    name="stdio-greeter",
    version="1.0.0",
    instructions="Call greet with a name to receive a greeting.",
  )
  try! builder.tool(name="greet", description="Greet someone by name", fn(
    _context,
    input : GreetInput,
  ) -> @mcp.HandlerOutcome[@mcp.CallToolResult] {
    @mcp.Complete(@mcp.CallToolResult::text("Hello, \{input.name}!"))
  })
  let server = builder.build()
  @mcp_stdio.serve(server)
}
