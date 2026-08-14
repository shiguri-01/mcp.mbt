///|
test "frame transport is opaque to protocol payloads" {
  let headers : Map[String, String] = { "Content-Type": "application/json" }
  let outbound = OutboundFrame::OutboundFrame(body="not parsed here", headers~)
  let returned = outbound.headers()
  returned["Content-Type"] = "text/plain"
  assert_eq(outbound.headers()["Content-Type"], "application/json")
  assert_eq(outbound.body(), "not parsed here")
}

///|
test "transport errors are distinct from protocol errors" {
  let error : TransportError = MessageTooLarge(limit=1024)
  assert_eq(error, MessageTooLarge(limit=1024))
}
