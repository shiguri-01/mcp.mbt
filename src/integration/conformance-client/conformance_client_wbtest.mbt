///|
test "client metadata declares every frozen MRTR capability" {
  assert_true(
    conformance_capabilities().to_json()
    is Object(
      {
        "roots": Object(_),
        "sampling": Object(_),
        "elicitation": Object({ "form": Object(_), .. }),
        ..
      }
    ),
  )
}

///|
test "listed entity identity is preserved in follow-up requests" {
  assert_eq(
    try! first_tool_name(
      Json::object({
        "tools": Json::array([Json::object({ "name": Json::string("tool-a") })]),
      }),
    ),
    "tool-a",
  )
  assert_eq(
    try! first_resource_uri(
      Json::object({
        "resources": Json::array([
          Json::object({ "uri": Json::string("test://resource-a") }),
        ]),
      }),
    ),
    "test://resource-a",
  )
  assert_eq(
    try! first_prompt_name(
      Json::object({
        "prompts": Json::array([
          Json::object({ "name": Json::string("prompt-a") }),
        ]),
      }),
    ),
    "prompt-a",
  )
}

///|
test "elicitation input is accepted with the required confirmation content" {
  let responses = try! accept_elicitation_requests({
    "confirmation": @mcp.InputRequest(
      method_name="elicitation/create",
      params=Json::object({
        "message": Json::string("Confirm the request"),
        "requestedSchema": Json::object({
          "type": Json::string("object"),
          "properties": Json::object({
            "confirmed": Json::object({ "type": Json::string("boolean") }),
          }),
          "required": Json::array([Json::string("confirmed")]),
        }),
      }),
    ),
  })
  assert_true(
    responses["confirmation"].result()
    is Object(
      {
        "action": String("accept"),
        "content": Object({ "confirmed": True, .. }),
        ..
      }
    ),
  )
}
