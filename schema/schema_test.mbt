///|
test "schema builds required object fields" {
  let value = schema([
    string_field(name="name", required=true),
    integer_field(name="count"),
  ])
  guard value
    is Object(
      { "properties": Object(properties), "required": Array(required), .. }
    ) else {
    fail("expected object schema")
  }
  assert_true(properties.contains("name"))
  assert_true(required == [Json::string("name")])
}
