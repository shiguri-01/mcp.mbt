# shiguri-01/mcp/schema

Typed JSON Schema (Draft 2020-12) builder, validator, and decoder.

## Defining Schemas

```moonbit nocheck
///|
struct UserInput {
  name : String
  age : Int?
} derive(@json.FromJson, ToJson)

///|
impl @schema.JsonSchema for UserInput with fn json_schema() {
  @schema.Schema::object(
    properties={
      "name": @schema.Schema::string(min_length=1),
      "age": @schema.Schema::integer(minimum=0),
    },
    required=["name"],
  )
}
```

## Validating & Decoding

```moonbit nocheck
// Validate & decode JSON into typed struct in one step
let input : UserInput = try! @schema.decode(json)

// Direct instance validation
let schema = @schema.Schema::string(min_length=3)
try! schema.validate(Json::string("hello"))
```
