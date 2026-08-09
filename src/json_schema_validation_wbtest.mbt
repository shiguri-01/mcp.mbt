///|
test "schema validator accepts draft-07 and ignores ref siblings" {
  let validator = compile_json_schema(
    Json::object({
      "$schema": Json::string("http://json-schema.org/draft-07/schema#"),
      "definitions": Json::object({
        "positive": Json::object({
          "type": Json::string("integer"),
          "minimum": Json::number(1.0),
        }),
      }),
      "$ref": Json::string("#/definitions/positive"),
      "maximum": Json::number(3.0),
    }),
  )
  assert_eq(validator.validate(Json::number(2.0)), None)
  assert_true(validator.validate(Json::number(0.0)) is Some(_))
  assert_eq(validator.validate(Json::number(4.0)), None)
}

///|
test "schema shape checks follow the selected dialect" {
  // Unknown 2020-12 keywords are annotations in draft-07 and must not make an
  // otherwise valid draft-07 schema fail registration.
  ignore(
    compile_json_schema(
      Json::object({
        "$schema": Json::string("http://json-schema.org/draft-07/schema#"),
        "type": Json::string("array"),
        "prefixItems": Json::string("ignored"),
        "dependentRequired": Json::string("ignored"),
        "minContains": Json::string("ignored"),
        "items": [Json::object({ "type": Json::string("string") })],
      }),
    ),
  )
  try
    compile_json_schema(
      Json::object({
        "$schema": Json::string("https://json-schema.org/draft/2020-12/schema"),
        "items": [Json::object({ "type": Json::string("string") })],
      }),
    )
  catch {
    InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("2020-12 must reject tuple-form items")
  }
  let modern = compile_json_schema(
    Json::object({
      "$schema": Json::string("https://json-schema.org/draft/2020-12/schema"),
      "type": Json::string("object"),
      "dependencies": Json::object({ "a": ["b"].to_json() }),
    }),
  )
  assert_eq(modern.validate(Json::object({ "a": Json::boolean(true) })), None)
}

///|
test "schema validator evaluates object applicators" {
  let validator = compile_json_schema(
    Json::object({
      "type": Json::string("object"),
      "propertyNames": Json::object({ "pattern": Json::string("^[a-z]+$") }),
      "patternProperties": Json::object({
        "^count": Json::object({ "type": Json::string("integer") }),
      }),
      "properties": Json::object({
        "unit": Json::object({ "type": Json::string("string") }),
      }),
      "dependentRequired": Json::object({ "count": ["unit"].to_json() }),
      "additionalProperties": Json::boolean(false),
    }),
  )
  assert_eq(
    validator.validate(
      Json::object({ "count": Json::number(1.0), "unit": Json::string("items") }),
    ),
    None,
  )
  assert_true(
    validator.validate(Json::object({ "count": Json::number(1.0) })) is Some(_),
  )
  assert_true(
    validator.validate(Json::object({ "Count": Json::number(1.0) })) is Some(_),
  )
}

///|
test "schema validator evaluates array applicators" {
  let validator = compile_json_schema(
    Json::object({
      "type": Json::string("array"),
      "prefixItems": [Json::object({ "type": Json::string("string") })],
      "items": Json::object({ "type": Json::string("integer") }),
      "contains": Json::object({
        "type": Json::string("integer"),
        "minimum": Json::number(5.0),
      }),
      "minContains": Json::number(1.0),
    }),
  )
  assert_eq(
    validator.validate(Json::array([Json::string("head"), Json::number(5.0)])),
    None,
  )
  assert_true(
    validator.validate(Json::array([Json::string("head"), Json::number(2.0)]))
    is Some(_),
  )
}

///|
test "schema compiler rejects unevaluated and remote references" {
  for
    schema in [
      Json::object({ "unevaluatedProperties": Json::boolean(false) }),
      Json::object({ "$ref": Json::string("https://example.com/schema") }),
      Json::object({
        "patternProperties": Json::object({
          "[": Json::object({ "type": Json::string("string") }),
        }),
      }),
    ] {
    try compile_json_schema(schema) catch {
      InvalidParams(_) => ()
      _ => fail("expected InvalidParams")
    } noraise {
      _ => fail("expected schema compilation failure")
    }
  }
}
