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
  fields.set_opt("lastModified", self.last_modified.map(Json::string))
  Json::object(fields)
}

///|
pub impl @json.FromJson for Annotations with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> Annotations raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let audience : Array[Role] = match fields.get("audience") {
    None => []
    Some(Array(values)) => {
      let audience : Array[Role] = []
      for i, item in values {
        audience.push(
          @json.from_json(item) catch {
            JsonDecodeError((_, msg)) =>
              raise JsonDecodeError(
                (path.add_key("audience").add_index(i), msg),
              )
          },
        )
      }
      audience
    }
    Some(_) =>
      raise JsonDecodeError((path.add_key("audience"), "expected array"))
  }
  let priority = match fields.get("priority") {
    Some(Number(value, ..)) => {
      if value.is_nan() || value.is_inf() || value < 0.0 || value > 1.0 {
        raise JsonDecodeError(
          (path.add_key("priority"), "priority must be between 0 and 1"),
        )
      }
      Some(value)
    }
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("priority"), "expected number"))
  }
  let last_modified = match fields.get("lastModified") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("lastModified"), "expected string"))
  }
  Annotations(audience~, priority?, last_modified?) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub fn Annotations::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> Annotations raise McpError {
  decode_json(value, path?)
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
    annotations: annotations.map(fn(a) { a.copy() }),
    size,
    meta: meta.map(fn(m) { m.copy() }),
  }
}

///|
pub impl ToJson for ResourceLink with fn to_json(self : ResourceLink) -> Json {
  let fields : Map[String, Json] = {
    "type": Json::string("resource_link"),
    "uri": Json::string(self.uri),
    "name": Json::string(self.name),
  }
  fields.set_opt("title", self.title.map(Json::string))
  fields.set_opt("description", self.description.map(Json::string))
  fields.set_opt("mimeType", self.mime_type.map(Json::string))
  if !self.icons.is_empty() {
    fields["icons"] = self.icons.map(fn(icon) { icon.to_json() }).to_json()
  }
  if self.annotations is Some(annotations) {
    fields["annotations"] = annotations.to_json()
  }
  fields.set_opt(
    "size",
    self.size.map(fn(size) { Json::number(size.to_double(), repr="\{size}") }),
  )
  fields.set_opt("_meta", self.meta.map(fn(m) { m.copy() }))
  Json::object(fields)
}

///|
pub impl @json.FromJson for ResourceLink with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ResourceLink raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let uri = match fields.get("uri") {
    Some(String(u)) => u
    Some(_) => raise JsonDecodeError((path.add_key("uri"), "expected string"))
    None => raise JsonDecodeError((path.add_key("uri"), "uri is required"))
  }
  let name = match fields.get("name") {
    Some(String(n)) => n
    Some(_) => raise JsonDecodeError((path.add_key("name"), "expected string"))
    None => raise JsonDecodeError((path.add_key("name"), "name is required"))
  }
  let title = match fields.get("title") {
    Some(String(t)) => Some(t)
    Some(Null) | None => None
    Some(_) => raise JsonDecodeError((path.add_key("title"), "expected string"))
  }
  let description = match fields.get("description") {
    Some(String(d)) => Some(d)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("description"), "expected string"))
  }
  let mime_type = match fields.get("mimeType") {
    Some(String(m)) => Some(m)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("mimeType"), "expected string"))
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
  let annotations : Annotations? = match fields {
    { "annotations": v, .. } =>
      Some(@json.from_json(v, path=path.add_key("annotations")))
    _ => None
  }
  let size : Int64? = match fields.get("size") {
    Some(Number(s, ..)) => {
      if s < 0.0 || s != s.to_int64().to_double() {
        raise JsonDecodeError(
          (path.add_key("size"), "expected non-negative integer"),
        )
      }
      Some(s.to_int64())
    }
    Some(Null) | None => None
    Some(_) => raise JsonDecodeError((path.add_key("size"), "expected number"))
  }
  let meta = fields.get("_meta")
  ResourceLink(
    uri~,
    name~,
    title?,
    description?,
    mime_type?,
    icons~,
    annotations?,
    size?,
    meta?,
  ) catch {
    error => raise JsonDecodeError((path, error.to_string()))
  }
}

///|
pub fn ResourceLink::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ResourceLink raise McpError {
  decode_json(value, path?)
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
  fields.set_opt("_meta", meta.map(fn(m) { m.copy() }))
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
    annotations=annotations.map(fn(a) { a.copy() }),
    meta=meta.map(fn(m) { m.copy() }),
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
    annotations=annotations.map(fn(a) { a.copy() }),
    meta=meta.map(fn(m) { m.copy() }),
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
    annotations=annotations.map(fn(a) { a.copy() }),
    meta=meta.map(fn(m) { m.copy() }),
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
    annotations=annotations.map(fn(a) { a.copy() }),
    meta=meta.map(fn(m) { m.copy() }),
  )
}

///|
/// Construct a content that links to a readable resource.
pub fn Content::resource_link(resource_link : ResourceLink) -> Content {
  ResourceLink(resource_link)
}

///|
pub impl @json.FromJson for Content with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> Content raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let annotations : Annotations? = match fields {
    { "annotations": v, .. } =>
      Some(@json.from_json(v, path=path.add_key("annotations")))
    _ => None
  }
  let meta = fields.get("_meta")
  match fields.get("type") {
    Some(String("text")) =>
      match fields.get("text") {
        Some(String(text)) => Content::text(text, annotations?, meta?)
        Some(_) =>
          raise JsonDecodeError((path.add_key("text"), "expected string"))
        None =>
          raise JsonDecodeError((path.add_key("text"), "text is required"))
      }
    Some(String("image")) => {
      let data = match fields.get("data") {
        Some(String(d)) => d
        Some(_) =>
          raise JsonDecodeError((path.add_key("data"), "expected string"))
        None =>
          raise JsonDecodeError((path.add_key("data"), "data is required"))
      }
      let mime_type = match fields.get("mimeType") {
        Some(String(m)) => m
        Some(_) =>
          raise JsonDecodeError((path.add_key("mimeType"), "expected string"))
        None =>
          raise JsonDecodeError(
            (path.add_key("mimeType"), "mimeType is required"),
          )
      }
      Content::image(data~, mime_type~, annotations?, meta?)
    }
    Some(String("audio")) => {
      let data = match fields.get("data") {
        Some(String(d)) => d
        Some(_) =>
          raise JsonDecodeError((path.add_key("data"), "expected string"))
        None =>
          raise JsonDecodeError((path.add_key("data"), "data is required"))
      }
      let mime_type = match fields.get("mimeType") {
        Some(String(m)) => m
        Some(_) =>
          raise JsonDecodeError((path.add_key("mimeType"), "expected string"))
        None =>
          raise JsonDecodeError(
            (path.add_key("mimeType"), "mimeType is required"),
          )
      }
      Content::audio(data~, mime_type~, annotations?, meta?)
    }
    Some(String("resource")) => {
      guard fields is { "resource": res_val, .. } else {
        raise JsonDecodeError(
          (path.add_key("resource"), "resource is required"),
        )
      }
      let resource : ResourceContent = @json.from_json(
        res_val,
        path=path.add_key("resource"),
      )
      Content::embedded_resource(resource~, annotations?, meta?)
    }
    Some(String("resource_link")) => {
      let link : ResourceLink = @json.from_json(value, path~)
      Content::resource_link(link)
    }
    Some(String(other)) =>
      raise JsonDecodeError(
        (path.add_key("type"), "unknown content type: \{other}"),
      )
    Some(_) => raise JsonDecodeError((path.add_key("type"), "expected string"))
    None => raise JsonDecodeError((path.add_key("type"), "type is required"))
  }
}

///|
/// Decode one official MCP content union value.
pub fn Content::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> Content raise McpError {
  decode_json(value, path?)
}
