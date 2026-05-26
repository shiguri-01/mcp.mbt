///|
/// JSON Schema provider for typed tool inputs.
pub(open) trait JsonSchema {
  fn json_schema() -> Json
}

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
  let property_fields : Map[String, Json] = {}
  let required : Array[String] = []
  for property in properties {
    property_fields[property.name] = property.schema
    if property.required {
      required.push(property.name)
    }
  }
  Json::object({
    "type": Json::string("object"),
    "properties": Json::object(property_fields),
    "required": required.to_json(),
    "additionalProperties": Json::boolean(additional_properties),
  })
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
/// Build a JSON Schema string type.
pub fn string(description? : String) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("string") }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
/// Build a JSON Schema integer type.
pub fn integer(description? : String) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("integer") }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
/// Build a JSON Schema number type.
pub fn number(description? : String) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("number") }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
/// Build a JSON Schema boolean type.
pub fn boolean(description? : String) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("boolean") }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
/// Build a JSON Schema array type.
pub fn array(items~ : Json, description? : String) -> Json {
  let fields : Map[String, Json] = {
    "type": Json::string("array"),
    "items": items,
  }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
/// Build a JSON Schema string enum.
pub fn string_enum(values : Array[String], description? : String) -> Json {
  let fields : Map[String, Json] = {
    "type": Json::string("string"),
    "enum": values.to_json(),
  }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
/// Build a string field for a JSON Schema object.
pub fn string_field(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property {
  field(name~, schema=string(description?), required~)
}

///|
/// Build an integer field for a JSON Schema object.
pub fn integer_field(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property {
  field(name~, schema=integer(description?), required~)
}

///|
/// Build a number field for a JSON Schema object.
pub fn number_field(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property {
  field(name~, schema=number(description?), required~)
}

///|
/// Build a boolean field for a JSON Schema object.
pub fn boolean_field(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property {
  field(name~, schema=boolean(description?), required~)
}

///|
/// Build an array field for a JSON Schema object.
pub fn array_field(
  name~ : String,
  items~ : Json,
  description? : String,
  required? : Bool = false,
) -> Property {
  field(name~, schema=array(items~, description?), required~)
}

///|
/// Build a string enum field for a JSON Schema object.
pub fn string_enum_field(
  name~ : String,
  values~ : Array[String],
  description? : String,
  required? : Bool = false,
) -> Property {
  field(name~, schema=string_enum(values, description?), required~)
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
