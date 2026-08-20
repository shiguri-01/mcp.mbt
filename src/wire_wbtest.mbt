///|
test "wire accepts a single request and rejects a batch" {
  let decoded = try! @jsonrpc.decode(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("server/discover"),
      "params": Json::object({ "_meta": Json::object({}) }),
    }),
  )
  match decoded {
    @jsonrpc.Message::Request(request) =>
      assert_eq(request.method_name, "server/discover")
    _ => fail("expected request")
  }
  try @jsonrpc.decode(Json::array([])) catch {
    _ => ()
  } noraise {
    _ => fail("expected batch to be rejected")
  }
}

///|
test "clients treat an absent resultType as complete" {
  let response = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "result": Json::object({}),
  })
  let outcome = try! HandlerOutcome::decode_response(response)
  assert_true(outcome is Complete(_))
}
