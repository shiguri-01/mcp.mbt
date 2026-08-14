///|
test "document uses MCP's 2020-12 default and validates required fields" {
  let document = try! Document::new(
    Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "name": Json::object({ "type": Json::string("string") }),
      }),
      "required": Json::array([Json::string("name")]),
      "additionalProperties": Json::boolean(false),
    }),
  )
  let schema = try! document.compile()
  let valid = schema.validate(Json::object({ "name": Json::string("MoonBit") }))
  assert_true(valid.valid)
  let invalid = schema.validate(Json::object({ "extra": Json::number(1.0) }))
  assert_false(invalid.valid)
  assert_true(invalid.errors.length() >= 2)
}

///|
test "document rejects an unsupported dialect before compilation" {
  try
    Document::new(
      Json::object({
        "$schema": Json::string("https://example.com/unknown-schema"),
      }),
    )
  catch {
    error => assert_true(error is UnsupportedDialect(_))
  } noraise {
    _ => fail("expected an unsupported dialect error")
  }
}

///|
test "document compilation has explicit resource limits" {
  let options = try! CompileOptions::new(max_depth=2, max_nodes=3)
  try
    Document::new(
      Json::object({
        "properties": Json::object({
          "nested": Json::object({ "type": Json::string("object") }),
        }),
      }),
    ).compile(options~)
  catch {
    error => assert_true(error is InvalidSchema(_))
  } noraise {
    _ => fail("expected a schema limit error")
  }
}
