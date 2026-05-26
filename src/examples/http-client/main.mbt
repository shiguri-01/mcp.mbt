///|
async fn main {
  let client = @mcp_http.Client("http://127.0.0.1:8080/mcp")
  let initialize = try! client.initialize(
    client_name="http-client-example",
    client_version="0.1.0",
  )
  println(initialize.stringify(indent=2))
  let session = client.session_id().unwrap_or("<none>")
  println("session: \{session}")
  println((try! client.list_tools()).stringify(indent=2))
  println(
    (try! client.call_tool(
      name="hello",
      arguments=Json::object({ "name": Json::string("MoonBit") }),
    )).stringify(indent=2),
  )
  try! client.close_session()
}
