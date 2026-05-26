// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
fn test_initialize_params() -> Json {
  Json::object({
    "protocolVersion": Json::string(latest_protocol_version),
    "capabilities": Json::object({ "roots": Json::object({}) }),
    "clientInfo": Json::object({
      "name": Json::string("test-client"),
      "version": Json::string("0.1.0"),
      "title": Json::string("Test Client"),
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
