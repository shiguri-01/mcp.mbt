///|
fn print_response(response : Json?) -> Unit {
  match response {
    Some(json) => println(json.stringify(indent=2))
    None => println("notification accepted")
  }
}

///|
fn main {
  let server = @mcp.Server(
    name="jsonrpc-example",
    version="0.1.0",
    instructions="Example server that handles JSON-RPC MCP messages.",
  )
  try! server.add_text_tool(name="ping", description="Return pong", fn(_) {
    "pong"
  })
  print_response(
    server.handle_jsonrpc(
      Json::object({
        "jsonrpc": Json::string("2.0"),
        "id": Json::number(1.0, repr="1"),
        "method": Json::string("initialize"),
        "params": Json::object({}),
      }),
    ),
  )
  print_response(
    server.handle_jsonrpc(
      Json::object({
        "jsonrpc": Json::string("2.0"),
        "method": Json::string("notifications/initialized"),
      }),
    ),
  )
  print_response(
    server.handle_jsonrpc(
      Json::object({
        "jsonrpc": Json::string("2.0"),
        "id": Json::number(2.0, repr="2"),
        "method": Json::string("tools/list"),
      }),
    ),
  )
  print_response(
    server.handle_jsonrpc(
      Json::object({
        "jsonrpc": Json::string("2.0"),
        "id": Json::number(3.0, repr="3"),
        "method": Json::string("tools/call"),
        "params": Json::object({
          "name": Json::string("ping"),
          "arguments": Json::object({}),
        }),
      }),
    ),
  )
}
