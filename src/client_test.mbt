///|
test "client builds protocol requests" {
  let client = @mcp.Client()
  let initialize = client.initialize_request(
    client_name="test-client",
    client_version="0.1.0",
    client_title="Test Client",
    capabilities=ClientCapabilities(
      roots=RootsCapability(list_changed=true),
      sampling=SamplingCapability(tools=true),
      elicitation=ElicitationCapability(form=true, url=true),
    ),
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
  guard init_params["capabilities"] is Object(capabilities) else {
    fail("expected capabilities")
  }
  guard capabilities["roots"] is Object(roots) else {
    fail("expected roots capability")
  }
  assert_true(roots["listChanged"] == Json::boolean(true))
  guard capabilities["sampling"] is Object(sampling) else {
    fail("expected sampling capability")
  }
  assert_true(sampling.contains("tools"))
  guard capabilities["elicitation"] is Object(elicitation) else {
    fail("expected elicitation capability")
  }
  assert_true(elicitation.contains("form"))
  assert_true(elicitation.contains("url"))
  let call = client.call_tool_request(
    name="echo",
    arguments=Json::object({ "text": Json::string("hi") }),
  )
  guard call is Object(call_fields) else { fail("expected call request") }
  assert_true(call_fields["method"] == Json::string("tools/call"))
  guard call_fields["params"] is Object(params) else { fail("expected params") }
  assert_true(params["name"] == Json::string("echo"))
}
