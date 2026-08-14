///|
test "transport errors are distinct from protocol errors" {
  let error : TransportError = MessageTooLarge(limit=1024)
  assert_eq(error, MessageTooLarge(limit=1024))
}

///|
test "frame response exposes readable copied metadata" {
  let metadata : Map[String, String] = { "status": "200" }
  let frame = FrameResponse::FrameResponse(body="{}", metadata~)
  metadata["status"] = "500"
  assert_eq(frame.body, "{}")
  assert_eq(frame.metadata["status"], "200")
}
