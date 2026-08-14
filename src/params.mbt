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
pub impl @json.FromJson for ListParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ListParams raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let cursor = match fields.get("cursor") {
    Some(String(cursor)) => Some(cursor)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("cursor"), "expected string"))
  }
  { cursor, }
}

///|
pub impl ToJson for ListParams with fn to_json(self : ListParams) -> Json {
  let fields : Map[String, Json] = Map([])
  if self.cursor is Some(cursor) {
    fields["cursor"] = Json::string(cursor)
  }
  Json::object(fields)
}

///|
pub fn ListParams::from_json(value : Json) -> ListParams raise McpError {
  decode_json(value, context="list params")
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
pub impl @json.FromJson for CallToolParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> CallToolParams raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let name = match fields.get("name") {
    Some(String(name)) => name
    Some(_) => raise JsonDecodeError((path.add_key("name"), "expected string"))
    None => raise JsonDecodeError((path.add_key("name"), "name is required"))
  }
  if name.is_empty() {
    raise JsonDecodeError((path.add_key("name"), "tool name must not be empty"))
  }
  let arguments = match fields.get("arguments") {
    Some(Object(_) as args) => args
    Some(Null) | None => Json::object({})
    Some(_) =>
      raise JsonDecodeError((path.add_key("arguments"), "expected object"))
  }
  { name, arguments }
}

///|
pub impl ToJson for CallToolParams with fn to_json(self : CallToolParams) -> Json {
  Json::object({ "name": Json::string(self.name), "arguments": self.arguments })
}

///|
pub fn CallToolParams::from_json(value : Json) -> CallToolParams raise McpError {
  decode_json(value, context="tools/call params")
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
pub impl @json.FromJson for ReadResourceParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ReadResourceParams raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let uri = match fields.get("uri") {
    Some(String(uri)) => uri
    Some(_) => raise JsonDecodeError((path.add_key("uri"), "expected string"))
    None => raise JsonDecodeError((path.add_key("uri"), "uri is required"))
  }
  if uri.is_empty() {
    raise JsonDecodeError(
      (path.add_key("uri"), "resource uri must not be empty"),
    )
  }
  { uri, }
}

///|
pub impl ToJson for ReadResourceParams with fn to_json(
  self : ReadResourceParams,
) -> Json {
  Json::object({ "uri": Json::string(self.uri) })
}

///|
pub fn ReadResourceParams::from_json(
  value : Json,
) -> ReadResourceParams raise McpError {
  decode_json(value, context="resources/read params")
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
pub impl @json.FromJson for GetPromptParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> GetPromptParams raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let name = match fields.get("name") {
    Some(String(name)) => name
    Some(_) => raise JsonDecodeError((path.add_key("name"), "expected string"))
    None => raise JsonDecodeError((path.add_key("name"), "name is required"))
  }
  if name.is_empty() {
    raise JsonDecodeError(
      (path.add_key("name"), "prompt name must not be empty"),
    )
  }
  let arguments : Map[String, String] = match fields.get("arguments") {
    Some(Object(map)) => {
      let result : Map[String, String] = Map([])
      for k, v in map {
        match v {
          String(s) => result[k] = s
          _ =>
            raise JsonDecodeError(
              (path.add_key("arguments").add_key(k), "expected string"),
            )
        }
      }
      result
    }
    Some(Null) | None => Map([])
    Some(_) =>
      raise JsonDecodeError((path.add_key("arguments"), "expected object"))
  }
  { name, arguments }
}

///|
pub impl ToJson for GetPromptParams with fn to_json(self : GetPromptParams) -> Json {
  let fields : Map[String, Json] = { "name": Json::string(self.name) }
  if !self.arguments.is_empty() {
    let args : Map[String, Json] = Map([])
    for k, v in self.arguments {
      args[k] = Json::string(v)
    }
    fields["arguments"] = Json::object(args)
  }
  Json::object(fields)
}

///|
pub fn GetPromptParams::from_json(
  value : Json,
) -> GetPromptParams raise McpError {
  decode_json(value, context="prompts/get params")
}
