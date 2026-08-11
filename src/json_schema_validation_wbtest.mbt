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
  let draft_2020_12 = compile_json_schema(
    Json::object({
      "$schema": Json::string("https://json-schema.org/draft/2020-12/schema"),
      "type": Json::string("object"),
      "dependencies": Json::object({ "a": ["b"].to_json() }),
    }),
  )
  assert_eq(
    draft_2020_12.validate(Json::object({ "a": Json::boolean(true) })),
    None,
  )
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
test "multipleOf accepts decimal multiples without binary rounding artifacts" {
  let validator = compile_json_schema(
    Json::object({ "type": Json::string("number"), "multipleOf": 0.1 }),
  )
  assert_eq(validator.validate(Json::number(0.3)), None)
  assert_true(validator.validate(Json::number(0.31)) is Some(_))
}

///|
test "2020-12 unevaluated properties include successful applicators" {
  let validator = compile_json_schema(
    Json::object({
      "$schema": Json::string("https://json-schema.org/draft/2020-12/schema"),
      "allOf": [
        Json::object({
          "properties": Json::object({
            "name": Json::object({ "type": Json::string("string") }),
          }),
        }),
      ],
      "unevaluatedProperties": Json::boolean(false),
    }),
  )
  assert_eq(
    validator.validate(Json::object({ "name": Json::string("mcp") })),
    None,
  )
  assert_true(
    validator.validate(
      Json::object({
        "name": Json::string("mcp"),
        "unknown": Json::boolean(true),
      }),
    )
    is Some(_),
  )
}

///|
test "2020-12 unevaluated items include successful applicators" {
  let validator = compile_json_schema(
    Json::object({
      "$schema": Json::string("https://json-schema.org/draft/2020-12/schema"),
      "allOf": [
        Json::object({
          "prefixItems": [Json::object({ "type": Json::string("string") })],
        }),
      ],
      "unevaluatedItems": Json::boolean(false),
    }),
  )
  assert_eq(validator.validate(Json::array([Json::string("head")])), None)
  assert_true(
    validator.validate(
      Json::array([Json::string("head"), Json::string("unexpected")]),
    )
    is Some(_),
  )
}

///|
test "2020-12 dynamic references resolve local dynamic anchors" {
  let validator = compile_json_schema(
    Json::object({
      "$defs": Json::object({
        "positive": Json::object({
          "$dynamicAnchor": Json::string("value"),
          "type": Json::string("integer"),
          "minimum": Json::number(1.0),
        }),
      }),
      "$dynamicRef": Json::string("#value"),
    }),
  )
  assert_eq(validator.validate(Json::number(1.0)), None)
  assert_true(validator.validate(Json::number(0.0)) is Some(_))
}

///|
test "2020-12 $ref treats a $dynamicAnchor as a static anchor" {
  let validator = compile_json_schema(
    Json::object({
      "$defs": Json::object({
        "value": Json::object({
          "$dynamicAnchor": Json::string("value"),
          "type": Json::string("string"),
        }),
      }),
      "$ref": Json::string("#value"),
    }),
  )
  assert_eq(validator.validate(Json::string("mcp")), None)
  assert_true(validator.validate(Json::number(1.0)) is Some(_))
}

///|
test "2020-12 resolves relative references to embedded schema resources" {
  let validator = compile_json_schema(
    Json::object({
      "$id": Json::string("https://example.com/schemas/root"),
      "$defs": Json::object({
        "value": Json::object({
          "$id": Json::string("value"),
          "type": Json::string("string"),
        }),
      }),
      "$ref": Json::string("value"),
    }),
  )
  assert_eq(validator.validate(Json::string("mcp")), None)
  assert_true(validator.validate(Json::number(1.0)) is Some(_))
}

///|
test "fragment references use the current embedded resource root" {
  let validator = compile_json_schema(
    Json::object({
      "$id": Json::string("https://example.com/schemas/root"),
      "$defs": Json::object({
        "local": Json::object({ "type": Json::string("number") }),
        "child": Json::object({
          "$id": Json::string("child"),
          "$defs": Json::object({
            "local": Json::object({ "type": Json::string("string") }),
          }),
          "$ref": Json::string("#/$defs/local"),
        }),
      }),
      "$ref": Json::string("child"),
    }),
  )
  assert_eq(validator.validate(Json::string("mcp")), None)
  assert_true(validator.validate(Json::number(1.0)) is Some(_))
}

///|
test "2020-12 $dynamicRef selects the outermost dynamic scope" {
  let validator = compile_json_schema(
    Json::object({
      "$id": Json::string("https://example.com/dynamic/root"),
      "$ref": Json::string("list"),
      "$defs": Json::object({
        "item": Json::object({
          "$dynamicAnchor": Json::string("items"),
          "type": Json::string("string"),
        }),
        "list": Json::object({
          "$id": Json::string("list"),
          "type": Json::string("array"),
          "items": Json::object({ "$dynamicRef": Json::string("#items") }),
          "$defs": Json::object({
            "bookend": Json::object({ "$dynamicAnchor": Json::string("items") }),
          }),
        }),
      }),
    }),
  )
  assert_eq(validator.validate(Json::array([Json::string("mcp")])), None)
  assert_true(validator.validate(Json::array([Json::number(1.0)])) is Some(_))
}

///|
test "2020-12 anchors use the specification name grammar" {
  ignore(
    compile_json_schema(
      Json::object({
        "$anchor": Json::string("_valid.anchor-1"),
        "type": Json::string("string"),
      }),
    ),
  )
  try
    compile_json_schema(Json::object({ "$anchor": Json::string("a:b") }))
  catch {
    InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("colon is not valid in a 2020-12 anchor")
  }
}

///|
test "schema compilation enforces structural and reference constraints" {
  for
    schema in [
      Json::object({ "$ref": Json::string("https://example.com/schema") }),
      Json::object({ "$dynamicRef": Json::string("https://example.com/schema") }),
      Json::object({ "type": Json::string("unknown") }),
      Json::object({ "enum": Json::array([]) }),
      Json::object({ "allOf": Json::array([]) }),
      Json::object({ "prefixItems": Json::array([]) }),
      Json::object({ "$anchor": Json::string("1invalid") }),
      Json::object({ "$id": Json::number(1) }),
      Json::object({ "$id": Json::string("https://example.com/schema#part") }),
      Json::object({ "multipleOf": Json::number(0.0) }),
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
