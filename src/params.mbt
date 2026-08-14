///|
/// Parameters for pagination-supporting list requests (`tools/list`, `resources/list`, etc.).
pub struct ListParams {
  cursor : String?
} derive(Debug, Eq)

///|
pub fn ListParams::ListParams(cursor? : String) -> ListParams {
  { cursor, }
}

///|
pub fn ListParams::from_json(value : Json) -> ListParams raise McpError {
  let fields = expect_object(value, "list params")
  let cursor = get_optional_string(fields, "cursor", "list params")
  { cursor, }
}

///|
/// Parameters for `tools/call`.
pub struct CallToolParams {
  name : String
  arguments : Json
} derive(Debug, Eq)

///|
pub fn CallToolParams::CallToolParams(
  name~ : String,
  arguments? : Json = Json::object({}),
) -> CallToolParams raise McpError {
  if name.is_empty() {
    raise InvalidParams("tool name must not be empty")
  }
  let args = match arguments {
    Object(_) as obj => obj
    Null => Json::object({})
    _ => raise InvalidParams("tools/call params.arguments must be an object")
  }
  { name, arguments: args }
}

///|
pub fn CallToolParams::from_json(value : Json) -> CallToolParams raise McpError {
  let fields = expect_object(value, "tools/call params")
  let name = get_string(fields, "name", "tools/call params")
  let arguments = match fields.get("arguments") {
    Some(Object(_) as args) => args
    Some(Null) | None => Json::object({})
    Some(_) =>
      raise InvalidParams("tools/call params.arguments must be an object")
  }
  CallToolParams(name~, arguments~)
}

///|
/// Parameters for `resources/read`.
pub struct ReadResourceParams {
  uri : String
} derive(Debug, Eq)

///|
pub fn ReadResourceParams::ReadResourceParams(
  uri~ : String,
) -> ReadResourceParams raise McpError {
  if uri.is_empty() {
    raise InvalidParams("resource uri must not be empty")
  }
  { uri, }
}

///|
pub fn ReadResourceParams::from_json(
  value : Json,
) -> ReadResourceParams raise McpError {
  let fields = expect_object(value, "resources/read params")
  let uri = get_string(fields, "uri", "resources/read params")
  ReadResourceParams(uri~)
}

///|
/// Parameters for `prompts/get`.
pub struct GetPromptParams {
  name : String
  arguments : Map[String, String]
} derive(Debug, Eq)

///|
pub fn GetPromptParams::GetPromptParams(
  name~ : String,
  arguments? : Map[String, String] = Map([]),
) -> GetPromptParams raise McpError {
  if name.is_empty() {
    raise InvalidParams("prompt name must not be empty")
  }
  { name, arguments }
}

///|
pub fn GetPromptParams::from_json(
  value : Json,
) -> GetPromptParams raise McpError {
  let fields = expect_object(value, "prompts/get params")
  let name = get_string(fields, "name", "prompts/get params")
  let arguments = get_prompt_arguments(fields)
  GetPromptParams(name~, arguments~)
}
