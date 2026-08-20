///|
test "JSON-RPC request decoding preserves the typed envelope" {
  let message = decode(
    @json.parse(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}",
    ),
  )
  match message {
    Message::Request(request) => {
      assert_eq(request.method_name, "tools/list")
      assert_eq(request.id, RequestId::number(1.0, repr="1"))
    }
    _ => fail("expected JSON-RPC request")
  }
}

///|
test "JSON-RPC notification has no request id" {
  let message = decode(
    @json.parse(
      "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{}}",
    ),
  )
  match message {
    Message::Notification(notification) =>
      assert_eq(notification.method_name, "notifications/cancelled")
    _ => fail("expected JSON-RPC notification")
  }
}

///|
test "JSON-RPC decoder rejects batches and ambiguous responses" {
  try decode(@json.parse("[]")) catch {
    _ => ()
  } noraise {
    _ => fail("expected a batch to be rejected")
  }
  try
    decode(
      @json.parse(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{},\"error\":{\"code\":-1,\"message\":\"x\"}}",
      ),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected an ambiguous response to be rejected")
  }
}

///|
test "JSON-RPC constructors reject empty method names" {
  try
    Request::Request(
      id=RequestId::number(1.0, repr="1"),
      method_name="",
      params=Json::object({}),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected an empty request method to be rejected")
  }
}
