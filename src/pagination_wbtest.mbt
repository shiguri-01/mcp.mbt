///|
test "empty cursor is a valid opaque cursor" {
  let page = paginate(["a", "b"], cursor="", page_size=1)
  assert_eq(page.items, ["a"])
  assert_eq(page.next_cursor, Some("1"))
}

///|
test "cursor parsing accepts the Int boundary and rejects overflow" {
  assert_eq(parse_cursor(Some("2147483647"), 2147483647), 2147483647)
  try ignore(parse_cursor(Some("2147483648"), 2147483647)) catch {
    InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("overflowing cursor was accepted")
  }
}

///|
test "cursor parsing bounds work before decimal accumulation" {
  try ignore(parse_cursor(Some("000000000000000000000"), 1)) catch {
    InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("overlong cursor was accepted")
  }
}
