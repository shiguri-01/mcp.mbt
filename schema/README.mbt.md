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
    @schema.string(name="name", description="Name to greet", required=true),
  ])
}
```

The builders intentionally return `Json`, so advanced schemas can still be
written directly with `Json::object(...)` and wrapped with `field(...)`.

`string()` builds an object field descriptor for `schema([...])`.
`string_schema()` builds a reusable JSON Schema fragment for places such as
`array(name="tags", items=string_schema())` or custom `field(...)` calls.
