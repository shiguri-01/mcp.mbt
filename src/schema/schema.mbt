///|
/// JSON Schema provider for typed tool inputs.
pub(open) trait JsonSchema {
  fn json_schema() -> Json raise SchemaError
}

///|
pub impl JsonSchema for String with fn json_schema() -> Json {
  Schema::string().to_json()
}

///|
pub impl JsonSchema for Bool with fn json_schema() -> Json {
  Schema::boolean().to_json()
}

///|
pub impl JsonSchema for Int with fn json_schema() -> Json {
  Schema::integer().to_json()
}

///|
pub impl JsonSchema for Int64 with fn json_schema() -> Json {
  Schema::integer().to_json()
}

///|
pub impl JsonSchema for Double with fn json_schema() -> Json {
  Schema::number().to_json()
}

///|
/// The JSON Schema dialect used by MCP `2026-07-28` when `$schema` is absent.
pub let draft_2020_12 : String = "https://json-schema.org/draft/2020-12/schema"

///|
pub(all) suberror SchemaError {
  InvalidDocument(String)
  UnsupportedDialect(String)
  InvalidSchema(String)
} derive(Debug, Eq)

///|
/// JSON Schema object field descriptor used by `schema`.
pub struct Property {
  name : String
  schema : Schema
  required : Bool
} derive(Debug, Eq)

///|
/// Obtain a typed schema without constructing a runtime value of `A`.
pub fn[A : JsonSchema] schema_of(_witness : A?) -> Schema raise SchemaError {
  Schema::raw(A::json_schema())
}

///|
pub fn Property::Property(
  name~ : String,
  schema~ : Schema,
  required? : Bool = false,
) -> Property raise SchemaError {
  if name.is_empty() {
    raise InvalidSchema("JSON Schema property name must not be empty")
  }
  { name, schema, required }
}

///|
/// Build a typed JSON Schema object for an input value.
pub fn object(
  properties : Array[Property],
  additional_properties? : Bool = false,
) -> Schema raise SchemaError {
  let property_schemas : Map[String, Schema] = Map([])
  let required : Array[String] = []
  for property in properties {
    property_schemas[property.name] = property.schema
    if property.required {
      required.push(property.name)
    }
  }
  Schema::object(properties=property_schemas, required~, additional_properties~)
}

///|
/// Encode a typed object schema for APIs that still accept a JSON Schema value.
pub fn object_json(
  properties : Array[Property],
  additional_properties? : Bool = false,
) -> Json raise SchemaError {
  object(properties, additional_properties~).to_json()
}

///|
/// Build an object field from a typed JSON Schema fragment.
fn property(
  name~ : String,
  schema~ : Schema,
  required? : Bool = false,
) -> Property raise SchemaError {
  Property(name~, schema~, required~)
}

///|
/// Build a JSON Schema string type fragment.
pub fn string_schema(description? : String) -> Schema {
  match description {
    Some(value) => Schema::description(Schema::string(), value)
    None => Schema::string()
  }
}

///|
/// Build a JSON Schema integer type fragment.
pub fn integer_schema(description? : String) -> Schema {
  match description {
    Some(value) => Schema::description(Schema::integer(), value)
    None => Schema::integer()
  }
}

///|
/// Build a JSON Schema number type fragment.
pub fn number_schema(description? : String) -> Schema {
  match description {
    Some(value) => Schema::description(Schema::number(), value)
    None => Schema::number()
  }
}

///|
/// Build a JSON Schema boolean type fragment.
pub fn boolean_schema(description? : String) -> Schema {
  match description {
    Some(value) => Schema::description(Schema::boolean(), value)
    None => Schema::boolean()
  }
}

///|
/// Build a string property mirrored to `Mcp-Param-{header_name}` by HTTP.

///|
/// Build a JSON Schema array type fragment.
pub fn array_schema(items~ : Schema, description? : String) -> Schema {
  let schema = Schema::array(items~)
  match description {
    Some(text) => Schema::description(schema, text)
    None => schema
  }
}

///|
/// Build a JSON Schema string enum type fragment.
pub fn string_enum_schema(
  values : Array[String],
  description? : String,
) -> Schema raise SchemaError {
  let value = Schema::enum_values(values.map(value => Json::string(value)))
  match description {
    Some(description) => Schema::description(value, description)
    None => value
  }
}

///|
/// Build a string field for a JSON Schema object.
pub fn string(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property raise SchemaError {
  property(name~, schema=string_schema(description?), required~)
}

///|
/// Build an integer field for a JSON Schema object.
pub fn integer(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property raise SchemaError {
  property(name~, schema=integer_schema(description?), required~)
}

///|
/// Build a number field for a JSON Schema object.
pub fn number(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property raise SchemaError {
  property(name~, schema=number_schema(description?), required~)
}

///|
/// Build a boolean field for a JSON Schema object.
pub fn boolean(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property raise SchemaError {
  property(name~, schema=boolean_schema(description?), required~)
}

///|
/// Build an array field for a JSON Schema object.
pub fn array(
  name~ : String,
  items~ : Schema,
  description? : String,
  required? : Bool = false,
) -> Property raise SchemaError {
  property(name~, schema=array_schema(items~, description?), required~)
}

///|
/// Build a string enum field for a JSON Schema object.
pub fn string_enum(
  name~ : String,
  values~ : Array[String],
  description? : String,
  required? : Bool = false,
) -> Property raise SchemaError {
  property(name~, schema=string_enum_schema(values, description?), required~)
}
