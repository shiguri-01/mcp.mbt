///|
test "empty cursor is a valid opaque cursor" {
  let page = paginate(["a", "b"], cursor="", page_size=1)
  assert_eq(page.items, ["a"])
  assert_eq(page.next_cursor, Some("1"))
}
