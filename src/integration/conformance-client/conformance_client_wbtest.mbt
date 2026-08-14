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
    responses["confirmation"].result
    is Object(
      {
        "action": String("accept"),
        "content": Object({ "confirmed": True, .. }),
        ..
      }
    ),
  )
}

///|
test "frozen authorization scenarios have an explicit dispatch contract" {
  let scenarios = [
    "auth/metadata-default", "auth/metadata-var1", "auth/metadata-var2", "auth/metadata-var3",
    "auth/basic-cimd", "auth/scope-from-www-authenticate", "auth/scope-from-scopes-supported",
    "auth/scope-omitted-when-undefined", "auth/scope-step-up", "auth/scope-retry-limit",
    "auth/token-endpoint-auth-basic", "auth/token-endpoint-auth-post", "auth/token-endpoint-auth-none",
    "auth/pre-registration", "auth/resource-mismatch", "auth/offline-access-scope",
    "auth/offline-access-not-supported", "auth/authorization-server-migration", "auth/iss-supported",
    "auth/iss-not-advertised", "auth/iss-supported-missing", "auth/iss-wrong-issuer",
    "auth/iss-unexpected", "auth/iss-normalized", "auth/metadata-issuer-mismatch",
  ]
  assert_eq(scenarios.length(), 25)
  assert_true(scenarios.all(frozen_auth_scenario))
  assert_false(frozen_auth_scenario("auth/client-credentials-basic"))
}

///|
test "pre-registration context is scenario-bound and complete" {
  let context = try! parse_pre_registration_context(
    Some(
      Json::object({
        "name": Json::string("auth/pre-registration"),
        "client_id": Json::string("registered-client"),
        "client_secret": Json::string("registered-secret"),
      }).stringify(),
    ),
  )
  assert_eq(context.client_id, "registered-client")
  assert_eq(context.client_secret, "registered-secret")
  let rejected = try
    parse_pre_registration_context(
      Some(
        Json::object({
          "name": Json::string("auth/pre-registration"),
          "client_id": Json::string("registered-client"),
        }).stringify(),
      ),
    )
  catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(rejected)
}
