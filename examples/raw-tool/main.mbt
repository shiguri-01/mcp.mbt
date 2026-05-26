///|
fn main {
  let server = @mcp.Server::new(name="raw-tool-example", version="0.1.0")
  let input_schema = @mcp.object_schema(
    properties={
      "name": @mcp.string_property_schema(description="Name to greet"),
    },
    required=["name"],
  )
  try! server.add_text_tool(
    @mcp.Tool::new(
      name="greet",
      description="Build a greeting from raw JSON arguments",
      input_schema~,
    ),
    fn(arguments) -> String raise @mcp.McpError {
      match arguments {
        Some(Object({ "name": String(name), .. })) => "Hello, \{name}!"
        _ => raise @mcp.InvalidParams("name must be a string")
      }
    },
  )
  let result = try! server.handle(
    "tools/call",
    Some(
      Json::object({
        "name": Json::string("greet"),
        "arguments": Json::object({ "name": Json::string("MoonBit") }),
      }),
    ),
  )
  println(result.unwrap().stringify(indent=2))
}
