///|
async fn main {
  @async.with_task_group <| group => {
    let client = @mcp_stdio.Client::spawn(group, "moon", args=[
      "run", "--target", "native", "examples/stdio-server",
    ])
    let initialize = try! client.initialize(
      client_name="stdio-client-example",
      client_version="0.1.0",
    )
    println(initialize.stringify(indent=2))
    println((try! client.list_tools()).stringify(indent=2))
    println(
      (try! client.call_tool(
        name="hello",
        arguments=Json::object({ "name": Json::string("MoonBit") }),
      )).stringify(indent=2),
    )
    println((try! client.list_resources()).stringify(indent=2))
    println(
      (try! client.read_resource(uri="memory://status")).stringify(indent=2),
    )
    println(
      (try! client.get_prompt(
        name="summarize",
        arguments=Json::object({ "topic": Json::string("MCP") }),
      )).stringify(indent=2),
    )
    client.close()
  }
}
