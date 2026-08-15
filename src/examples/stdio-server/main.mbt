///|
struct GreetInput {
  name : String
} derive(FromJson)

///|

///|
impl @schema.JsonSchema for GreetInput with fn json_schema() -> @schema.Schema {
  @schema.ObjectSchema(
    properties={
      "name": @schema.StringSchema(description="Name to greet").into_schema(),
    },
    required=["name"],
  ).into_schema()
}

///|
async fn main {
  let server = try! @mcp_server.Server(
    name="stdio-greeter",
    version="1.0.0",
    instructions="Call greet with a name to receive a greeting.",
  )
  try! server.tool(name="greet", description="Greet someone by name", fn(
    _context,
    input : GreetInput,
  ) -> @mcp.HandlerOutcome[@mcp.CallToolResult] {
    @mcp.Complete(@mcp.CallToolResult::text("Hello, \{input.name}!"))
  })
  @mcp_stdio.serve(server)
}
