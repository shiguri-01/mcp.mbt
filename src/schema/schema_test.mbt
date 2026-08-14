///|
test "typed object schema preserves required fields" {
  let value = try! object([
    string(name="name", required=true),
    integer(name="count"),
  ])
  let json = value.to_json()
  guard json
    is Object(
      { "properties": Object(properties), "required": Array(required), .. }
    ) else {
    fail("expected object schema")
  }
  assert_true(properties.contains("name"))
  assert_eq(required, [Json::string("name")])
}

///|
test "typed constructors reject an undeclared required property" {
  try
    Schema::object(properties={ "count": Schema::integer() }, required=["name"])
  catch {
    error => assert_true(error is InvalidSchema(_))
  } noraise {
    _ => fail("expected invalid property declaration")
  }
}

///|
test "primitive JsonSchema implementations produce typed documents" {
  let string_document = try! schema_of((None : String?)).document()
  let int_document = try! schema_of((None : Int?)).document()
  assert_true(try! string_document.compile().validate(Json::string("ok")).valid)
  assert_false(try! int_document.compile().validate(Json::string("no")).valid)
}

///|
test "container JsonSchema implementations are built without JSON literals" {
  let strings = try! schema_of((None : Array[String]?)).document().compile()
  assert_true(strings.validate(Json::array([Json::string("ok")])).valid)
  assert_false(strings.validate(Json::array([Json::number(1.0)])).valid)
  let optional = try! schema_of((None : Int??)).document().compile()
  assert_true(optional.validate(Json::null()).valid)
  assert_true(optional.validate(Json::number(1.0)).valid)
}

///|
test "raw Json has an explicit unconstrained schema" {
  let schema = try! schema_of((None : Json?))
  let validator = try! schema.document().compile()
  assert_true(
    validator.validate(Json::object({ "any": Json::number(1.0) })).valid,
  )
}

///|
test "const and enum assertions accept MoonBit values" {
  let constant = Schema::const_value(42)
  let enumeration = try! Schema::enum_values(["draft", "published"])
  let constant_validator = try! constant.document().compile()
  let enum_validator = try! enumeration.document().compile()
  assert_true(constant_validator.validate(Json::number(42.0)).valid)
  assert_false(constant_validator.validate(Json::number(41.0)).valid)
  assert_true(enum_validator.validate(Json::string("draft")).valid)
  assert_false(enum_validator.validate(Json::string("other")).valid)
}

///|
test "description preserves boolean schema assertion semantics" {
  let described_never = Schema::description(Schema::never(), "not allowed")
  let validator = try! described_never.document().compile()
  assert_false(validator.validate(Json::string("value")).valid)
}
