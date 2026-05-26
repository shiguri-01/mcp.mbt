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
fn get_cursor(params : Json?, context : String) -> String? raise McpError {
  match params {
    Some(value) =>
      get_optional_string(expect_object(value, context), "cursor", context)
    None => None
  }
}

///|
fn put_next_cursor(fields : Map[String, Json], cursor : String?) -> Unit {
  put_optional_string(fields, "nextCursor", cursor)
}

///|
fn empty_result() -> Json {
  Json::object({})
}
