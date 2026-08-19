///|
/// The JSON Schema dialect used by MCP `2026-07-28` when `$schema` is absent.
pub const DRAFT_2020_12 : String = "https://json-schema.org/draft/2020-12/schema"

///|
/// Errors raised while constructing, compiling, or validating a schema.
pub suberror SchemaError {
  InvalidDocument(String)
  UnsupportedDialect(String)
  UnsupportedKeyword(String)
  InvalidSchema(String)
} derive(Debug, Eq)

///|
pub impl Show for SchemaError with fn output(
  self : SchemaError,
  logger : &Logger,
) -> Unit {
  match self {
    InvalidDocument(msg) => logger.write_string("InvalidDocument: \{msg}")
    UnsupportedDialect(msg) => logger.write_string("UnsupportedDialect: \{msg}")
    UnsupportedKeyword(msg) => logger.write_string("UnsupportedKeyword: \{msg}")
    InvalidSchema(msg) => logger.write_string("InvalidSchema: \{msg}")
  }
}

///|
/// JSON Schema provider for typed tool inputs.
pub(open) trait JsonSchema {
  fn json_schema() -> Schema raise SchemaError
}

///|
pub impl JsonSchema for String with fn json_schema() -> Schema {
  Schema::string() catch {
    _ => Schema::always()
  }
}

///|
pub impl JsonSchema for Bool with fn json_schema() -> Schema {
  Schema::bool_type()
}

///|
pub impl JsonSchema for Int with fn json_schema() -> Schema {
  Schema::integer() catch {
    _ => Schema::always()
  }
}

///|
pub impl JsonSchema for Int64 with fn json_schema() -> Schema {
  Schema::integer() catch {
    _ => Schema::always()
  }
}

///|
pub impl JsonSchema for Double with fn json_schema() -> Schema {
  Schema::number() catch {
    _ => Schema::always()
  }
}

///|
/// A raw JSON value has no narrower instance constraint.
pub impl JsonSchema for Json with fn json_schema() -> Schema {
  Schema::always()
}

///|
pub impl[T : JsonSchema] JsonSchema for Array[T] with fn json_schema() -> Schema raise SchemaError {
  Schema::array(items=schema_of((None : T?)))
}

///|
pub impl[T : JsonSchema] JsonSchema for T? with fn json_schema() -> Schema raise SchemaError {
  Schema::any_of([Schema::null(), schema_of((None : T?))])
}

///|
/// Obtain a typed schema without constructing a runtime value of `A`.
pub fn[A : JsonSchema] schema_of(_witness : A?) -> Schema raise SchemaError {
  A::json_schema()
}

///|
/// Validates a JSON instance against the schema associated with type `T`,
/// and decodes it into `T`.
pub fn[T : JsonSchema + @json.FromJson] decode(
  json : Json,
  max_depth? : Int = 128,
) -> T raise Error {
  let schema = schema_of((None : T?))
  schema.validate(json, max_depth~)
  @json.from_json(json)
}
