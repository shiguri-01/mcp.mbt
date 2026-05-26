///|
pub(all) struct Implementation {
  name : String
  version : String
} derive(Debug, Eq)

///|
pub fn Implementation::to_json(self : Implementation) -> Json {
  Json::object({
    "name": Json::string(self.name),
    "version": Json::string(self.version),
  })
}

///|
pub(all) struct ToolAnnotations {
  title : String?
  read_only_hint : Bool?
  destructive_hint : Bool?
  idempotent_hint : Bool?
  open_world_hint : Bool?
} derive(Debug, Eq)

///|
pub fn ToolAnnotations::to_json(self : ToolAnnotations) -> Json {
  let fields : Map[String, Json] = {}
  put_optional_string(fields, "title", self.title)
  put_optional_bool(fields, "readOnlyHint", self.read_only_hint)
  put_optional_bool(fields, "destructiveHint", self.destructive_hint)
  put_optional_bool(fields, "idempotentHint", self.idempotent_hint)
  put_optional_bool(fields, "openWorldHint", self.open_world_hint)
  Json::object(fields)
}

///|
pub(all) struct Tool {
  name : String
  title : String?
  description : String?
  input_schema : Json
  output_schema : Json?
  annotations : ToolAnnotations?
  meta : Json?
} derive(Debug, Eq)

///|
pub fn Tool::to_json(self : Tool) -> Json {
  let fields : Map[String, Json] = {
    "name": Json::string(self.name),
    "inputSchema": self.input_schema,
  }
  put_optional_string(fields, "title", self.title)
  put_optional_string(fields, "description", self.description)
  put_optional_json(fields, "outputSchema", self.output_schema)
  match self.annotations {
    Some(annotations) => fields["annotations"] = annotations.to_json()
    None => ()
  }
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
pub fn Tool::new(
  name~ : String,
  title? : String,
  description? : String,
  input_schema? : Json = empty_object_schema(),
  output_schema? : Json,
  annotations? : ToolAnnotations,
  meta? : Json,
) -> Tool {
  { name, title, description, input_schema, output_schema, annotations, meta }
}

///|
pub(all) enum ContentBlock {
  Text(String)
  Image(data~ : String, mime_type~ : String)
  Audio(data~ : String, mime_type~ : String)
  Resource(Json)
} derive(Debug, Eq)

///|
pub fn ContentBlock::to_json(self : ContentBlock) -> Json {
  match self {
    Text(text) =>
      Json::object({ "type": Json::string("text"), "text": Json::string(text) })
    Image(data~, mime_type~) =>
      Json::object({
        "type": Json::string("image"),
        "data": Json::string(data),
        "mimeType": Json::string(mime_type),
      })
    Audio(data~, mime_type~) =>
      Json::object({
        "type": Json::string("audio"),
        "data": Json::string(data),
        "mimeType": Json::string(mime_type),
      })
    Resource(resource) => resource
  }
}

///|
pub(all) struct CallToolResult {
  content : Array[ContentBlock]
  structured_content : Json?
  is_error : Bool
  meta : Json?
} derive(Debug, Eq)

///|
pub fn CallToolResult::to_json(self : CallToolResult) -> Json {
  let fields : Map[String, Json] = {
    "content": self.content.map(fn(block) { block.to_json() }).to_json(),
  }
  put_optional_json(fields, "structuredContent", self.structured_content)
  if self.is_error {
    fields["isError"] = Json::boolean(true)
  }
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
pub fn CallToolResult::text(text : String) -> CallToolResult {
  {
    content: [Text(text)],
    structured_content: None,
    is_error: false,
    meta: None,
  }
}

///|
pub fn CallToolResult::json(value : Json) -> CallToolResult {
  { content: [], structured_content: Some(value), is_error: false, meta: None }
}

///|
pub(all) struct ServerCapabilities {
  tools_list_changed : Bool
  resources : Json?
  prompts : Json?
  experimental : Json?
} derive(Debug, Eq)

///|
pub fn ServerCapabilities::tools_only(
  list_changed? : Bool = false,
) -> ServerCapabilities {
  {
    tools_list_changed: list_changed,
    resources: None,
    prompts: None,
    experimental: None,
  }
}

///|
pub fn ServerCapabilities::to_json(self : ServerCapabilities) -> Json {
  let fields : Map[String, Json] = {
    "tools": Json::object({
      "listChanged": Json::boolean(self.tools_list_changed),
    }),
  }
  put_optional_json(fields, "resources", self.resources)
  put_optional_json(fields, "prompts", self.prompts)
  put_optional_json(fields, "experimental", self.experimental)
  Json::object(fields)
}

///|
pub(all) struct InitializeResult {
  protocol_version : String
  capabilities : ServerCapabilities
  server_info : Implementation
  instructions : String?
  meta : Json?
} derive(Debug, Eq)

///|
pub fn InitializeResult::to_json(self : InitializeResult) -> Json {
  let fields : Map[String, Json] = {
    "protocolVersion": Json::string(self.protocol_version),
    "capabilities": self.capabilities.to_json(),
    "serverInfo": self.server_info.to_json(),
  }
  put_optional_string(fields, "instructions", self.instructions)
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
pub(all) suberror McpError {
  ParseError(String)
  InvalidRequest(String)
  MethodNotFound(String)
  InvalidParams(String)
  InternalError(String)
} derive(Debug, Eq)

///|
pub fn McpError::code(self : McpError) -> Int {
  match self {
    ParseError(_) => -32700
    InvalidRequest(_) => -32600
    MethodNotFound(_) => -32601
    InvalidParams(_) => -32602
    InternalError(_) => -32603
  }
}

///|
pub fn McpError::message(self : McpError) -> String {
  match self {
    ParseError(message) => message
    InvalidRequest(message) => message
    MethodNotFound(method_name) => "Method not found: \{method_name}"
    InvalidParams(message) => message
    InternalError(message) => message
  }
}

///|
pub fn McpError::to_json(self : McpError) -> Json {
  Json::object({
    "code": Json::number(self.code().to_double(), repr="\{self.code()}"),
    "message": Json::string(self.message()),
  })
}
