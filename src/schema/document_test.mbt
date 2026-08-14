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

///|
test "typed Schema constructors produce a validated document" {
  let properties : Map[String, Schema] = {
    "name": Schema::string(),
    "count": Schema::integer(),
  }
  let typed = try! Schema::object(
    properties~,
    required=["name"],
    additional_properties=false,
  )
  let document = try! typed.document()
  let compiled = try! document.compile()
  assert_true(
    compiled.validate(
      Json::object({
        "name": Json::string("MoonBit"),
        "count": Json::number(1.0),
      }),
    ).valid,
  )
  assert_false(
    compiled.validate(Json::object({ "name": Json::number(1.0) })).valid,
  )
}

///|
test "string constraints are constructed and validated as typed schemas" {
  let schema = Schema::string_constraints(min_length=2, max_length=4)
  assert_eq(
    schema.to_json(),
    Json::object({
      "type": Json::string("string"),
      "minLength": Json::number(2.0, repr="2"),
      "maxLength": Json::number(4.0, repr="4"),
    }),
  )
  let compiled = schema.document().compile()
  assert_true(compiled.validate(Json::string("moon")).valid)
  assert_false(compiled.validate(Json::string("m")).valid)
  ignore(
    Schema::string_constraints(min_length=5, max_length=2) catch {
      InvalidSchema(_) => Schema::never()
      _ => fail("expected invalid string bounds")
    },
  )
}

///|
test "unsupported pattern validation is rejected instead of ignored" {
  let document = try! Document::Document(
    Json::object({
      "type": Json::string("string"),
      "pattern": Json::string("^[a-z]+$"),
    }),
  )
  try document.compile() catch {
    UnsupportedKeyword("pattern") => ()
    _ => fail("pattern must be reported as unsupported")
  } noraise {
    _ => fail("pattern must not be silently ignored")
  }
}

///|
test "typed schema constructors reject duplicate names and enum values" {
  try Schema::enum_values([Json::string("same"), Json::string("same")]) catch {
    InvalidSchema(_) => ()
    _ => fail("duplicate enum values must be rejected")
  } noraise {
    _ => fail("duplicate enum values must be rejected")
  }
  try
    Schema::object(properties={ "name": Schema::string() }, required=[
      "name", "name",
    ])
  catch {
    InvalidSchema(_) => ()
    _ => fail("duplicate required names must be rejected")
  } noraise {
    _ => fail("duplicate required names must be rejected")
  }
  try object([string(name="name"), string(name="name")]) catch {
    InvalidSchema(_) => ()
    _ => fail("duplicate property names must be rejected")
  } noraise {
    _ => fail("duplicate property names must be rejected")
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
  ]
  for value in invalid_schemas {
    let document = try! Document::Document(value)
    try document.compile() catch {
      InvalidSchema(_) => ()
      _ => fail("malformed schema keyword must be rejected")
    } noraise {
      _ => fail("malformed schema keyword must be rejected")
    }
  }
}

///|
test "instance data is not mistaken for a schema" {
  let document = try! Document::Document(
    Json::object({
      "const": Json::object({ "pattern": Json::string("literal") }),
    }),
  )
  let compiled = try! document.compile()
  assert_true(
    compiled.validate(Json::object({ "pattern": Json::string("literal") })).valid,
  )
}

///|
test "typed combinators preserve JSON Schema assertion semantics" {
  let positive = Schema::any_of([
    Schema::const_value(Json::string("yes")),
    Schema::const_value(Json::string("ok")),
  ]) catch {
    _ => abort("anyOf construction failed")
  }
  let exact = Schema::const_value(Json::string("yes"))
  let document = try! Schema::all_of([positive, Schema::not(exact)]).document()
  let result = document.compile() catch { _ => abort("compile failed") }
  assert_false(result.validate(Json::string("yes")).valid)
  assert_true(result.validate(Json::string("ok")).valid)
}
