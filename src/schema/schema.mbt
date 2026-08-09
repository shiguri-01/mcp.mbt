///|
/// JSON Schema provider for typed tool inputs.
pub(open) trait JsonSchema {
  fn json_schema() -> Json
}

///|
/// The JSON Schema dialect used by MCP `2026-07-28` when `$schema` is absent.
pub let draft_2020_12 : String = "https://json-schema.org/draft/2020-12/schema"

///|
pub(all) suberror SchemaError {
  InvalidHeaderName(String)
} derive(Debug, Eq)

///|
/// JSON Schema object field descriptor used by `schema`.
pub struct Property {
  priv name : String
  priv schema : Json
  priv required : Bool
} derive(Debug, Eq)

///|
/// Build a JSON Schema object for MCP tool input.
pub fn schema(
  properties : Array[Property],
  additional_properties? : Bool = false,
) -> Json {
  let property_fields : Map[String, Json] = Map([])
  let required : Array[String] = []
  for property in properties {
    property_fields[property.name] = property.schema
    if property.required {
      required.push(property.name)
    }
  }
  Json::object({
    "$schema": Json::string(draft_2020_12),
    "type": Json::string("object"),
    "properties": Json::object(property_fields),
    "required": required.to_json(),
    "additionalProperties": Json::boolean(additional_properties),
  })
}

///|
fn is_http_token_char(char : Char) -> Bool {
  match char {
    'a'..='z'
    | 'A'..='Z'
    | '0'..='9'
    | '!'
    | '#'
    | '$'
    | '%'
    | '&'
    | '\''
    | '*'
    | '+'
    | '-'
    | '.'
    | '^'
    | '_'
    | '`'
    | '|'
    | '~' => true
    _ => false
  }
}

///|
fn validate_header_name(name : String) -> Unit raise SchemaError {
  if name.is_empty() {
    raise InvalidHeaderName("x-mcp-header must not be empty")
  }
  for char in name {
    if !is_http_token_char(char) {
      raise InvalidHeaderName("invalid x-mcp-header name: \{name}")
    }
  }
}

///|
fn with_header(schema : Json, header_name : String) -> Json raise SchemaError {
  validate_header_name(header_name)
  guard schema is Object(fields) else {
    raise InvalidHeaderName("header property schema must be an object")
  }
  fields["x-mcp-header"] = Json::string(header_name)
  Json::object(fields)
}

///|
/// Build an object field from an arbitrary JSON Schema fragment.
pub fn field(
  name~ : String,
  schema~ : Json,
  required? : Bool = false,
) -> Property {
  { name, schema, required }
}

///|
/// Build a JSON Schema string type fragment.
pub fn string_schema(description? : String) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("string") }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
/// Build a JSON Schema integer type fragment.
pub fn integer_schema(description? : String) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("integer") }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
/// Build a JSON Schema number type fragment.
pub fn number_schema(description? : String) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("number") }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
/// Build a JSON Schema boolean type fragment.
pub fn boolean_schema(description? : String) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("boolean") }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
/// Build a string property mirrored to `Mcp-Param-{header_name}` by HTTP.
pub fn header_string(
  name~ : String,
  header_name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property raise SchemaError {
  field(
    name~,
    schema=with_header(string_schema(description?), header_name),
    required~,
  )
}

///|
/// Build an integer property mirrored to `Mcp-Param-{header_name}` by HTTP.
pub fn header_integer(
  name~ : String,
  header_name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property raise SchemaError {
  field(
    name~,
    schema=with_header(integer_schema(description?), header_name),
    required~,
  )
}

///|
/// Build a boolean property mirrored to `Mcp-Param-{header_name}` by HTTP.
pub fn header_boolean(
  name~ : String,
  header_name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property raise SchemaError {
  field(
    name~,
    schema=with_header(boolean_schema(description?), header_name),
    required~,
  )
}

///|
/// Build a JSON Schema array type fragment.
pub fn array_schema(items~ : Json, description? : String) -> Json {
  let fields : Map[String, Json] = {
    "type": Json::string("array"),
    "items": items,
  }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
/// Build a JSON Schema string enum type fragment.
pub fn string_enum_schema(
  values : Array[String],
  description? : String,
) -> Json {
  let fields : Map[String, Json] = {
    "type": Json::string("string"),
    "enum": values.to_json(),
  }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
/// Build a string field for a JSON Schema object.
pub fn string(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property {
  field(name~, schema=string_schema(description?), required~)
}

///|
/// Build an integer field for a JSON Schema object.
pub fn integer(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property {
  field(name~, schema=integer_schema(description?), required~)
}

///|
/// Build a number field for a JSON Schema object.
pub fn number(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property {
  field(name~, schema=number_schema(description?), required~)
}

///|
/// Build a boolean field for a JSON Schema object.
pub fn boolean(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property {
  field(name~, schema=boolean_schema(description?), required~)
}

///|
/// Build an array field for a JSON Schema object.
pub fn array(
  name~ : String,
  items~ : Json,
  description? : String,
  required? : Bool = false,
) -> Property {
  field(name~, schema=array_schema(items~, description?), required~)
}

///|
/// Build a string enum field for a JSON Schema object.
pub fn string_enum(
  name~ : String,
  values~ : Array[String],
  description? : String,
  required? : Bool = false,
) -> Property {
  field(name~, schema=string_enum_schema(values, description?), required~)
}

///|
fn put_optional_string(
  fields : Map[String, Json],
  key : String,
  value : String?,
) -> Unit {
  match value {
    Some(value) => fields[key] = Json::string(value)
    None => ()
  }
}
