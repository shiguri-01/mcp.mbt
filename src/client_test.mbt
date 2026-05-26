///|
test "client builds protocol requests" {
  let client = @mcp.Client()
  let initialize = client.initialize_request(
    client_name="test-client",
    client_version="0.1.0",
  )
  guard initialize is Object(init) else { fail("expected initialize request") }
  assert_true(init["method"] == Json::string("initialize"))
  let call = client.call_tool_request(
    name="echo",
    arguments=Json::object({ "text": Json::string("hi") }),
  )
  guard call is Object(call_fields) else { fail("expected call request") }
  assert_true(call_fields["method"] == Json::string("tools/call"))
  guard call_fields["params"] is Object(params) else { fail("expected params") }
  assert_true(params["name"] == Json::string("echo"))
}
