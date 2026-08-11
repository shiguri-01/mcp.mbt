///|
test "deprecated MRTR methods require and accept matching capabilities" {
  let server = try! Server(name="server", version="1")
  let result = try! InputRequiredResult(input_requests={
    "roots": try! InputRequest(method_name="roots/list"),
    "sampling": try! InputRequest(
      method_name="sampling/createMessage",
      params=Json::object({
        "messages": Json::array([
          Json::object({
            "role": Json::string("user"),
            "content": Json::object({
              "type": Json::string("text"),
              "text": Json::string("hello"),
            }),
          }),
        ]),
        "maxTokens": Json::number(1.0),
      }),
    ),
  })
  let context = try! RequestContext(
    request_id=Json::number(1.0),
    method_name="tools/call",
    meta=RequestMeta(
      client_capabilities=ClientCapabilities(
        deprecated=DeprecatedClientCapabilities(
          roots=Json::object({}),
          sampling=Json::object({}),
        ),
      ),
    ),
  )
  try! server.validate_input_requests(context, result)

  let missing = try! RequestContext(
    request_id=Json::number(2.0),
    method_name="tools/call",
    meta=RequestMeta(),
  )
  try server.validate_input_requests(missing, result) catch {
    MissingRequiredClientCapability(_, required) =>
      assert_true(required.deprecated is Some({ roots: Some(Object(_)), .. }))
    _ => fail("expected missing deprecated capability")
  } noraise {
    _ => fail("expected missing deprecated capability")
  }
}
