///|
pub(all) enum ResultType {
  Complete
  InputRequired
  Extension(String)
} derive(Debug, Eq)

///|
pub fn ResultType::to_string(self : ResultType) -> String {
  match self {
    Complete => "complete"
    InputRequired => "input_required"
    Extension(value) => value
  }
}

///|
pub impl ToJson for ResultType with fn to_json(self : ResultType) -> Json {
  Json::string(self.to_string())
}

///|
pub fn parse_result_type(value : Json) -> ResultType raise McpError {
  match value {
    String("complete") => Complete
    String("input_required") => InputRequired
    String(value) => Extension(value)
    _ => raise InvalidRequest("result.resultType must be a string")
  }
}

///|
pub(all) struct ResultMeta {
  server_info : Implementation?
  extra : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn ResultMeta::ResultMeta(
  server_info? : Implementation,
  extra? : Map[String, Json] = {},
) -> ResultMeta raise McpError {
  validate_meta_map(extra)
  { server_info, extra }
}

///|
pub impl ToJson for ResultMeta with fn to_json(self : ResultMeta) -> Json {
  let fields = self.extra.copy()
  if self.server_info is Some(value) {
    fields["io.modelcontextprotocol/serverInfo"] = value.to_json()
  }
  Json::object(fields)
}

///|
fn parse_result_meta(
  value : Json,
  context : String,
) -> ResultMeta raise McpError {
  let fields = expect_object(value, context)
  validate_meta_map(fields)
  let extra = fields.copy()
  extra.remove("io.modelcontextprotocol/serverInfo")
  let server_info : Implementation? = match
    fields.get("io.modelcontextprotocol/serverInfo") {
    Some(value) =>
      Some(
        @json.from_json(value) catch {
          JsonDecodeError((_, message)) =>
            raise InvalidParams("\{context}.serverInfo: \{message}")
        },
      )
    None => None
  }
  ResultMeta(server_info?, extra~)
}

///|
fn merge_result_meta(
  fields : Map[String, Json],
  server_info? : Implementation,
  extra? : Map[String, Json] = {},
) -> Unit raise McpError {
  let merged = match fields.get("_meta") {
    Some(value) => expect_object(value, "result._meta").copy()
    None => Map([])
  }
  validate_meta_map(merged)
  validate_meta_map(extra)
  for key, value in extra {
    merged[key] = value
  }
  if server_info is Some(value) {
    merged["io.modelcontextprotocol/serverInfo"] = value.to_json()
  }
  if !merged.is_empty() {
    fields["_meta"] = Json::object(merged)
  }
}

///|
/// Stamp a method-specific result object with mandatory modern result metadata.
pub fn complete_result(
  value : Json,
  server_info? : Implementation,
  meta? : Map[String, Json] = {},
) -> Json raise McpError {
  let fields = expect_object(value, "complete result").copy()
  fields["resultType"] = ResultType::Complete.to_json()
  merge_result_meta(fields, server_info?, extra=meta)
  Json::object(fields)
}

///|
pub(all) enum CacheScope {
  Public
  Private
} derive(Debug, Eq)

///|
pub fn CacheScope::to_string(self : CacheScope) -> String {
  match self {
    Public => "public"
    Private => "private"
  }
}

///|
pub impl ToJson for CacheScope with fn to_json(self : CacheScope) -> Json {
  Json::string(self.to_string())
}

///|
pub fn parse_cache_scope(value : Json) -> CacheScope raise McpError {
  match value {
    String("public") => Public
    String("private") => Private
    _ => raise InvalidParams("cacheScope must be 'public' or 'private'")
  }
}

///|
/// Validated caching advice for discover, list, and resource read results.
pub struct CachePolicy {
  ttl_ms : Int64
  scope : CacheScope
} derive(Debug, Eq)

///|
pub fn CachePolicy::CachePolicy(
  ttl_ms~ : Int64,
  scope? : CacheScope = Private,
) -> CachePolicy raise McpError {
  if ttl_ms < 0L {
    raise InvalidParams("cache ttlMs must be non-negative")
  }
  { ttl_ms, scope }
}

///|
pub fn CachePolicy::ttl_ms(self : CachePolicy) -> Int64 {
  self.ttl_ms
}

///|
pub fn CachePolicy::scope(self : CachePolicy) -> CacheScope {
  self.scope
}

///|
pub impl ToJson for CachePolicy with fn to_json(self : CachePolicy) -> Json {
  Json::object({
    "ttlMs": Json::number(self.ttl_ms.to_double(), repr="\{self.ttl_ms}"),
    "cacheScope": self.scope.to_json(),
  })
}

///|
fn CachePolicy::put(self : CachePolicy, fields : Map[String, Json]) -> Unit {
  fields["ttlMs"] = Json::number(self.ttl_ms.to_double(), repr="\{self.ttl_ms}")
  fields["cacheScope"] = self.scope.to_json()
}

///|
/// Canonical decoded result of `tools/list`.
pub(all) struct ListToolsResult {
  tools : Array[Tool]
  next_cursor : String?
  cache_policy : CachePolicy
  meta : ResultMeta?
} derive(Debug, Eq)

///|
/// Canonical decoded result of `resources/list`.
pub(all) struct ListResourcesResult {
  resources : Array[Resource]
  next_cursor : String?
  cache_policy : CachePolicy
  meta : ResultMeta?
} derive(Debug, Eq)

///|
/// Canonical decoded result of `resources/templates/list`.
pub(all) struct ListResourceTemplatesResult {
  resource_templates : Array[ResourceTemplate]
  next_cursor : String?
  cache_policy : CachePolicy
  meta : ResultMeta?
} derive(Debug, Eq)

///|
/// Canonical decoded result of `prompts/list`.
pub(all) struct ListPromptsResult {
  prompts : Array[Prompt]
  next_cursor : String?
  cache_policy : CachePolicy
  meta : ResultMeta?
} derive(Debug, Eq)

///|
fn complete_result_fields(
  value : Json,
  context : String,
) -> Map[String, Json] raise McpError {
  let fields = expect_object(value, context)
  match fields.get("resultType") {
    None | Some(String("complete")) => fields
    Some(String(value)) =>
      raise InvalidParams(
        "\{context}.resultType must be complete, got \{value}",
      )
    Some(_) => raise InvalidParams("\{context}.resultType must be a string")
  }
}

///|
fn decoded_result_meta(
  fields : Map[String, Json],
  context : String,
) -> ResultMeta? raise McpError {
  match fields.get("_meta") {
    Some(value) => Some(parse_result_meta(value, "\{context}._meta"))
    None => None
  }
}

///|
fn decoded_cache_policy(
  fields : Map[String, Json],
  context : String,
) -> CachePolicy raise McpError {
  let scope = match fields.get("cacheScope") {
    Some(value) => parse_cache_scope(value)
    None => raise InvalidParams("\{context}.cacheScope is required")
  }
  CachePolicy(ttl_ms=parse_ttl_ms(fields, context), scope~)
}

///|
fn decode_icons(
  fields : Map[String, Json],
  context : String,
) -> Array[Icon] raise McpError {
  match fields.get("icons") {
    None => []
    Some(Array(values)) => {
      let icons : Array[Icon] = []
      for value in values {
        icons.push(
          @json.from_json(value) catch {
            JsonDecodeError((_, message)) =>
              raise InvalidParams("\{context}.icons: \{message}")
          },
        )
      }
      icons
    }
    Some(_) => raise InvalidParams("\{context}.icons must be an array")
  }
}

///|
fn decode_annotations(
  value : Json,
  context : String,
) -> Annotations raise McpError {
  let fields = expect_object(value, context)
  let audience : Array[Role] = []
  match fields.get("audience") {
    None => ()
    Some(Array(values)) =>
      for value in values {
        audience.push(
          @json.from_json(value) catch {
            JsonDecodeError((_, message)) =>
              raise InvalidParams("\{context}.audience: \{message}")
          },
        )
      }
    Some(_) => raise InvalidParams("\{context}.audience must be an array")
  }
  let priority = match fields.get("priority") {
    Some(Number(value, ..)) => Some(value)
    Some(Null) | None => None
    Some(_) => raise InvalidParams("\{context}.priority must be a number")
  }
  Annotations(
    audience~,
    priority?,
    last_modified?=get_optional_string(fields, "lastModified", context),
  )
}

///|
fn optional_annotations(
  fields : Map[String, Json],
  context : String,
) -> Annotations? raise McpError {
  match fields.get("annotations") {
    Some(value) => Some(decode_annotations(value, "\{context}.annotations"))
    None => None
  }
}

///|
fn optional_meta_json(
  fields : Map[String, Json],
  context : String,
) -> Json? raise McpError {
  match fields.get("_meta") {
    Some(Object(_) as value) => Some(value)
    Some(_) => raise InvalidParams("\{context}._meta must be an object")
    None => None
  }
}

///|
fn optional_size(
  fields : Map[String, Json],
  context : String,
) -> Int64? raise McpError {
  match fields.get("size") {
    Some(Number(value, ..)) if value >= 0.0 &&
      value == value.to_int64().to_double() => Some(value.to_int64())
    Some(Null) | None => None
    Some(_) =>
      raise InvalidParams("\{context}.size must be a non-negative integer")
  }
}

///|
fn decode_resource_content(
  value : Json,
  context : String,
) -> ResourceContent raise McpError {
  let fields = expect_object(value, context)
  let uri = get_string(fields, "uri", context)
  let mime_type = get_optional_string(fields, "mimeType", context)
  let meta = optional_meta_json(fields, context)
  match (fields.get("text"), fields.get("blob")) {
    (Some(String(text)), None) =>
      ResourceContent::text(uri~, text~, mime_type?, meta?)
    (None, Some(String(blob))) =>
      ResourceContent::blob(uri~, blob~, mime_type?, meta?)
    _ =>
      raise InvalidParams(
        "\{context} must contain exactly one string field: text or blob",
      )
  }
}

///|
/// Decode one official MCP content union value.
pub fn decode_content_block(value : Json) -> ContentBlock raise McpError {
  let context = "content block"
  let fields = expect_object(value, context)
  let annotations = optional_annotations(fields, context)
  let meta = optional_meta_json(fields, context)
  match get_string(fields, "type", context) {
    "text" =>
      ContentBlock::text(
        get_string(fields, "text", context),
        annotations?,
        meta?,
      )
    "image" =>
      ContentBlock::image(
        data=get_string(fields, "data", context),
        mime_type=get_string(fields, "mimeType", context),
        annotations?,
        meta?,
      )
    "audio" =>
      ContentBlock::audio(
        data=get_string(fields, "data", context),
        mime_type=get_string(fields, "mimeType", context),
        annotations?,
        meta?,
      )
    "resource" =>
      ContentBlock::embedded_resource(
        resource=decode_resource_content(
          match fields.get("resource") {
            Some(resource) => resource
            None => raise InvalidParams("content block.resource is required")
          },
          "content block.resource",
        ),
        annotations?,
        meta?,
      )
    "resource_link" =>
      ContentBlock::resource_link(
        ResourceLink(
          uri=get_string(fields, "uri", context),
          name=get_string(fields, "name", context),
          title?=get_optional_string(fields, "title", context),
          description?=get_optional_string(fields, "description", context),
          mime_type?=get_optional_string(fields, "mimeType", context),
          icons=decode_icons(fields, context),
          annotations?,
          size?=optional_size(fields, context),
          meta?,
        ),
      )
    other => raise InvalidParams("unknown content block type: \{other}")
  }
}

///|
fn decode_content_array(
  fields : Map[String, Json],
  key : String,
  context : String,
) -> Array[ContentBlock] raise McpError {
  guard fields.get(key) is Some(Array(values)) else {
    raise InvalidParams("\{context}.\{key} must be an array")
  }
  values.map(value => decode_content_block(value))
}

///|
/// Decode the complete payload of `tools/call`.
pub fn decode_call_tool_result(value : Json) -> CallToolResult raise McpError {
  let fields = complete_result_fields(value, "tools/call result")
  {
    content: decode_content_array(fields, "content", "tools/call result"),
    structured_content: fields.get("structuredContent"),
    is_error: get_optional_bool(fields, "isError", "tools/call result").unwrap_or(
      false,
    ),
    meta: decoded_result_meta(fields, "tools/call result"),
  }
}

///|
/// Decode the complete payload of `resources/read`.
pub fn decode_read_resource_result(
  value : Json,
) -> ReadResourceResult raise McpError {
  let fields = complete_result_fields(value, "resources/read result")
  guard fields.get("contents") is Some(Array(values)) else {
    raise InvalidParams("resources/read result.contents must be an array")
  }
  {
    contents: values.map(value => {
      decode_resource_content(value, "resources/read result.contents[]")
    }),
    cache_policy: Some(decoded_cache_policy(fields, "resources/read result")),
    meta: decoded_result_meta(fields, "resources/read result"),
  }
}

///|
fn decode_prompt_message(
  value : Json,
  context : String,
) -> PromptMessage raise McpError {
  let fields = expect_object(value, context)
  PromptMessage(
    role={
      let value = match fields.get("role") {
        Some(role) => role
        None => raise InvalidParams("\{context}.role is required")
      }
      @json.from_json(value) catch {
        JsonDecodeError((_, message)) =>
          raise InvalidParams("\{context}.role: \{message}")
      }
    },
    content=decode_content_block(
      match fields.get("content") {
        Some(content) => content
        None => raise InvalidParams("\{context}.content is required")
      },
    ),
  )
}

///|
/// Decode the complete payload of `prompts/get`.
pub fn decode_get_prompt_result(value : Json) -> GetPromptResult raise McpError {
  let fields = complete_result_fields(value, "prompts/get result")
  guard fields.get("messages") is Some(Array(values)) else {
    raise InvalidParams("prompts/get result.messages must be an array")
  }
  {
    description: get_optional_string(
      fields, "description", "prompts/get result",
    ),
    messages: values.map(value => {
      decode_prompt_message(value, "prompts/get result.messages[]")
    }),
    meta: decoded_result_meta(fields, "prompts/get result"),
  }
}

///|
/// Decode the complete payload of `completion/complete`.
pub fn decode_complete_result(value : Json) -> CompleteResult raise McpError {
  let fields = complete_result_fields(value, "completion/complete result")
  let completion = expect_object(
    match fields.get("completion") {
      Some(value) => value
      None =>
        raise InvalidParams("completion/complete result.completion is required")
    },
    "completion/complete result.completion",
  )
  guard completion.get("values") is Some(Array(raw_values)) else {
    raise InvalidParams(
      "completion/complete result.completion.values must be an array",
    )
  }
  let values : Array[String] = []
  for value in raw_values {
    match value {
      String(value) => values.push(value)
      _ =>
        raise InvalidParams(
          "completion/complete result.completion.values must contain strings",
        )
    }
  }
  let total = match completion.get("total") {
    Some(Number(value, ..)) if value >= 0.0 &&
      value == value.to_int().to_double() => Some(value.to_int())
    Some(Null) | None => None
    Some(_) =>
      raise InvalidParams(
        "completion/complete result.completion.total must be a non-negative integer",
      )
  }
  let result = CompleteResult(
    values~,
    total?,
    has_more=get_optional_bool(
      completion, "hasMore", "completion/complete result.completion",
    ).unwrap_or(false),
  )
  { ..result, meta: decoded_result_meta(fields, "completion/complete result") }
}

///|
fn decode_tool_annotations(
  value : Json,
  context : String,
) -> ToolAnnotations raise McpError {
  let fields = expect_object(value, context)
  {
    title: get_optional_string(fields, "title", context),
    read_only_hint: get_optional_bool(fields, "readOnlyHint", context),
    destructive_hint: get_optional_bool(fields, "destructiveHint", context),
    idempotent_hint: get_optional_bool(fields, "idempotentHint", context),
    open_world_hint: get_optional_bool(fields, "openWorldHint", context),
  }
}

///|
fn decode_tool(value : Json, context : String) -> Tool raise McpError {
  let fields = expect_object(value, context)
  Tool(
    name=get_string(fields, "name", context),
    title?=get_optional_string(fields, "title", context),
    description?=get_optional_string(fields, "description", context),
    input_schema=match fields.get("inputSchema") {
      Some(schema) => schema
      None => raise InvalidParams("\{context}.inputSchema is required")
    },
    output_schema?=fields.get("outputSchema"),
    annotations?=match fields.get("annotations") {
      Some(value) =>
        Some(decode_tool_annotations(value, "\{context}.annotations"))
      None => None
    },
    icons=decode_icons(fields, context),
    meta?=optional_meta_json(fields, context),
  )
}

///|
fn decode_resource(value : Json, context : String) -> Resource raise McpError {
  let fields = expect_object(value, context)
  Resource(
    uri=get_string(fields, "uri", context),
    name=get_string(fields, "name", context),
    title?=get_optional_string(fields, "title", context),
    description?=get_optional_string(fields, "description", context),
    mime_type?=get_optional_string(fields, "mimeType", context),
    icons=decode_icons(fields, context),
    annotations?=optional_annotations(fields, context),
    size?=optional_size(fields, context),
    meta?=optional_meta_json(fields, context),
  )
}

///|
fn decode_resource_template(
  value : Json,
  context : String,
) -> ResourceTemplate raise McpError {
  let fields = expect_object(value, context)
  ResourceTemplate(
    uri_template=get_string(fields, "uriTemplate", context),
    name=get_string(fields, "name", context),
    title?=get_optional_string(fields, "title", context),
    description?=get_optional_string(fields, "description", context),
    mime_type?=get_optional_string(fields, "mimeType", context),
    icons=decode_icons(fields, context),
    annotations?=optional_annotations(fields, context),
    meta?=optional_meta_json(fields, context),
  )
}

///|
fn decode_prompt_argument(
  value : Json,
  context : String,
) -> PromptArgument raise McpError {
  let fields = expect_object(value, context)
  PromptArgument(
    name=get_string(fields, "name", context),
    title?=get_optional_string(fields, "title", context),
    description?=get_optional_string(fields, "description", context),
    required=get_optional_bool(fields, "required", context).unwrap_or(false),
  )
}

///|
fn decode_prompt(value : Json, context : String) -> Prompt raise McpError {
  let fields = expect_object(value, context)
  let arguments : Array[PromptArgument] = []
  match fields.get("arguments") {
    None => ()
    Some(Array(values)) =>
      for value in values {
        arguments.push(decode_prompt_argument(value, "\{context}.arguments[]"))
      }
    Some(_) => raise InvalidParams("\{context}.arguments must be an array")
  }
  validate_prompt_argument_names(arguments, "\{context}.arguments")
  Prompt(
    name=get_string(fields, "name", context),
    title?=get_optional_string(fields, "title", context),
    description?=get_optional_string(fields, "description", context),
    arguments~,
    icons=decode_icons(fields, context),
    meta?=optional_meta_json(fields, context),
  )
}

///|
/// Decode the canonical cacheable payload of `tools/list`.
pub fn decode_list_tools_result(value : Json) -> ListToolsResult raise McpError {
  let context = "tools/list result"
  let fields = complete_result_fields(value, context)
  guard fields.get("tools") is Some(Array(values)) else {
    raise InvalidParams("tools/list result.tools must be an array")
  }
  {
    tools: values.map(value => decode_tool(value, "tools/list result.tools[]")),
    next_cursor: get_optional_string(fields, "nextCursor", context),
    cache_policy: decoded_cache_policy(fields, context),
    meta: decoded_result_meta(fields, context),
  }
}

///|
/// Decode the canonical cacheable payload of `resources/list`.
pub fn decode_list_resources_result(
  value : Json,
) -> ListResourcesResult raise McpError {
  let context = "resources/list result"
  let fields = complete_result_fields(value, context)
  guard fields.get("resources") is Some(Array(values)) else {
    raise InvalidParams("resources/list result.resources must be an array")
  }
  {
    resources: values.map(value => {
      decode_resource(value, "resources/list result.resources[]")
    }),
    next_cursor: get_optional_string(fields, "nextCursor", context),
    cache_policy: decoded_cache_policy(fields, context),
    meta: decoded_result_meta(fields, context),
  }
}

///|
/// Decode the canonical cacheable payload of `resources/templates/list`.
pub fn decode_list_resource_templates_result(
  value : Json,
) -> ListResourceTemplatesResult raise McpError {
  let context = "resources/templates/list result"
  let fields = complete_result_fields(value, context)
  guard fields.get("resourceTemplates") is Some(Array(values)) else {
    raise InvalidParams(
      "resources/templates/list result.resourceTemplates must be an array",
    )
  }
  {
    resource_templates: values.map(value => {
      decode_resource_template(
        value, "resources/templates/list result.resourceTemplates[]",
      )
    }),
    next_cursor: get_optional_string(fields, "nextCursor", context),
    cache_policy: decoded_cache_policy(fields, context),
    meta: decoded_result_meta(fields, context),
  }
}

///|
/// Decode the canonical cacheable payload of `prompts/list`.
pub fn decode_list_prompts_result(
  value : Json,
) -> ListPromptsResult raise McpError {
  let context = "prompts/list result"
  let fields = complete_result_fields(value, context)
  guard fields.get("prompts") is Some(Array(values)) else {
    raise InvalidParams("prompts/list result.prompts must be an array")
  }
  {
    prompts: values.map(value => {
      decode_prompt(value, "prompts/list result.prompts[]")
    }),
    next_cursor: get_optional_string(fields, "nextCursor", context),
    cache_policy: decoded_cache_policy(fields, context),
    meta: decoded_result_meta(fields, context),
  }
}
