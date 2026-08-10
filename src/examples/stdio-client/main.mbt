///|
async fn main {
  @async.with_task_group <| group => {
    let server_executable = match @env.get_env_var("MCP_STDIO_SERVER") {
      Some(value) => value
      None =>
        abort("MCP_STDIO_SERVER must name a built stdio server executable")
    }
    let client = try! @mcp_stdio.Client::spawn(
      group,
      server_executable,
      name="stdio-example-client",
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
        println(result.stringify(indent=2))
      @mcp.HandlerOutcome::InputRequired(request) =>
        println(request.to_json().stringify(indent=2))
      @mcp.HandlerOutcome::ExtensionResult(_, result) =>
        println(result.stringify(indent=2))
    }
    try! client.shutdown()
  }
}
