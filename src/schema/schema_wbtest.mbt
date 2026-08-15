///|
test "typed object schema preserves required fields" {
  let value = ObjectSchema(
    properties={
      "name": StringSchema().into_schema(),
      "count": IntegerSchema().into_schema(),
    },
    required=["name"],
  )
  let json = value.to_json()
  guard json is Object(fields) else { fail("expected object schema") }
  guard fields.get("properties") is Some(Object(properties)) else {
    fail("expected properties object")
  }
  guard fields.get("required") is Some(Array(required)) else {
    fail("expected required array")
  }
  assert_true(properties.contains("name"))
  assert_eq(required, [Json::string("name")])
}

///|
test "typed constructors reject an undeclared required property" {
  try
    ignore(
      ObjectSchema(properties={ "count": IntegerSchema().into_schema() }, required=[
        "name",
      ]),
    )
  catch {
    InvalidSchema(_) => ()
    _ => fail("expected invalid property declaration")
  } noraise {
    _ => fail("expected invalid property declaration")
  }
}

///|
test "primitive JsonSchema implementations produce typed documents" {
  let string_document = schema_of((None : String?)).document()
  let int_document = schema_of((None : Int?)).document()
  assert_true(string_document.compile().validate(Json::string("ok")).valid)
  assert_false(int_document.compile().validate(Json::string("no")).valid)
}

///|
test "container JsonSchema implementations are built without JSON literals" {
  let strings = schema_of((None : Array[String]?)).document().compile()
  assert_true(strings.validate(Json::array([Json::string("ok")])).valid)
  assert_false(strings.validate(Json::array([Json::number(1.0)])).valid)
  let optional = schema_of((None : Int??)).document().compile()
  assert_true(optional.validate(Json::null()).valid)
  assert_true(optional.validate(Json::number(1.0)).valid)
}

///|
test "raw Json has an explicit unconstrained schema" {
  let schema = schema_of((None : Json?))
  let validator = schema.document().compile()
  assert_true(
    validator.validate(Json::object({ "any": Json::number(1.0) })).valid,
  )
}

///|
test "const and enum assertions accept MoonBit values" {
  let constant = ConstSchema::from_value(42)
  let enumeration = EnumSchema::from_values(["draft", "published"])
  let constant_validator = constant.into_schema().document().compile()
  let enum_validator = enumeration.into_schema().document().compile()
  assert_true(constant_validator.validate(Json::number(42.0)).valid)
  assert_false(constant_validator.validate(Json::number(41.0)).valid)
  assert_true(enum_validator.validate(Json::string("draft")).valid)
  assert_false(enum_validator.validate(Json::string("other")).valid)
}

///|
test "typed schema string constraints support serialization and validation" {
  let schema = StringSchema(min_length=3, max_length=10)
  assert_eq(
    schema.to_json(),
    Json::object({
      "type": Json::string("string"),
      "minLength": Json::number(3.0, repr="3"),
      "maxLength": Json::number(10.0, repr="10"),
    }),
  )
  let compiled = schema.into_schema().document().compile()
  assert_true(compiled.validate(Json::string("hello")).valid)
  assert_false(compiled.validate(Json::string("hi")).valid)
}

///|
test "Schema values support Eq equality check" {
  let a = StringSchema(min_length=1, max_length=5).into_schema()
  let b = StringSchema(min_length=1, max_length=5).into_schema()
  let c = StringSchema(min_length=2, max_length=5).into_schema()
  assert_true(a == b)
  assert_false(a == c)
}
