///|
async test "initialize returns server metadata and capabilities" {
  let server = @mcp.Server(name="test-server", version="0.1.0")
  let response = server.handle_jsonrpc(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("initialize"),
      "params": Json::object({}),
    }),
  )
  guard response is Some(Object(fields)) else {
    fail("expected JSON-RPC response")
  }
  guard fields["result"] is Object(result) else {
    fail("expected initialize result")
  }
  assert_true(
    result["protocolVersion"] == Json::string(@mcp.latest_protocol_version),
  )
  guard result["serverInfo"] is Object(info) else {
    fail("expected serverInfo")
  }
  assert_true(info["name"] == Json::string("test-server"))
}
