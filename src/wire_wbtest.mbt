///|
test "wire accepts a single request and rejects a batch" {
  let request = parse_rpc_request(
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "method": Json::string("server/discover"),
      "params": Json::object({ "_meta": Json::object({}) }),
    }),
  )
  assert_eq(request.method_name, "server/discover")
  try parse_rpc_request(Json::array([])) catch {
    _ => ()
  } noraise {
    _ => fail("expected batch to be rejected")
  }
}

///|
test "2026-07-28 results require resultType" {
  assert_eq(
    require_result_type(
      Json::object({ "resultType": Json::string("complete") }),
    ),
    "complete",
  )
  try require_result_type(Json::object({})) catch {
    _ => ()
  } noraise {
    _ => fail("expected missing resultType to be rejected")
  }
}
