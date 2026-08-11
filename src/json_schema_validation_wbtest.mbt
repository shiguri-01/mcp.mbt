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
test "2020-12 nested unevaluatedProperties contributes evaluated names" {
  let validator = compile_json_schema(
    Json::object({
      "$schema": Json::string("https://json-schema.org/draft/2020-12/schema"),
      "properties": Json::object({
        "foo": Json::object({ "type": Json::string("string") }),
      }),
      "allOf": [Json::object({ "unevaluatedProperties": Json::boolean(true) })],
      "unevaluatedProperties": Json::object({
        "type": Json::string("string"),
        "maxLength": Json::number(2.0),
      }),
    }),
  )
  assert_eq(
    validator.validate(
      Json::object({ "foo": Json::string("foo"), "bar": Json::string("bar") }),
    ),
    None,
  )
}

///|
test "2020-12 nested unevaluatedItems contributes evaluated positions" {
  let validator = compile_json_schema(
    Json::object({
      "$schema": Json::string("https://json-schema.org/draft/2020-12/schema"),
      "allOf": [
        Json::object({
          "prefixItems": [Json::object({ "type": Json::string("string") })],
        }),
        Json::object({ "unevaluatedItems": Json::boolean(true) }),
      ],
      "unevaluatedItems": Json::boolean(false),
    }),
  )
  assert_eq(
    validator.validate(
      Json::array([
        Json::string("head"),
        Json::number(42.0),
        Json::boolean(true),
      ]),
    ),
    None,
  )
}

///|
test "2020-12 a failed if does not contribute evaluated properties" {
  let validator = compile_json_schema(
    Json::object({
      "$schema": Json::string("https://json-schema.org/draft/2020-12/schema"),
      "if": Json::object({
        "properties": Json::object({
          "foo": Json::object({ "const": Json::string("then") }),
        }),
        "required": [Json::string("foo")],
      }),
      "else": Json::object({
        "properties": Json::object({
          "baz": Json::object({ "type": Json::string("string") }),
        }),
      }),
      "unevaluatedProperties": Json::boolean(false),
    }),
  )
  assert_true(
    validator.validate(
      Json::object({ "foo": Json::string("else"), "baz": Json::string("baz") }),
    )
    is Some(_),
  )
}

///|
test "2020-12 unevaluatedProperties applies through a cyclic reference" {
  let validator = compile_json_schema(
    Json::object({
      "$schema": Json::string("https://json-schema.org/draft/2020-12/schema"),
      "properties": Json::object({
        "x": Json::object({ "$ref": Json::string("#") }),
      }),
      "unevaluatedProperties": Json::boolean(false),
    }),
  )
  assert_eq(
    validator.validate(
      Json::object({ "x": Json::object({ "x": Json::empty_object() }) }),
    ),
    None,
  )
  assert_true(
    validator.validate(
      Json::object({
        "x": Json::object({
          "x": Json::empty_object(),
          "y": Json::empty_object(),
        }),
      }),
    )
    is Some(_),
  )
}

///|
test "JSON numbers retain exact decimal identity and ordering" {
  let distinct = compile_json_schema(
    try! @json.parse("{\"type\":\"array\",\"uniqueItems\":true}"),
  )
  assert_eq(
    distinct.validate(try! @json.parse("[9007199254740992,9007199254740993]")),
    None,
  )
  let constant = compile_json_schema(
    try! @json.parse("{\"const\":9007199254740992}"),
  )
  assert_true(
    constant.validate(try! @json.parse("9007199254740993")) is Some(_),
  )
  let enumeration = compile_json_schema(
    try! @json.parse("{\"enum\":[9007199254740992]}"),
  )
  assert_true(
    enumeration.validate(try! @json.parse("9007199254740993")) is Some(_),
  )
  let bounded = compile_json_schema(
    try! @json.parse("{\"maximum\":9007199254740992}"),
  )
  assert_true(bounded.validate(try! @json.parse("9007199254740993")) is Some(_))
  let even = compile_json_schema(try! @json.parse("{\"multipleOf\":2}"))
  assert_true(even.validate(try! @json.parse("9007199254740993")) is Some(_))
  let overflow_safe = compile_json_schema(
    try! @json.parse("{\"type\":\"integer\",\"multipleOf\":0.123456789}"),
  )
  assert_true(overflow_safe.validate(try! @json.parse("1e308")) is Some(_))
  let small_divisor = compile_json_schema(
    try! @json.parse("{\"type\":\"integer\",\"multipleOf\":1e-8}"),
  )
  assert_eq(small_divisor.validate(try! @json.parse("12391239123")), None)
  let huge_exponent = compile_json_schema(
    try! @json.parse("{\"minimum\":9e2147483646,\"multipleOf\":2}"),
  )
  assert_eq(huge_exponent.validate(try! @json.parse("1e2147483647")), None)
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
test "URI fragment octets are decoded before JSON Pointer evaluation" {
  let validator = compile_json_schema(
    Json::object({
      "$defs": Json::object({
        "c%d": Json::object({ "type": Json::string("string") }),
      }),
      "$ref": Json::string("#%2F$defs%2Fc%25d"),
    }),
  )
  assert_eq(validator.validate(Json::string("mcp")), None)
  assert_true(validator.validate(Json::number(1.0)) is Some(_))
  let unicode = compile_json_schema(
    Json::object({
      "$defs": Json::object({
        "値": Json::object({ "const": Json::string("ok") }),
      }),
      "$ref": Json::string("#/$defs/%E5%80%A4"),
    }),
  )
  assert_eq(unicode.validate(Json::string("ok")), None)
}

///|
test "fixed-width ECMA-262 lookahead assertions are zero-width" {
  let anchored = compile_json_schema(
    Json::object({ "type": Json::string("string"), "pattern": "^(?=a)a$" }),
  )
  assert_eq(anchored.validate(Json::string("a")), None)
  assert_true(anchored.validate(Json::string("b")) is Some(_))
  let negative = compile_json_schema(
    Json::object({ "type": Json::string("string"), "pattern": "^(?!a)b$" }),
  )
  assert_eq(negative.validate(Json::string("b")), None)
  assert_true(negative.validate(Json::string("a")) is Some(_))
  for pattern in ["(?=a).", ".*(?=a).", ".*(?!b)."] {
    try
      ignore(
        compile_json_schema(
          Json::object({ "type": Json::string("string"), "pattern": pattern }),
        ),
      )
    catch {
      InvalidParams(_) => ()
      _ => fail("expected InvalidParams for ambiguous lookahead")
    } noraise {
      _ => fail("ambiguous lookahead was accepted")
    }
  }
  let property_name = compile_json_schema(
    Json::object({
      "type": "object",
      "patternProperties": Json::object({ "^(?=a)a$": false }),
    }),
  )
  assert_true(
    property_name.validate(Json::object({ "a": Json::number(1.0) })) is Some(_),
  )
  assert_eq(
    property_name.validate(Json::object({ "b": Json::number(1.0) })),
    None,
  )
}

///|
test "vocabulary requirements apply only when a resource is a meta-schema" {
  let declaration = Json::object({
    "https://json-schema.org/draft/2020-12/vocab/core": true,
    "https://example.com/vocab/optional": false,
  })
  let ordinary = compile_json_schema(
    Json::object({
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "$vocabulary": Json::object({ "https://example.com/vocab/required": true }),
      "type": "string",
    }),
  )
  assert_eq(ordinary.validate(Json::string("mcp")), None)
  let compound = Json::object({
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "https://example.com/root",
    "$defs": Json::object({
      "meta": Json::object({
        "$id": "https://example.com/meta",
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$vocabulary": declaration,
      }),
      "value": Json::object({
        "$id": "https://example.com/value",
        "$schema": "https://example.com/meta",
        "type": "string",
      }),
    }),
    "$ref": "https://example.com/value",
  })
  let validator = compile_json_schema(compound)
  assert_eq(validator.validate(Json::string("mcp")), None)
  guard compound is Object(root) &&
    root.get("$defs") is Some(Object(definitions)) &&
    definitions.get("meta") is Some(Object(meta)) else {
    fail("expected compound schema resources")
  }
  meta["$vocabulary"] = Json::object({
    "https://json-schema.org/draft/2020-12/vocab/core": true,
    "https://example.com/vocab/required": true,
  })
  try compile_json_schema(compound) catch {
    InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("an unknown required vocabulary must refuse schema processing")
  }
}

///|
test "embedded resources cannot silently change the processing dialect" {
  try
    compile_json_schema(
      Json::object({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$defs": Json::object({
          "legacy": Json::object({
            "$id": "https://example.com/legacy",
            "$schema": "http://json-schema.org/draft-07/schema#",
          }),
        }),
      }),
    )
  catch {
    InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("mixed embedded dialects require an implementation for both")
  }
  try
    compile_json_schema(
      Json::object({
        "properties": Json::object({
          "value": Json::object({
            "$schema": "https://json-schema.org/draft/2020-12/schema",
          }),
        }),
      }),
    )
  catch {
    InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("$schema is only valid at a schema resource root")
  }
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
      Json::object({
        "$defs": Json::object({ "bad~2escape": Json::boolean(true) }),
        "$ref": Json::string("#/$defs/bad~2escape"),
      }),
      Json::object({
        "$defs": Json::object({ "value": Json::boolean(true) }),
        "$ref": Json::string("#/$defs/%ZZ"),
      }),
      Json::object({
        "prefixItems": [Json::boolean(true), Json::boolean(true)],
        "$ref": Json::string("#/prefixItems/01"),
      }),
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
