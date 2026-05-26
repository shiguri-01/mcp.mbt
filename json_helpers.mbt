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

///|
fn put_optional_bool(
  fields : Map[String, Json],
  key : String,
  value : Bool?,
) -> Unit {
  match value {
    Some(value) => fields[key] = Json::boolean(value)
    None => ()
  }
}

///|
fn put_optional_json(
  fields : Map[String, Json],
  key : String,
  value : Json?,
) -> Unit {
  match value {
    Some(value) => fields[key] = value
    None => ()
  }
}

///|
fn empty_object_schema() -> Json {
  object([])
}

///|
/// JSON Schema object property descriptor used by `object`.
pub struct Property {
  priv name : String
  priv schema : Json
  priv required : Bool
} derive(Debug, Eq)

///|
/// Build an object property from an arbitrary JSON Schema fragment.
pub fn prop(
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
pub fn integer(description? : String) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("integer") }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
pub fn number(description? : String) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("number") }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
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
/// Build a required-or-optional string property.
pub fn string_prop(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property {
  prop(name~, schema=string(description?), required~)
}

///|
pub fn integer_prop(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property {
  prop(name~, schema=integer(description?), required~)
}

///|
pub fn number_prop(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property {
  prop(name~, schema=number(description?), required~)
}

///|
pub fn boolean_prop(
  name~ : String,
  description? : String,
  required? : Bool = false,
) -> Property {
  prop(name~, schema=boolean(description?), required~)
}

///|
pub fn array_prop(
  name~ : String,
  items~ : Json,
  description? : String,
  required? : Bool = false,
) -> Property {
  prop(name~, schema=array(items~, description?), required~)
}

///|
pub fn string_enum_prop(
  name~ : String,
  values~ : Array[String],
  description? : String,
  required? : Bool = false,
) -> Property {
  prop(name~, schema=string_enum(values, description?), required~)
}

///|
/// Build a closed JSON Schema object from property descriptors.
pub fn object(
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
fn expect_object(
  value : Json,
  context : String,
) -> Map[String, Json] raise McpError {
  match value {
    Object(fields) => fields
    _ => raise InvalidParams("\{context} must be an object")
  }
}

///|
fn get_string(
  fields : Map[String, Json],
  key : String,
  context : String,
) -> String raise McpError {
  match fields.get(key) {
    Some(String(value)) => value
    Some(_) => raise InvalidParams("\{context}.\{key} must be a string")
    None => raise InvalidParams("\{context}.\{key} is required")
  }
}

///|
fn get_optional_object(
  fields : Map[String, Json],
  key : String,
  context : String,
) -> Json? raise McpError {
  match fields.get(key) {
    Some(Object(_) as value) => Some(value)
    Some(Null) => None
    Some(_) => raise InvalidParams("\{context}.\{key} must be an object")
    None => None
  }
}
