///|
test "typed object schema preserves required fields" {
  let value = Schema::object(
    properties={ "name": Schema::string(), "count": Schema::integer() },
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
      Schema::object(properties={ "count": Schema::integer() }, required=[
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
  let string_schema = schema_of((None : String?))
  let int_schema = schema_of((None : Int?))
  assert_true(string_schema.validate(Json::string("ok")).valid)
  assert_false(int_schema.validate(Json::string("no")).valid)
}

///|
test "container JsonSchema implementations are built without JSON literals" {
  let strings = schema_of((None : Array[String]?))
  assert_true(strings.validate(Json::array([Json::string("ok")])).valid)
  assert_false(strings.validate(Json::array([Json::number(1.0)])).valid)
  let optional = schema_of((None : Int??))
  assert_true(optional.validate(Json::null()).valid)
  assert_true(optional.validate(Json::number(1.0)).valid)
}

///|
test "raw Json has an explicit unconstrained schema" {
  let schema = schema_of((None : Json?))
  assert_true(schema.validate(Json::object({ "any": Json::number(1.0) })).valid)
}

///|
test "const and enum assertions accept MoonBit values" {
  let constant = Schema::constant(42)
  let enumeration = Schema::enumeration(["draft", "published"])
  assert_true(constant.validate(Json::number(42.0)).valid)
  assert_false(constant.validate(Json::number(41.0)).valid)
  assert_true(enumeration.validate(Json::string("draft")).valid)
  assert_false(enumeration.validate(Json::string("other")).valid)
}

///|
test "typed schema string constraints support serialization and validation" {
  let schema = Schema::string(min_length=3, max_length=10)
  assert_eq(
    schema.to_json(),
    Json::object({
      "type": Json::string("string"),
      "minLength": Json::number(3.0, repr="3"),
      "maxLength": Json::number(10.0, repr="10"),
    }),
  )
  assert_true(schema.validate(Json::string("hello")).valid)
  assert_false(schema.validate(Json::string("hi")).valid)
}

///|
test "Schema values support Eq equality check" {
  let a = Schema::string(min_length=1, max_length=5)
  let b = Schema::string(min_length=1, max_length=5)
  let c = Schema::string(min_length=2, max_length=5)
  assert_true(a == b)
  assert_false(a == c)
}

///|
struct UserInput {
  name : String
} derive(Eq, @debug.Debug, @json.FromJson)

///|
impl JsonSchema for UserInput with fn json_schema() -> Schema {
  Schema::object(properties={ "name": Schema::string(min_length=2) }, required=[
    "name",
  ])
}

///|
test "decode_json validates and parses typed struct" {
  let valid_json = Json::object({ "name": Json::string("Alice") })
  let valid_result : Result[UserInput, Array[ValidationError]] = decode_json(
    valid_json,
  )
  assert_true(valid_result is Ok({ name: "Alice" }))

  let invalid_json = Json::object({ "name": Json::string("A") })
  let invalid_result : Result[UserInput, Array[ValidationError]] = decode_json(
    invalid_json,
  )
  assert_true(invalid_result is Err(_))
}
