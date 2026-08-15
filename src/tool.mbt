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
  fields.set_opt("title", self.title.map(Json::string))
  fields.set_opt("readOnlyHint", self.read_only_hint.map(Json::boolean))
  fields.set_opt("destructiveHint", self.destructive_hint.map(Json::boolean))
  fields.set_opt("idempotentHint", self.idempotent_hint.map(Json::boolean))
  fields.set_opt("openWorldHint", self.open_world_hint.map(Json::boolean))
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
  let read_bool_opt = fn(key : String) -> Bool? raise @json.JsonDecodeError {
    match fields.get(key) {
      Some(True) => Some(true)
      Some(False) => Some(false)
      Some(Null) | None => None
      Some(_) => raise JsonDecodeError((path.add_key(key), "expected boolean"))
    }
  }
  let read_only_hint = read_bool_opt("readOnlyHint")
  let destructive_hint = read_bool_opt("destructiveHint")
  let idempotent_hint = read_bool_opt("idempotentHint")
  let open_world_hint = read_bool_opt("openWorldHint")
  ToolAnnotations(
    title?,
    read_only_hint?,
    destructive_hint?,
    idempotent_hint?,
    open_world_hint?,
  )
}

///|
pub fn ToolAnnotations::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ToolAnnotations raise McpError {
  decode_json(value, path?)
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
    input_schema: self.input_schema.copy(),
    output_schema: self.output_schema.map(fn(s) { s.copy() }),
    icons: self.icons.map(icon => icon.copy()),
    meta: self.meta.map(fn(m) { m.copy() }),
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
  let _ = @schema.Document(input_schema) catch {
    _ =>
      raise InvalidParams(
        "tool inputSchema is not a valid JSON Schema document",
      )
  }
  guard input_schema is Object(fields) else {
    raise InvalidParams("tool inputSchema must be a JSON Schema object")
  }
  guard fields.get("type") is Some(String("object")) else {
    raise InvalidParams("tool inputSchema root type must be \"object\"")
  }
  if output_schema is Some(schema) {
    let _ = @schema.Document(schema) catch {
      _ =>
        raise InvalidParams(
          "tool outputSchema is not a valid JSON Schema document",
        )
    }
  }
  {
    name,
    title,
    description,
    input_schema: input_schema.copy(),
    output_schema: output_schema.map(fn(s) { s.copy() }),
    annotations,
    icons: icons.map(icon => icon.copy()),
    meta: meta.map(fn(m) { m.copy() }),
  }
}

///|
pub impl ToJson for Tool with fn to_json(self : Tool) -> Json {
  let fields : Map[String, Json] = {
    "name": Json::string(self.name),
    "inputSchema": self.input_schema.copy(),
  }
  fields.set_opt("title", self.title.map(Json::string))
  fields.set_opt("description", self.description.map(Json::string))
  fields.set_opt("outputSchema", self.output_schema.map(fn(s) { s.copy() }))
  match self.annotations {
    Some(annotations) => fields["annotations"] = annotations.to_json()
    None => ()
  }
  if !self.icons.is_empty() {
    fields["icons"] = self.icons.map(fn(icon) { icon.to_json() }).to_json()
  }
  fields.set_opt("_meta", self.meta.map(fn(m) { m.copy() }))
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
  guard fields.get("inputSchema") is Some(input_schema) else {
    raise JsonDecodeError(
      (path.add_key("inputSchema"), "inputSchema is required"),
    )
  }
  let output_schema = fields.get("outputSchema")
  let annotations : ToolAnnotations? = match fields.get("annotations") {
    Some(v) => Some(@json.from_json(v, path=path.add_key("annotations")))
    None => None
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
  path? : @json.JsonPath,
) -> Tool raise McpError {
  decode_json(value, path?)
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
    structured_content: structured_content.map(fn(c) { c.copy() }),
    is_error,
    meta: meta.map(fn(m) { m.copy() }),
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
  fields.set_opt(
    "structuredContent",
    self.structured_content.map(fn(c) { c.copy() }),
  )
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
  let content : Array[Content] = match fields.get("content") {
    Some(Array(arr)) => {
      let result : Array[Content] = []
      for i, it in arr {
        result.push(
          @json.from_json(it, path=path.add_key("content").add_index(i)),
        )
      }
      result
    }
    Some(Null) | None => []
    Some(_) =>
      raise JsonDecodeError((path.add_key("content"), "expected array"))
  }
  let structured_content = fields.get("structuredContent")
  let is_error = match fields.get("isError") {
    Some(True) => true
    Some(False | Null) | None => false
    Some(_) =>
      raise JsonDecodeError((path.add_key("isError"), "expected boolean"))
  }
  let meta : ResultMeta? = match fields.get("_meta") {
    Some(v) => Some(@json.from_json(v, path=path.add_key("_meta")))
    None => None
  }
  CallToolResult(content~, structured_content?, is_error~, meta?)
}

///|
pub fn CallToolResult::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> CallToolResult raise McpError {
  decode_json(value, path?)
}

///|
/// Return a plain text tool result.
pub fn CallToolResult::text(
  text : String,
  annotations? : Annotations,
  meta? : Json,
) -> CallToolResult {
  CallToolResult(content=[Content::text(text, annotations?, meta?)])
}

///|
/// Return structured content without a text block.
pub fn CallToolResult::json(value : Json) -> CallToolResult {
  CallToolResult(content=[], structured_content=value)
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
  CallToolResult(
    content=[Content::text(text, annotations?, meta?)],
    is_error=true,
  )
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
  fields.set_opt("nextCursor", self.next_cursor.map(Json::string))
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
  let tools : Array[Tool] = match fields.get("tools") {
    Some(Array(arr)) => {
      let result : Array[Tool] = []
      for i, it in arr {
        result.push(
          @json.from_json(it, path=path.add_key("tools").add_index(i)),
        )
      }
      result
    }
    Some(_) => raise JsonDecodeError((path.add_key("tools"), "expected array"))
    None => raise JsonDecodeError((path.add_key("tools"), "tools is required"))
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
  let meta : ResultMeta? = match fields.get("_meta") {
    Some(v) => Some(@json.from_json(v, path=path.add_key("_meta")))
    None => None
  }
  { tools, next_cursor, cache_policy, meta }
}

///|
pub fn ListToolsResult::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ListToolsResult raise McpError {
  decode_json(value, path?)
}
