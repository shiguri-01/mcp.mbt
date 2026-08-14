///|
test "document uses MCP's 2020-12 default and validates required fields" {
  let document = try! Document::Document(
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
    Document::Document(
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
  let options = try! CompileOptions::CompileOptions(max_depth=2, max_nodes=3)
  try
    Document::Document(
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

///|
test "compiled schemas resolve local JSON Pointer references" {
  let document = try! Document::Document(
    Json::object({
      "$defs": Json::object({
        "name": Json::object({ "type": Json::string("string") }),
      }),
      "$ref": Json::string("#/$defs/name"),
    }),
  )
  let schema = try! document.compile()
  assert_true(schema.validate(Json::string("MoonBit")).valid)
  assert_false(schema.validate(Json::number(1.0)).valid)
}

///|
test "network references are rejected during compilation" {
  try
    Document::Document(
      Json::object({ "$ref": Json::string("https://example.com/schema.json") }),
    ).compile()
  catch {
    error => assert_true(error is InvalidSchema(_))
  } noraise {
    _ => fail("expected network reference rejection")
  }
}

///|
test "boolean schemas retain JSON Schema semantics" {
  let always_valid = try! Document::Document(Json::boolean(true)).compile()
  let never_valid = try! Document::Document(Json::boolean(false)).compile()
  assert_true(always_valid.validate(Json::string("ok")).valid)
  assert_false(never_valid.validate(Json::string("ok")).valid)
}
