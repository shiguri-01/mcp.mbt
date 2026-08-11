///|
async fn main {
  let client = try! @mcp_http.Client(
    "http://127.0.0.1:8080/mcp",
    name="http-example-client",
    version="1.0.0",
  )
  let discovered = try! client.discover()
  println(discovered.to_json().stringify(indent=2))

  match
    (try! client.call_tool(
      name="greet",
      arguments=Json::object({ "name": Json::string("MoonBit") }),
    )) {
    @mcp.HandlerOutcome::Complete(result) =>
      println(result.to_json().stringify(indent=2))
    @mcp.HandlerOutcome::InputRequired(request) =>
      println(request.to_json().stringify(indent=2))
    @mcp.HandlerOutcome::ExtensionResult(_, result) =>
      println(result.stringify(indent=2))
  }
}
