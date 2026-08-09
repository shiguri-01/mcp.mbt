///|
test "schema builds required object fields" {
  let value = schema([string(name="name", required=true), integer(name="count")])
  guard value
    is Object(
      { "properties": Object(properties), "required": Array(required), .. }
    ) else {
    fail("expected object schema")
  }
  assert_true(properties.contains("name"))
  assert_true(required == [Json::string("name")])
}

///|
test "schema declares 2020-12 and builds HTTP header properties" {
  let value = schema([
    try! header_string(name="region", header_name="Region", required=true),
  ])
  guard value
    is Object(
      {
        "$schema": String("https://json-schema.org/draft/2020-12/schema"),
        "properties": Object(
          {
            "region": Object(
              { "type": String("string"), "x-mcp-header": String("Region"), .. }
            ),
            ..
          }
        ),
        ..
      }
    ) else {
    fail("expected an MCP header property")
  }
}

///|
test "panic invalid HTTP header property name" {
  ignore(try! header_string(name="region", header_name="bad header"))
}
