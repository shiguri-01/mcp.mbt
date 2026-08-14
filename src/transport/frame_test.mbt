///|
test "transport errors are distinct from protocol errors" {
  let error : TransportError = MessageTooLarge(limit=1024)
  assert_eq(error, MessageTooLarge(limit=1024))
}
