///|
pub(all) struct Implementation {
  name : String
  version : String
} derive(Debug, Eq)

///|
pub impl ToJson for Implementation with fn to_json(self : Implementation) -> Json {
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
pub impl ToJson for ToolAnnotations with fn to_json(self : ToolAnnotations) -> Json {
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
pub fn Tool::Tool(
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
pub impl ToJson for Tool with fn to_json(self : Tool) -> Json {
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
pub fn Tool::text(
  name~ : String,
  title? : String,
  description? : String,
  input_schema? : Json = empty_object_schema(),
  annotations? : ToolAnnotations,
) -> Tool {
  {
    name,
    title,
    description,
    input_schema,
    output_schema: None,
    annotations,
    meta: None,
  }
}

///|
pub(all) struct Resource {
  uri : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  meta : Json?
} derive(Debug, Eq)

///|
pub fn Resource::Resource(
  uri~ : String,
  name~ : String,
  title? : String,
  description? : String,
  mime_type? : String,
  meta? : Json,
) -> Resource {
  { uri, name, title, description, mime_type, meta }
}

///|
pub impl ToJson for Resource with fn to_json(self : Resource) -> Json {
  let fields : Map[String, Json] = {
    "uri": Json::string(self.uri),
    "name": Json::string(self.name),
  }
  put_optional_string(fields, "title", self.title)
  put_optional_string(fields, "description", self.description)
  put_optional_string(fields, "mimeType", self.mime_type)
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
pub fn Resource::text(
  uri~ : String,
  name~ : String,
  title? : String,
  description? : String,
  mime_type? : String = "text/plain",
) -> Resource {
  { uri, name, title, description, mime_type: Some(mime_type), meta: None }
}

///|
pub(all) enum ResourceContent {
  ResourceText(uri~ : String, text~ : String, mime_type~ : String?)
  ResourceBlob(uri~ : String, blob~ : String, mime_type~ : String?)
} derive(Debug, Eq)

///|
pub impl ToJson for ResourceContent with fn to_json(self : ResourceContent) -> Json {
  let fields : Map[String, Json] = {}
  match self {
    ResourceText(uri~, text~, mime_type~) => {
      fields["uri"] = Json::string(uri)
      fields["text"] = Json::string(text)
      put_optional_string(fields, "mimeType", mime_type)
    }
    ResourceBlob(uri~, blob~, mime_type~) => {
      fields["uri"] = Json::string(uri)
      fields["blob"] = Json::string(blob)
      put_optional_string(fields, "mimeType", mime_type)
    }
  }
  Json::object(fields)
}

///|
pub(all) struct ReadResourceResult {
  contents : Array[ResourceContent]
  meta : Json?
} derive(Debug, Eq)

///|
pub impl ToJson for ReadResourceResult with fn to_json(
  self : ReadResourceResult,
) -> Json {
  let fields : Map[String, Json] = {
    "contents": self.contents.map(fn(content) { content.to_json() }).to_json(),
  }
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
pub fn ReadResourceResult::text(
  uri~ : String,
  text~ : String,
  mime_type? : String,
) -> ReadResourceResult {
  { contents: [ResourceText(uri~, text~, mime_type~)], meta: None }
}

///|
pub(all) struct PromptArgument {
  name : String
  title : String?
  description : String?
  required : Bool
} derive(Debug, Eq)

///|
pub fn PromptArgument::PromptArgument(
  name~ : String,
  title? : String,
  description? : String,
  required? : Bool = false,
) -> PromptArgument {
  { name, title, description, required }
}

///|
pub impl ToJson for PromptArgument with fn to_json(self : PromptArgument) -> Json {
  let fields : Map[String, Json] = { "name": Json::string(self.name) }
  put_optional_string(fields, "title", self.title)
  put_optional_string(fields, "description", self.description)
  if self.required {
    fields["required"] = Json::boolean(true)
  }
  Json::object(fields)
}

///|
pub(all) struct Prompt {
  name : String
  title : String?
  description : String?
  arguments : Array[PromptArgument]
  meta : Json?
} derive(Debug, Eq)

///|
pub fn Prompt::Prompt(
  name~ : String,
  title? : String,
  description? : String,
  arguments? : Array[PromptArgument] = [],
  meta? : Json,
) -> Prompt {
  { name, title, description, arguments, meta }
}

///|
pub impl ToJson for Prompt with fn to_json(self : Prompt) -> Json {
  let fields : Map[String, Json] = { "name": Json::string(self.name) }
  put_optional_string(fields, "title", self.title)
  put_optional_string(fields, "description", self.description)
  if !self.arguments.is_empty() {
    fields["arguments"] = self.arguments
      .map(fn(arg) { arg.to_json() })
      .to_json()
  }
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
pub(all) enum ContentBlock {
  Text(String)
  Image(data~ : String, mime_type~ : String)
  Audio(data~ : String, mime_type~ : String)
  Resource(Json)
} derive(Debug, Eq)

///|
pub impl ToJson for ContentBlock with fn to_json(self : ContentBlock) -> Json {
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
pub impl ToJson for CallToolResult with fn to_json(self : CallToolResult) -> Json {
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
pub fn[T : ToJson] CallToolResult::structured(value : T) -> CallToolResult {
  CallToolResult::json(value.to_json())
}

///|
pub fn CallToolResult::text_json(text : String, value : Json) -> CallToolResult {
  {
    content: [Text(text)],
    structured_content: Some(value),
    is_error: false,
    meta: None,
  }
}

///|
pub fn CallToolResult::error_text(text : String) -> CallToolResult {
  {
    content: [Text(text)],
    structured_content: None,
    is_error: true,
    meta: None,
  }
}

///|
pub(all) struct PromptMessage {
  role : String
  content : ContentBlock
} derive(Debug, Eq)

///|
pub fn PromptMessage::user(text : String) -> PromptMessage {
  { role: "user", content: Text(text) }
}

///|
pub fn PromptMessage::assistant(text : String) -> PromptMessage {
  { role: "assistant", content: Text(text) }
}

///|
pub impl ToJson for PromptMessage with fn to_json(self : PromptMessage) -> Json {
  Json::object({
    "role": Json::string(self.role),
    "content": self.content.to_json(),
  })
}

///|
pub(all) struct GetPromptResult {
  description : String?
  messages : Array[PromptMessage]
  meta : Json?
} derive(Debug, Eq)

///|
pub impl ToJson for GetPromptResult with fn to_json(self : GetPromptResult) -> Json {
  let fields : Map[String, Json] = {
    "messages": self.messages.map(fn(message) { message.to_json() }).to_json(),
  }
  put_optional_string(fields, "description", self.description)
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
pub fn GetPromptResult::user(
  text : String,
  description? : String,
) -> GetPromptResult {
  { description, messages: [PromptMessage::user(text)], meta: None }
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
pub fn ServerCapabilities::full(
  list_changed? : Bool = false,
  experimental? : Json,
) -> ServerCapabilities {
  {
    tools_list_changed: list_changed,
    resources: Some(
      Json::object({ "listChanged": Json::boolean(list_changed) }),
    ),
    prompts: Some(Json::object({ "listChanged": Json::boolean(list_changed) })),
    experimental,
  }
}

///|
pub impl ToJson for ServerCapabilities with fn to_json(
  self : ServerCapabilities,
) -> Json {
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
pub impl ToJson for InitializeResult with fn to_json(self : InitializeResult) -> Json {
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
pub impl ToJson for McpError with fn to_json(self : McpError) -> Json {
  Json::object({
    "code": Json::number(self.code().to_double(), repr="\{self.code()}"),
    "message": Json::string(self.message()),
  })
}
