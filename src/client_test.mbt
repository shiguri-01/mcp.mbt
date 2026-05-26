///|
test "client builds protocol requests" {
  let client = @mcp.Client()
  let initialize = client.initialize_request(
    client_name="test-client",
    client_version="0.1.0",
    client_title="Test Client",
  )
  guard initialize is Object(init) else { fail("expected initialize request") }
  assert_true(init["method"] == Json::string("initialize"))
  guard init["params"] is Object(init_params) else {
    fail("expected initialize params")
  }
  guard init_params["clientInfo"] is Object(client_info) else {
    fail("expected clientInfo")
  }
  assert_true(client_info["title"] == Json::string("Test Client"))
  let call = client.call_tool_request(
    name="echo",
    arguments=Json::object({ "text": Json::string("hi") }),
  )
  guard call is Object(call_fields) else { fail("expected call request") }
  assert_true(call_fields["method"] == Json::string("tools/call"))
  guard call_fields["params"] is Object(params) else { fail("expected params") }
  assert_true(params["name"] == Json::string("echo"))
}
