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
  @schema.ObjectSchema(
    properties={
      "name": @schema.StringSchema(description="Name to greet").into_schema(),
    },
    required=["name"],
  ).into_schema()
}
```

Every JSON Schema 2020-12 type (`StringSchema`, `ObjectSchema`, `ArraySchema`,
`IntegerSchema`, `NumberSchema`, `BooleanSchema`, `EnumSchema`, `ConstSchema`,
`AllOfSchema`, `AnyOfSchema`, `OneOfSchema`, `NotSchema`, `RefSchema`, `RawSchema`)
implements the `SchemaNode` trait and can be converted into `Schema` via
`.into_schema()`.

`Schema::document()` validates the document shape, and `Document::compile()`
produces an instance validator. `schema_of((None : T?))` obtains a schema from
a `JsonSchema` implementation without constructing `T`.
