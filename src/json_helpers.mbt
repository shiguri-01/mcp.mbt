///|
fn put_optional_string(
  fields : Map[String, Json],
  key : String,
  value : String?,
) -> Unit {
  if value is Some(value) {
    fields[key] = Json::string(value)
  }
}

///|
fn put_optional_bool(
  fields : Map[String, Json],
  key : String,
  value : Bool?,
) -> Unit {
  if value is Some(value) {
    fields[key] = Json::boolean(value)
  }
}

///|
fn put_optional_int64(
  fields : Map[String, Json],
  key : String,
  value : Int64?,
) -> Unit {
  if value is Some(value) {
    fields[key] = Json::number(value.to_double(), repr="\{value}")
  }
}

///|
fn put_optional_json(
  fields : Map[String, Json],
  key : String,
  value : Json?,
) -> Unit {
  if value is Some(value) {
    fields[key] = copy_json(value)
  }
}

///|
/// Copy a JSON value recursively before retaining caller-owned protocol data.
fn copy_json(value : Json) -> Json {
  match value {
    Object(fields) => Json::object(copy_json_map(fields))
    Array(values) => Json::array(values.map(copy_json))
    _ => value
  }
}

///|
fn copy_json_map(values : Map[String, Json]) -> Map[String, Json] {
  let copied : Map[String, Json] = Map([])
  for key, value in values {
    copied[key] = copy_json(value)
  }
  copied
}

///|
fn copy_optional_json(value : Json?) -> Json? {
  value.map(copy_json)
}

///|
fn empty_object_schema() -> Json {
  @schema.schema([])
}

///|
/// Prompt argument provider for typed prompt inputs.
pub(open) trait PromptArguments {
  fn prompt_arguments() -> Array[PromptArgument]
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

///|
fn get_optional_string(
  fields : Map[String, Json],
  key : String,
  context : String,
) -> String? raise McpError {
  match fields.get(key) {
    Some(String(value)) => Some(value)
    Some(Null) | None => None
    Some(_) => raise InvalidParams("\{context}.\{key} must be a string")
  }
}

///|
fn get_optional_bool(
  fields : Map[String, Json],
  key : String,
  context : String,
) -> Bool? raise McpError {
  match fields.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    Some(_) => raise InvalidParams("\{context}.\{key} must be a boolean")
  }
}

///|
fn get_optional_fields(
  fields : Map[String, Json],
  key : String,
  context : String,
) -> Map[String, Json]? raise McpError {
  match fields.get(key) {
    Some(Object(value)) => Some(value)
    Some(Null) | None => None
    Some(_) => raise InvalidParams("\{context}.\{key} must be an object")
  }
}

///|
fn put_next_cursor(fields : Map[String, Json], cursor : String?) -> Unit {
  put_optional_string(fields, "nextCursor", cursor)
}
