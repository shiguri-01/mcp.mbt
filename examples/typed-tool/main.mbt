///|
struct AddInput {
  left : Int
  right : Int
} derive(FromJson)

///|
struct AddOutput {
  sum : Int
} derive(ToJson)

///|
fn main {
  let server = @mcp.Server(name="typed-tool-example", version="0.1.0")
  let input_schema = @mcp.object([
    @mcp.integer_prop(name="left", required=true),
    @mcp.integer_prop(name="right", required=true),
  ])
  try! server.add_tool(
    name="add",
    description="Add two integers with FromJson/ToJson",
    input_schema~,
    fn(input : AddInput) -> AddOutput { { sum: input.left + input.right } },
  )
  let result = try! server.handle(
    "tools/call",
    Some(
      Json::object({
        "name": Json::string("add"),
        "arguments": Json::object({
          "left": Json::number(20.0, repr="20"),
          "right": Json::number(22.0, repr="22"),
        }),
      }),
    ),
  )
  println(result.unwrap().stringify(indent=2))
}
