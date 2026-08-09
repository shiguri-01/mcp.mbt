///|
async fn main {
  @async.with_task_group <| group => {
    let client = @mcp_stdio.Client::spawn(
      group,
      "moon",
      name="stdio-example-client",
      version="1.0.0",
      args=["run", "--target", "native", "src/examples/stdio-server"],
    )
    let discovered = try! client.discover()
    println(discovered.to_json().stringify(indent=2))

    match
      (try! client.call_tool(
        name="greet",
        arguments=Json::object({ "name": Json::string("MoonBit") }),
      )) {
      @mcp.HandlerOutcome::Complete(result) =>
        println(result.stringify(indent=2))
      @mcp.HandlerOutcome::InputRequired(request) =>
        println(request.to_json().stringify(indent=2))
    }
    client.close()
  }
}
