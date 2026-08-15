///|
pub struct ToolAnnotations {
  title : String?
  read_only_hint : Bool?
  destructive_hint : Bool?
  idempotent_hint : Bool?
  open_world_hint : Bool?
} derive(Debug, Eq)

///|
/// Construct optional tool behavior annotations.
pub fn ToolAnnotations::ToolAnnotations(
  title? : String,
  read_only_hint? : Bool,
  destructive_hint? : Bool,
  idempotent_hint? : Bool,
  open_world_hint? : Bool,
) -> ToolAnnotations {
  { title, read_only_hint, destructive_hint, idempotent_hint, open_world_hint }
}

///|
pub impl ToJson for ToolAnnotations with fn to_json(self : ToolAnnotations) -> Json {
  let fields : Map[String, Json] = Map([])
  put_optional_string(fields, "title", self.title)
  put_optional_bool(fields, "readOnlyHint", self.read_only_hint)
  put_optional_bool(fields, "destructiveHint", self.destructive_hint)
  put_optional_bool(fields, "idempotentHint", self.idempotent_hint)
  put_optional_bool(fields, "openWorldHint", self.open_world_hint)
  Json::object(fields)
}

///|
pub impl @json.FromJson for ToolAnnotations with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ToolAnnotations raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let title = match fields.get("title") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) => raise JsonDecodeError((path.add_key("title"), "expected string"))
  }
  let read_only_hint = match fields.get("readOnlyHint") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("readOnlyHint"), "expected boolean"))
  }
  let destructive_hint = match fields.get("destructiveHint") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("destructiveHint"), "expected boolean"),
      )
  }
  let idempotent_hint = match fields.get("idempotentHint") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("idempotentHint"), "expected boolean"),
      )
  }
  let open_world_hint = match fields.get("openWorldHint") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("openWorldHint"), "expected boolean"))
  }
  { title, read_only_hint, destructive_hint, idempotent_hint, open_world_hint }
}

///|
pub fn ToolAnnotations::from_json(
  value : Json,
  context? : String = "tool annotations",
) -> ToolAnnotations raise McpError {
  decode_json(value, context~)
}

///|
/// MCP tool descriptor.
pub struct Tool {
  name : String
  title : String?
  description : String?
  input_schema : Json
  output_schema : Json?
  annotations : ToolAnnotations?
  icons : Array[Icon]
  meta : Json?
} derive(Debug, Eq)

///|
/// Copy a tool descriptor before handing it to an adapter.
fn Tool::copy(self : Tool) -> Tool {
  {
    ..self,
    input_schema: copy_json(self.input_schema),
    output_schema: copy_optional_json(self.output_schema),
    icons: self.icons.map(icon => icon.copy()),
    meta: copy_optional_json(self.meta),
  }
}

///|
/// Construct a tool descriptor.
pub fn Tool::Tool(
  name~ : String,
  title? : String,
  description? : String,
  input_schema? : Json = empty_object_schema(),
  output_schema? : Json,
  annotations? : ToolAnnotations,
  icons? : Array[Icon] = [],
  meta? : Json,
) -> Tool raise McpError {
  validate_tool_input_schema(input_schema)
  match output_schema {
    Some(schema) => validate_tool_document(schema, "tool outputSchema")
    None => ()
  }
  {
    name,
    title,
    description,
    input_schema: copy_json(input_schema),
    output_schema: copy_optional_json(output_schema),
    annotations,
    icons: icons.map(icon => icon.copy()),
    meta: copy_optional_json(meta),
  }
}

///|
fn validate_tool_input_schema(schema : Json) -> Unit raise McpError {
  validate_tool_document(schema, "tool inputSchema")
  guard schema is Object(fields) else {
    raise InvalidParams("tool inputSchema must be a JSON Schema object")
  }
  guard fields.get("type") is Some(String("object")) else {
    raise InvalidParams("tool inputSchema root type must be \"object\"")
  }
}

///|
fn validate_tool_document(
  schema : Json,
  context : String,
) -> Unit raise McpError {
  ignore(
    @schema.Document::Document(schema) catch {
      _ => raise InvalidParams("\{context} is not a valid JSON Schema document")
    },
  )
}

///|
pub impl ToJson for Tool with fn to_json(self : Tool) -> Json {
  let fields : Map[String, Json] = {
    "name": Json::string(self.name),
    "inputSchema": copy_json(self.input_schema),
  }
  put_optional_string(fields, "title", self.title)
  put_optional_string(fields, "description", self.description)
  put_optional_json(fields, "outputSchema", self.output_schema)
  match self.annotations {
    Some(annotations) => fields["annotations"] = annotations.to_json()
    None => ()
  }
  if !self.icons.is_empty() {
    fields["icons"] = self.icons.map(fn(icon) { icon.to_json() }).to_json()
  }
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
pub impl @json.FromJson for Tool with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> Tool raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let name = match fields.get("name") {
    Some(String(s)) => s
    Some(_) => raise JsonDecodeError((path.add_key("name"), "expected string"))
    None => raise JsonDecodeError((path.add_key("name"), "name is required"))
  }
  let title = match fields.get("title") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) => raise JsonDecodeError((path.add_key("title"), "expected string"))
  }
  let description = match fields.get("description") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("description"), "expected string"))
  }
  let input_schema = match fields.get("inputSchema") {
    Some(v) => v
    None =>
      raise JsonDecodeError(
        (path.add_key("inputSchema"), "inputSchema is required"),
      )
  }
  let output_schema = fields.get("outputSchema")
  let annotations : ToolAnnotations? = match fields {
    { "annotations": v, .. } =>
      Some(@json.from_json(v, path=path.add_key("annotations")))
    _ => None
  }
  let icons : Array[Icon] = match fields.get("icons") {
    Some(Array(arr)) => {
      let result : Array[Icon] = []
      for i, it in arr {
        result.push(
          @json.from_json(it, path=path.add_key("icons").add_index(i)),
        )
      }
      result
    }
    Some(Null) | None => []
    Some(_) => raise JsonDecodeError((path.add_key("icons"), "expected array"))
  }
  let meta = fields.get("_meta")
  Tool(
    name~,
    title?,
    description?,
    input_schema~,
    output_schema?,
    annotations?,
    icons~,
    meta?,
  ) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub fn Tool::from_json(
  value : Json,
  context? : String = "tool",
) -> Tool raise McpError {
  decode_json(value, context~)
}

///|
pub struct CallToolResult {
  content : Array[Content]
  structured_content : Json?
  is_error : Bool
  meta : ResultMeta?
} derive(Debug, Eq)

///|
/// Construct a tool result with validated ownership of its content array.
pub fn CallToolResult::CallToolResult(
  content~ : Array[Content],
  structured_content? : Json,
  is_error? : Bool = false,
  meta? : ResultMeta,
) -> CallToolResult {
  {
    content: content.copy(),
    structured_content: copy_optional_json(structured_content),
    is_error,
    meta: copy_optional_result_meta(meta),
  }
}

///|
/// Decode the optional structured content as the caller's domain type.
pub fn[T : FromJson] CallToolResult::decode_structured(
  self : CallToolResult,
) -> T raise McpError {
  match self.structured_content {
    Some(value) =>
      @json.from_json(value) catch {
        error => raise InvalidParams(error.to_string())
      }
    None => raise InvalidRequest("tools/call result has no structuredContent")
  }
}

///|
pub impl ToJson for CallToolResult with fn to_json(self : CallToolResult) -> Json {
  let fields : Map[String, Json] = {
    "content": self.content.map(fn(block) { block.to_json() }).to_json(),
    "isError": Json::boolean(self.is_error),
  }
  put_optional_json(fields, "structuredContent", self.structured_content)
  if self.meta is Some(meta) {
    fields["_meta"] = meta.to_json()
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for CallToolResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> CallToolResult raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let content_val = match fields.get("content") {
    Some(Array(arr)) => arr
    Some(_) =>
      raise JsonDecodeError((path.add_key("content"), "expected array"))
    None => []
  }
  let content : Array[Content] = []
  for i, it in content_val {
    content.push(@json.from_json(it, path=path.add_key("content").add_index(i)))
  }
  let structured_content = fields.get("structuredContent")
  let is_error = match fields.get("isError") {
    Some(True) => true
    Some(False) | Some(Null) | None => false
    Some(_) =>
      raise JsonDecodeError((path.add_key("isError"), "expected boolean"))
  }
  let meta : ResultMeta? = match fields {
    { "_meta": v, .. } => Some(@json.from_json(v, path=path.add_key("_meta")))
    _ => None
  }
  { content, structured_content, is_error, meta }
}

///|
pub fn CallToolResult::from_json(value : Json) -> CallToolResult raise McpError {
  decode_json(value, context="tools/call result")
}

///|
/// Return a plain text tool result.
pub fn CallToolResult::text(
  text : String,
  annotations? : Annotations,
  meta? : Json,
) -> CallToolResult {
  {
    content: [Content::text(text, annotations?, meta?)],
    structured_content: None,
    is_error: false,
    meta: None,
  }
}

///|
/// Return structured content without a text block.
pub fn CallToolResult::json(value : Json) -> CallToolResult {
  { content: [], structured_content: Some(value), is_error: false, meta: None }
}

///|
/// Return typed structured content through `ToJson`.
pub fn[T : ToJson] CallToolResult::structured(value : T) -> CallToolResult {
  CallToolResult::json(value.to_json())
}

///|
/// Return a tool error as MCP content, not as a JSON-RPC protocol error.
pub fn CallToolResult::error_text(
  text : String,
  annotations? : Annotations,
  meta? : Json,
) -> CallToolResult {
  {
    content: [Content::text(text, annotations?, meta?)],
    structured_content: None,
    is_error: true,
    meta: None,
  }
}

///|
/// Canonical decoded result of `tools/list`.
pub struct ListToolsResult {
  tools : Array[Tool]
  next_cursor : String?
  cache_policy : CachePolicy
  meta : ResultMeta?
} derive(Debug, Eq)

///|
pub impl ToJson for ListToolsResult with fn to_json(self : ListToolsResult) -> Json {
  let fields : Map[String, Json] = {
    "resultType": ResultType::Complete.to_json(),
    "tools": self.tools.map(fn(t) { t.to_json() }).to_json(),
  }
  put_optional_string(fields, "nextCursor", self.next_cursor)
  self.cache_policy.put(fields)
  if self.meta is Some(meta) {
    fields["_meta"] = meta.to_json()
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for ListToolsResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ListToolsResult raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let tools_val = match fields.get("tools") {
    Some(Array(arr)) => arr
    Some(_) => raise JsonDecodeError((path.add_key("tools"), "expected array"))
    None => raise JsonDecodeError((path.add_key("tools"), "tools is required"))
  }
  let tools : Array[Tool] = []
  for i, it in tools_val {
    tools.push(@json.from_json(it, path=path.add_key("tools").add_index(i)))
  }
  let next_cursor = match fields.get("nextCursor") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("nextCursor"), "expected string"))
  }
  let cache_policy : CachePolicy = @json.from_json(value) catch {
    JsonDecodeError((_, msg)) => raise JsonDecodeError((path, msg))
  }
  let meta : ResultMeta? = match fields {
    { "_meta": v, .. } => Some(@json.from_json(v, path=path.add_key("_meta")))
    _ => None
  }
  { tools, next_cursor, cache_policy, meta }
}

///|
pub fn ListToolsResult::from_json(
  value : Json,
) -> ListToolsResult raise McpError {
  decode_json(value, context="tools/list result")
}
