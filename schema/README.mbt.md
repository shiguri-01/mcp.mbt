# shiguri/mcp/schema

Small JSON Schema builders for MCP tool input types.

Use this package next to the MoonBit input struct that derives `FromJson`:

```mbt nocheck
///|
struct HelloInput {
  name : String
} derive(FromJson)

///|
impl @schema.JsonSchema for HelloInput with fn json_schema() {
  @schema.schema([
    @schema.string_field(
      name="name",
      description="Name to greet",
      required=true,
    ),
  ])
}
```

The builders intentionally return `Json`, so advanced schemas can still be
written directly with `Json::object(...)` and wrapped with `field(...)`.
