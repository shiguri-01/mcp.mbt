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
pub fn empty_object_schema() -> Json {
  Json::object({
    "type": Json::string("object"),
    "properties": Json::object({}),
  })
}

///|
pub fn string_property_schema(description? : String) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("string") }
  put_optional_string(fields, "description", description)
  Json::object(fields)
}

///|
pub fn object_schema(
  properties~ : Map[String, Json],
  required? : Array[String] = [],
  additional_properties? : Bool = false,
) -> Json {
  Json::object({
    "type": Json::string("object"),
    "properties": Json::object(properties),
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
