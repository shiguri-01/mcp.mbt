# shiguri-01/mcp/schema

Typed JSON Schema 2020-12 construction and validation. The package is
independent of MCP and can be used for any JSON document.

Use this package next to the MoonBit input struct that derives `FromJson`:

```mbt nocheck
///|
struct HelloInput {
  name : String
} derive(FromJson)

///|
impl @schema.JsonSchema for HelloInput with fn json_schema() -> @schema.Schema {
  @schema.object([
    @schema.string(name="name", description="Name to greet", required=true),
  ])
}
```

`Schema` is the typed AST. `Schema::document()` validates the document shape,
and `Document::compile()` produces an instance validator. Use `Schema::raw`
only for keywords not yet modeled by the typed AST. `schema_of((None : T?))`
obtains a schema from a `JsonSchema` implementation without constructing `T`.
