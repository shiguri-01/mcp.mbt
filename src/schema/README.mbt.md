# shiguri-01/mcp/schema

Typed JSON Schema 2020-12 construction and bounded instance validation. The
package is independent of MCP and can be used for any JSON document. The
implemented keyword subset is explicit; assertion keywords that this runtime
cannot evaluate (for example `pattern`) are rejected at compile time instead
of being silently ignored.

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

Common constraints are also typed constructors, for example
`Schema::string_constraints(min_length=1)`,
`Schema::array_constraints(items=Schema::integer(), min_items=1)`, and
`Schema::object_constraints(properties={ "items": item_schema },
min_properties=1)`. These constructors reject invalid bounds before a
document is compiled.

Value assertions are typed as well: `Schema::const_value(42)` and
`Schema::enum_values(["draft", "published"])` use `ToJson`, so callers do not
need to pre-encode ordinary MoonBit values as `Json`.
