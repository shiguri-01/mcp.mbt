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
