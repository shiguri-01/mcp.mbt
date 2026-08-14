///|
pub(all) enum Role {
  User
  Assistant
} derive(Debug, Eq)

///|
pub fn Role::to_string(self : Role) -> String {
  match self {
    User => "user"
    Assistant => "assistant"
  }
}

///|
pub impl ToJson for Role with fn to_json(self : Role) -> Json {
  Json::string(self.to_string())
}

///|
pub impl @json.FromJson for Role with fn from_json(value, path) -> Role {
  match value {
    String("user") => User
    String("assistant") => Assistant
    _ =>
      raise @json.JsonDecodeError(
        (path, "role must be \"user\" or \"assistant\""),
      )
  }
}

///|
pub struct Annotations {
  audience : Array[Role]
  priority : Double?
  last_modified : String?
} derive(Debug, Eq)

///|
pub fn Annotations::Annotations(
  audience? : Array[Role] = [],
  priority? : Double,
  last_modified? : String,
) -> Annotations raise McpError {
  if priority is Some(value) &&
    (value.is_nan() || value.is_inf() || value < 0.0 || value > 1.0) {
    raise InvalidParams(
      "annotation priority must be finite and between 0 and 1",
    )
  }
  { audience: audience.copy(), priority, last_modified }
}

///|
fn Annotations::copy(self : Annotations) -> Annotations {
  { ..self, audience: self.audience.copy() }
}

///|
fn copy_optional_annotations(value : Annotations?) -> Annotations? {
  value.map(annotation => annotation.copy())
}

///|
pub impl ToJson for Annotations with fn to_json(self : Annotations) -> Json {
  let fields : Map[String, Json] = Map([])
  if !self.audience.is_empty() {
    fields["audience"] = self.audience
      .map(fn(role) { role.to_json() })
      .to_json()
  }
  if self.priority is Some(priority) {
    fields["priority"] = Json::number(priority)
  }
  put_optional_string(fields, "lastModified", self.last_modified)
  Json::object(fields)
}

///|
pub fn Annotations::from_json(
  value : Json,
  context? : String = "annotations",
) -> Annotations raise McpError {
  let fields = expect_object(value, context)
  let audience : Array[Role] = match fields.get("audience") {
    None => []
    Some(Array(values)) => {
      let audience : Array[Role] = []
      for value in values {
        let role : Role = @json.from_json(value) catch {
          JsonDecodeError((_, message)) =>
            raise InvalidParams("\{context}.audience[]: \{message}")
        }
        audience.push(role)
      }
      audience
    }
    Some(_) => raise InvalidParams("\{context}.audience must be an array")
  }
  let priority = match fields.get("priority") {
    Some(Number(value, ..)) => Some(value)
    Some(Null) | None => None
    Some(_) => raise InvalidParams("\{context}.priority must be a number")
  }
  let last_modified = get_optional_string(fields, "lastModified", context)
  Annotations(audience~, priority?, last_modified?)
}

///|
/// A link to a readable resource returned as content.
///
/// `size`, when known, is the raw resource byte length before base64 encoding
/// or tokenization.
pub struct ResourceLink {
  uri : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  icons : Array[Icon]
  annotations : Annotations?
  size : Int64?
  meta : Json?
} derive(Debug, Eq)

///|
pub fn ResourceLink::ResourceLink(
  uri~ : String,
  name~ : String,
  title? : String,
  description? : String,
  mime_type? : String,
  icons? : Array[Icon] = [],
  annotations? : Annotations,
  size? : Int64,
  meta? : Json,
) -> ResourceLink raise McpError {
  if size is Some(value) && value < 0L {
    raise InvalidParams("resource link size must be non-negative")
  }
  {
    uri,
    name,
    title,
    description,
    mime_type,
    icons: icons.map(icon => icon.copy()),
    annotations: copy_optional_annotations(annotations),
    size,
    meta: copy_optional_json(meta),
  }
}

///|
pub impl ToJson for ResourceLink with fn to_json(self : ResourceLink) -> Json {
  let fields : Map[String, Json] = {
    "type": Json::string("resource_link"),
    "uri": Json::string(self.uri),
    "name": Json::string(self.name),
  }
  put_optional_string(fields, "title", self.title)
  put_optional_string(fields, "description", self.description)
  put_optional_string(fields, "mimeType", self.mime_type)
  if !self.icons.is_empty() {
    fields["icons"] = self.icons.map(fn(icon) { icon.to_json() }).to_json()
  }
  if self.annotations is Some(annotations) {
    fields["annotations"] = annotations.to_json()
  }
  put_optional_int64(fields, "size", self.size)
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
/// Content payload accepted by MCP prompts and tool results.
///
/// Corresponds to `Content` in the MCP specification:
/// `TextContent | ImageContent | EmbeddedResource`
pub(all) enum Content {
  TextContent(text~ : String, annotations~ : Annotations?, meta~ : Json?)
  ImageContent(
    data~ : String,
    mime_type~ : String,
    annotations~ : Annotations?,
    meta~ : Json?
  )
  AudioContent(
    data~ : String,
    mime_type~ : String,
    annotations~ : Annotations?,
    meta~ : Json?
  )
  EmbeddedResource(
    resource~ : ResourceContent,
    annotations~ : Annotations?,
    meta~ : Json?
  )
  ResourceLink(ResourceLink)
} derive(Debug, Eq)

///|
fn put_content_metadata(
  fields : Map[String, Json],
  annotations : Annotations?,
  meta : Json?,
) -> Unit {
  if annotations is Some(annotations) {
    fields["annotations"] = annotations.to_json()
  }
  put_optional_json(fields, "_meta", meta)
}

///|
pub impl ToJson for Content with fn to_json(self : Content) -> Json {
  match self {
    TextContent(text~, annotations~, meta~) => {
      let fields : Map[String, Json] = {
        "type": Json::string("text"),
        "text": Json::string(text),
      }
      put_content_metadata(fields, annotations, meta)
      Json::object(fields)
    }
    ImageContent(data~, mime_type~, annotations~, meta~) => {
      let fields : Map[String, Json] = {
        "type": Json::string("image"),
        "data": Json::string(data),
        "mimeType": Json::string(mime_type),
      }
      put_content_metadata(fields, annotations, meta)
      Json::object(fields)
    }
    AudioContent(data~, mime_type~, annotations~, meta~) => {
      let fields : Map[String, Json] = {
        "type": Json::string("audio"),
        "data": Json::string(data),
        "mimeType": Json::string(mime_type),
      }
      put_content_metadata(fields, annotations, meta)
      Json::object(fields)
    }
    EmbeddedResource(resource~, annotations~, meta~) => {
      let fields : Map[String, Json] = {
        "type": Json::string("resource"),
        "resource": resource.to_json(),
      }
      put_content_metadata(fields, annotations, meta)
      Json::object(fields)
    }
    ResourceLink(resource_link) => resource_link.to_json()
  }
}

///|
/// Construct a text content.
pub fn Content::text(
  text : String,
  annotations? : Annotations,
  meta? : Json,
) -> Content {
  TextContent(
    text~,
    annotations=copy_optional_annotations(annotations),
    meta=copy_optional_json(meta),
  )
}

///|
/// Construct an image content from base64-encoded data.
pub fn Content::image(
  data~ : String,
  mime_type~ : String,
  annotations? : Annotations,
  meta? : Json,
) -> Content {
  ImageContent(
    data~,
    mime_type~,
    annotations=copy_optional_annotations(annotations),
    meta=copy_optional_json(meta),
  )
}

///|
/// Construct an audio content from base64-encoded data.
pub fn Content::audio(
  data~ : String,
  mime_type~ : String,
  annotations? : Annotations,
  meta? : Json,
) -> Content {
  AudioContent(
    data~,
    mime_type~,
    annotations=copy_optional_annotations(annotations),
    meta=copy_optional_json(meta),
  )
}

///|
/// Construct a content that embeds resource contents inline.
pub fn Content::embedded_resource(
  resource~ : ResourceContent,
  annotations? : Annotations,
  meta? : Json,
) -> Content {
  EmbeddedResource(
    resource~,
    annotations=copy_optional_annotations(annotations),
    meta=copy_optional_json(meta),
  )
}

///|
/// Construct a content that links to a readable resource.
pub fn Content::resource_link(resource_link : ResourceLink) -> Content {
  ResourceLink(resource_link)
}

///|
/// Decode one official MCP content union value.
pub fn Content::from_json(value : Json) -> Content raise McpError {
  let context = "content"
  let fields = expect_object(value, context)
  let annotations = optional_annotations(fields, context)
  let meta = optional_meta_json(fields, context)
  match get_string(fields, "type", context) {
    "text" =>
      Content::text(get_string(fields, "text", context), annotations?, meta?)
    "image" =>
      Content::image(
        data=get_string(fields, "data", context),
        mime_type=get_string(fields, "mimeType", context),
        annotations?,
        meta?,
      )
    "audio" =>
      Content::audio(
        data=get_string(fields, "data", context),
        mime_type=get_string(fields, "mimeType", context),
        annotations?,
        meta?,
      )
    "resource" =>
      Content::embedded_resource(
        resource=decode_resource_content(
          match fields.get("resource") {
            Some(resource) => resource
            None => raise InvalidParams("content.resource is required")
          },
          "content.resource",
        ),
        annotations?,
        meta?,
      )
    "resource_link" =>
      Content::resource_link(
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
    other => raise InvalidParams("unknown content type: \{other}")
  }
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
  }
  put_optional_json(fields, "structuredContent", self.structured_content)
  if self.is_error {
    fields["isError"] = Json::boolean(true)
  }
  if self.meta is Some(meta) {
    fields["_meta"] = meta.to_json()
  }
  Json::object(fields)
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
