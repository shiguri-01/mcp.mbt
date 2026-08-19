///|
test "schema parses 2020-12 default and validates required fields" {
  let schema = Schema::from_json(
    Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "name": Json::object({ "type": Json::string("string") }),
      }),
      "required": Json::array([Json::string("name")]),
      "additionalProperties": Json::boolean(false),
    }),
  )
  let valid = schema.validate(Json::object({ "name": Json::string("MoonBit") }))
  assert_true(valid.valid)
  let invalid = schema.validate(Json::object({ "extra": Json::number(1.0) }))
  assert_false(invalid.valid)
  assert_true(invalid.errors.length() >= 2)
}

///|
test "schema from_json rejects an unsupported dialect" {
  try
    ignore(
      Schema::from_json(
        Json::object({
          "$schema": Json::string("https://example.com/unknown-schema"),
        }),
      ),
    )
  catch {
    UnsupportedDialect(_) => ()
    _ => fail("expected an unsupported dialect error")
  } noraise {
    _ => fail("expected an unsupported dialect error")
  }
}

///|
test "schema from_json has explicit resource limits" {
  try
    ignore(
      Schema::from_json(
        Json::object({
          "properties": Json::object({
            "nested": Json::object({ "type": Json::string("object") }),
          }),
        }),
        max_depth=2,
        max_nodes=3,
      ),
    )
  catch {
    InvalidSchema(_) => ()
    _ => fail("expected a schema limit error")
  } noraise {
    _ => fail("expected a schema limit error")
  }
}

///|
test "schema from_json resolves local JSON Pointer references" {
  let schema = Schema::from_json(
    Json::object({
      "$defs": Json::object({
        "name": Json::object({ "type": Json::string("string") }),
      }),
      "$ref": Json::string("#/$defs/name"),
    }),
  )
  assert_true(schema.validate(Json::string("MoonBit")).valid)
  assert_false(schema.validate(Json::number(1.0)).valid)
}

///|
test "network references are rejected during schema from_json" {
  try
    ignore(
      Schema::from_json(
        Json::object({ "$ref": Json::string("https://example.com/schema.json") }),
      ),
    )
  catch {
    InvalidSchema(_) => ()
    _ => fail("expected network reference rejection")
  } noraise {
    _ => fail("expected network reference rejection")
  }
}

///|
test "boolean schemas retain JSON Schema semantics" {
  let always_valid = Schema::from_json(Json::boolean(true))
  let never_valid = Schema::from_json(Json::boolean(false))
  assert_true(always_valid.validate(Json::string("ok")).valid)
  assert_false(never_valid.validate(Json::string("ok")).valid)
}

///|
test "typed Schema constructors produce a validated document" {
  let properties : Map[String, Schema] = {
    "name": Schema::string(),
    "count": Schema::integer(),
  }
  let schema = Schema::object(
    properties~,
    required=["name"],
    additional_properties=false,
  )
  assert_true(
    schema.validate(
      Json::object({
        "name": Json::string("MoonBit"),
        "count": Json::number(1.0),
      }),
    ).valid,
  )
  assert_false(
    schema.validate(Json::object({ "name": Json::number(1.0) })).valid,
  )
}

///|
test "string constraints are constructed and validated as typed schemas" {
  let schema = Schema::string(min_length=2, max_length=4)
  assert_eq(
    schema.to_json(),
    Json::object({
      "type": Json::string("string"),
      "minLength": Json::number(2.0, repr="2"),
      "maxLength": Json::number(4.0, repr="4"),
    }),
  )
  assert_true(schema.validate(Json::string("moon")).valid)
  assert_false(schema.validate(Json::string("m")).valid)
  try ignore(Schema::string(min_length=5, max_length=2)) catch {
    InvalidSchema(_) => ()
    _ => fail("invalid bounds must be rejected")
  } noraise {
    _ => fail("invalid bounds must be rejected")
  }
}

///|
test "unsupported keywords are rejected at compile time" {
  try
    ignore(
      Schema::from_json(
        Json::object({
          "type": Json::string("string"),
          "pattern": Json::string("^[a-z]+$"),
        }),
      ),
    )
  catch {
    UnsupportedKeyword("pattern") => ()
    _ => fail("pattern must be reported as unsupported")
  } noraise {
    _ => fail("pattern must not be silently ignored")
  }
}

///|
test "typed schema constructors reject duplicate names and enum values" {
  try ignore(Schema::enumeration(["same", "same"])) catch {
    InvalidSchema(_) => ()
    _ => fail("duplicate enum values must be rejected")
  } noraise {
    _ => fail("duplicate enum values must be rejected")
  }
  try
    ignore(
      Schema::object(properties={ "name": Schema::string() }, required=[
        "name", "name",
      ]),
    )
  catch {
    InvalidSchema(_) => ()
    _ => fail("duplicate required names must be rejected")
  } noraise {
    _ => fail("duplicate required names must be rejected")
  }
}

///|
test "document compilation rejects malformed supported keywords" {
  let invalid_schemas = [
    Json::object({ "type": Json::number(1.0) }),
    Json::object({ "minLength": Json::number(-1.0) }),
    Json::object({ "required": Json::array([Json::number(1.0)]) }),
    Json::object({ "properties": Json::string("not-an-object") }),
    Json::object({ "items": Json::string("not-a-schema") }),
    Json::object({ "anyOf": Json::array([]) }),
    Json::object({ "$dynamicRef": Json::string("#/$defs/value") }),
  ]
  for value in invalid_schemas {
    try ignore(Schema::from_json(value)) catch {
      InvalidSchema(_) | UnsupportedKeyword(_) => ()
      _ => fail("malformed schema keyword must be rejected")
    } noraise {
      _ => fail("malformed schema keyword must be rejected")
    }
  }
}

///|
test "instance data is not mistaken for a schema" {
  let schema = Schema::from_json(
    Json::object({
      "const": Json::object({ "pattern": Json::string("literal") }),
    }),
  )
  assert_true(
    schema.validate(Json::object({ "pattern": Json::string("literal") })).valid,
  )
}

///|
test "array, object, and multipleOf constraints are evaluated" {
  let schema = Schema::from_json(
    Json::object({
      "type": Json::string("object"),
      "minProperties": Json::number(1.0),
      "properties": Json::object({
        "values": Json::object({
          "type": Json::string("array"),
          "minItems": Json::number(2.0),
          "maxItems": Json::number(3.0),
          "uniqueItems": Json::boolean(true),
          "items": Json::object({
            "type": Json::string("number"),
            "multipleOf": Json::number(2.0),
          }),
        }),
      }),
    }),
  )
  assert_true(
    schema.validate(Json::object({ "values": [2.0, 4.0].to_json() })).valid,
  )
  assert_false(
    schema.validate(Json::object({ "values": [2.0, 3.0].to_json() })).valid,
  )
}

///|
test "array and object constraints can be built without JSON" {
  let array_schema = Schema::array(
    items=Schema::integer(),
    min_items=1,
    max_items=2,
    unique_items=true,
  )
  let object_schema = Schema::object(
    properties={ "values": array_schema },
    min_properties=1,
    max_properties=1,
  )
  assert_eq(
    object_schema.to_json(),
    Json::object({
      "type": Json::string("object"),
      "properties": Json::object({ "values": array_schema.to_json() }),
      "required": Json::array([]),
      "additionalProperties": Json::boolean(true),
      "minProperties": Json::number(1.0, repr="1"),
      "maxProperties": Json::number(1.0, repr="1"),
    }),
  )
}

///|
test "typed combinators preserve JSON Schema assertion semantics" {
  let positive = Schema::any_of([
    Schema::constant("yes"),
    Schema::constant("ok"),
  ])
  let exact = Schema::constant("yes")
  let not_exact = Schema::not(exact)
  let schema = Schema::all_of([positive, not_exact])
  assert_false(schema.validate(Json::string("yes")).valid)
  assert_true(schema.validate(Json::string("ok")).valid)
}
