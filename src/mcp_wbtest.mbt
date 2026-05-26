// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
fn test_initialize_params() -> Json {
  Json::object({
    "protocolVersion": Json::string(latest_protocol_version),
    "capabilities": Json::object({
      "roots": Json::object({ "listChanged": Json::boolean(true) }),
      "sampling": Json::object({ "tools": Json::object({}) }),
      "x-client": Json::object({ "enabled": Json::boolean(true) }),
    }),
    "clientInfo": Json::object({
      "name": Json::string("test-client"),
      "version": Json::string("0.1.0"),
      "title": Json::string("Test Client"),
      "icons": Json::array([
        Json::object({
          "src": Json::string("data:image/png;base64,AA=="),
          "theme": Json::string("dark"),
        }),
      ]),
    }),
  })
}

///|
test "initialize stores negotiated session metadata and waits for initialized" {
  let server = Server(name="test-server", version="0.1.0")
  let result = try! server.initialize(Some(test_initialize_params()))
  assert_true(result.protocol_version == latest_protocol_version)
  assert_true(server.is_initialized() == false)
  assert_true(
    server.negotiated_protocol_version() == Some(latest_protocol_version),
  )
  guard server.client_info() is Some(info) else { fail("expected client info") }
  assert_true(info.name == "test-client")
  assert_true(info.title == Some("Test Client"))
  guard info.icons is [{ theme: Some(IconTheme::Dark), .. }] else {
    fail("expected dark icon theme")
  }
  guard server.client_capabilities() is Some(capabilities) else {
    fail("expected client capabilities")
  }
  guard capabilities.roots is Some(roots) else { fail("expected roots") }
  assert_true(roots.list_changed == Some(true))
  guard capabilities.sampling is Some(sampling) else {
    fail("expected sampling")
  }
  assert_true(sampling.tools)
  assert_true(capabilities.extra.contains("x-client"))
  try! server.notify_initialized()
  assert_true(server.is_initialized())
}

///|
test "dispatch rejects normal operations before ready" {
  let server = Server(name="test-server", version="0.1.0")
  let before_initialize : Result[Json?, Error] = try? server.dispatch(
    "tools/list",
    None,
  )
  guard before_initialize is Err(InvalidRequest(_)) else {
    fail("expected initialize-first error")
  }
  ignore(try! server.initialize(Some(test_initialize_params())))
  let before_ready : Result[Json?, Error] = try? server.dispatch(
    "tools/list",
    None,
  )
  guard before_ready is Err(InvalidRequest(_)) else {
    fail("expected initialized notification error")
  }
  try! server.notify_initialized()
  let ready = try! server.dispatch("tools/list", None)
  guard ready is Some(Object({ "tools": Array(_), .. })) else {
    fail("expected tools/list result")
  }
}

///|
test "server capabilities encode known capabilities and extensions" {
  let capabilities = ServerCapabilities(
    tools=ToolsCapability(list_changed=true),
    resources=ResourcesCapability(subscribe=true, list_changed=false),
    prompts=PromptsCapability(list_changed=true),
    logging=true,
    completions=true,
    tasks=ServerTaskCapabilities(
      list=true,
      cancel=true,
      requests=ServerTaskRequestCapabilities(tools_call=true),
    ),
    experimental=Json::object({ "draft": Json::object({}) }),
    extra={ "x-server": Json::object({ "enabled": Json::boolean(true) }) },
  ).to_json()
  guard capabilities is Object(fields) else {
    fail("expected capabilities object")
  }
  guard fields["tools"] is Object(tools) else {
    fail("expected tools capability")
  }
  assert_true(tools["listChanged"] == Json::boolean(true))
  guard fields["resources"] is Object(resources) else {
    fail("expected resources capability")
  }
  assert_true(resources["subscribe"] == Json::boolean(true))
  assert_true(resources["listChanged"] == Json::boolean(false))
  guard fields["tasks"] is Object(tasks) else {
    fail("expected tasks capability")
  }
  assert_true(tasks.contains("list"))
  assert_true(tasks.contains("cancel"))
  assert_true(fields.contains("x-server"))
}

///|
test "initialize rejects invalid icon theme" {
  let server = Server(name="test-server", version="0.1.0")
  let params = Json::object({
    "protocolVersion": Json::string(latest_protocol_version),
    "capabilities": Json::object({}),
    "clientInfo": Json::object({
      "name": Json::string("test-client"),
      "version": Json::string("0.1.0"),
      "icons": Json::array([
        Json::object({
          "src": Json::string("data:image/png;base64,AA=="),
          "theme": Json::string("sepia"),
        }),
      ]),
    }),
  })
  let result : Result[InitializeResult, Error] = try? server.initialize(
    Some(params),
  )
  guard result is Err(InvalidParams(_)) else {
    fail("expected invalid icon theme error")
  }
}
