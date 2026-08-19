# shiguri-01/mcp/schema

Typed JSON Schema (Draft 2020-12) construction, bounded instance validation, and typed decoding.
The package is independent of MCP and can be used for any JSON Schema validation and decoding workflow.

## Defining a Typed Schema

Use factory methods on `Schema` to build schemas programmatically:

```mbt nocheck
///|
struct HelloInput {
  name : String
} derive(FromJson)

///|
impl @schema.JsonSchema for HelloInput with fn json_schema() -> @schema.Schema {
  @schema.Schema::object(
    properties={
      "name": @schema.Schema::string(min_length=1, description="Name to greet"),
    },
    required=["name"],
  )
}
```

## Validating and Decoding JSON

Validate raw JSON directly or decode it into a typed struct in a single step:

```mbt nocheck
// 1. Direct schema validation
let schema = @schema.Schema::string(min_length=3)
let result = schema.validate(Json::string("hello"))
if result.valid {
  println("Valid JSON!")
}

// 2. Typed validation & decoding
let input_json = Json::object({ "name": Json::string("Alice") })
let decoded : Result[HelloInput, Array[@schema.ValidationError]] = @schema.decode_json(input_json)
match decoded {
  Ok(input) => println("Hello, \{input.name}!")
  Err(errors) => println("Validation failed: \{errors}")
}

// 3. Parsing schema from JSON Schema JSON
let parsed_schema = @schema.Schema::from_json(json_schema_definition)
```
