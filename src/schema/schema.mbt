///|
/// The JSON Schema dialect used by MCP `2026-07-28` when `$schema` is absent.
pub let draft_2020_12 : String = "https://json-schema.org/draft/2020-12/schema"

///|
/// Errors raised while constructing, compiling, or validating a schema.
pub suberror SchemaError {
  InvalidDocument(String)
  UnsupportedDialect(String)
  UnsupportedKeyword(String)
  InvalidSchema(String)
} derive(Debug, Eq)

///|
/// JSON Schema provider for typed tool inputs.
pub(open) trait JsonSchema {
  fn json_schema() -> Schema raise SchemaError
}

///|
pub impl JsonSchema for String with fn json_schema() -> Schema {
  StringSchema().into_schema()
}

///|
pub impl JsonSchema for Bool with fn json_schema() -> Schema {
  BoolTypeSchema().into_schema()
}

///|
pub impl JsonSchema for Int with fn json_schema() -> Schema {
  IntegerSchema().into_schema()
}

///|
pub impl JsonSchema for Int64 with fn json_schema() -> Schema {
  IntegerSchema().into_schema()
}

///|
pub impl JsonSchema for Double with fn json_schema() -> Schema {
  NumberSchema().into_schema()
}

///|
/// A raw JSON value has no narrower instance constraint.
pub impl JsonSchema for Json with fn json_schema() -> Schema {
  BooleanSchema::always().into_schema()
}

///|
pub impl[T : JsonSchema] JsonSchema for Array[T] with fn json_schema() -> Schema {
  ArraySchema(items=schema_of((None : T?))).into_schema()
}

///|
pub impl[T : JsonSchema] JsonSchema for T? with fn json_schema() -> Schema raise SchemaError {
  AnyOfSchema([NullSchema().into_schema(), schema_of((None : T?))]).into_schema()
}

///|
/// Obtain a typed schema without constructing a runtime value of `A`.
pub fn[A : JsonSchema] schema_of(_witness : A?) -> Schema raise SchemaError {
  A::json_schema()
}
