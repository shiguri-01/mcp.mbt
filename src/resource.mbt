///|
/// Resource descriptor returned by `resources/list`.
///
/// `size`, when known, is the raw resource byte length before base64 encoding
/// or tokenization.
pub struct Resource {
  uri : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  icons : Array[Icon]
  annotations : Annotations?
  size : Int64?
  meta : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a text resource descriptor.
pub fn Resource::text(
  uri~ : String,
  name~ : String,
  title? : String,
  description? : String,
  mime_type? : String = "text/plain",
  annotations? : Annotations,
  size? : Int64,
  meta? : Map[String, Json] = {},
) -> Resource raise McpError {
  Resource::Resource(
    uri~,
    name~,
    title?,
    description?,
    mime_type~,
    annotations?,
    size?,
    meta~,
  )
}

///|
/// Construct a resource descriptor.
pub fn Resource::Resource(
  uri~ : String,
  name~ : String,
  title? : String,
  description? : String,
  mime_type? : String,
  icons? : Array[Icon] = [],
  annotations? : Annotations,
  size? : Int64,
  meta? : Map[String, Json] = {},
) -> Resource raise McpError {
  if uri.is_empty() {
    raise InvalidParams("resource uri must not be empty")
  }
  if name.is_empty() {
    raise InvalidParams("resource name must not be empty")
  }
  if size is Some(value) && value < 0L {
    raise InvalidParams("resource size must be non-negative")
  }
  validate_meta_map(meta)
  {
    uri,
    name,
    title,
    description,
    mime_type,
    icons: icons.map(icon => icon.copy()),
    annotations: annotations.map(fn(a) { a.copy() }),
    size,
    meta: meta.copy_json(),
  }
}

///|
pub impl ToJson for Resource with fn to_json(self : Resource) -> Json {
  let fields : Map[String, Json] = {
    "uri": Json::string(self.uri),
    "name": Json::string(self.name),
  }
  fields.set_opt("title", self.title.map(Json::string))
  fields.set_opt("description", self.description.map(Json::string))
  fields.set_opt("mimeType", self.mime_type.map(Json::string))
  if !self.icons.is_empty() {
    fields["icons"] = self.icons
      .map(fn(icon) { ToJson::to_json(icon) })
      .to_json()
  }
  if self.annotations is Some(annotations) {
    fields["annotations"] = ToJson::to_json(annotations)
  }
  fields.set_opt(
    "size",
    self.size.map(fn(size) { Json::number(size.to_double(), repr="\{size}") }),
  )
  if !self.meta.is_empty() {
    fields["_meta"] = Json::object(self.meta.copy_json())
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for Resource with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> Resource raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let uri = match fields.get("uri") {
    Some(String(s)) => s
    Some(_) => raise JsonDecodeError((path.add_key("uri"), "expected string"))
    None => raise JsonDecodeError((path.add_key("uri"), "uri is required"))
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
  let mime_type = match fields.get("mimeType") {
    Some(String(s)) => Some(s)
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
  let annotations : Annotations? = match fields.get("annotations") {
    Some(v) => Some(@json.from_json(v, path=path.add_key("annotations")))
    None => None
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
  let meta : Map[String, Json] = match fields.get("_meta") {
    Some(Object(m)) => {
      validate_meta_map(m) catch {
        error => raise JsonDecodeError((path.add_key("_meta"), error.message()))
      }
      m.copy_json()
    }
    Some(Null) | None => Map([])
    Some(_) => raise JsonDecodeError((path.add_key("_meta"), "expected object"))
  }
  Resource(
    uri~,
    name~,
    title?,
    description?,
    mime_type?,
    icons~,
    annotations?,
    size?,
    meta~,
  ) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub fn Resource::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> Resource raise McpError {
  decode_json(value, path?)
}

///|
/// Resource template descriptor returned by `resources/templates/list`.
pub struct ResourceTemplate {
  uri_template : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  icons : Array[Icon]
  annotations : Annotations?
  meta : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a resource template descriptor.
pub fn ResourceTemplate::ResourceTemplate(
  uri_template~ : String,
  name~ : String,
  title? : String,
  description? : String,
  mime_type? : String,
  icons? : Array[Icon] = [],
  annotations? : Annotations,
  meta? : Map[String, Json] = {},
) -> ResourceTemplate raise McpError {
  validate_meta_map(meta)
  {
    uri_template,
    name,
    title,
    description,
    mime_type,
    icons: icons.map(icon => icon.copy()),
    annotations: annotations.map(fn(a) { a.copy() }),
    meta: meta.copy_json(),
  }
}

///|
pub impl ToJson for ResourceTemplate with fn to_json(self : ResourceTemplate) -> Json {
  let fields : Map[String, Json] = {
    "uriTemplate": Json::string(self.uri_template),
    "name": Json::string(self.name),
  }
  fields.set_opt("title", self.title.map(Json::string))
  fields.set_opt("description", self.description.map(Json::string))
  fields.set_opt("mimeType", self.mime_type.map(Json::string))
  if !self.icons.is_empty() {
    fields["icons"] = self.icons
      .map(fn(icon) { ToJson::to_json(icon) })
      .to_json()
  }
  if self.annotations is Some(annotations) {
    fields["annotations"] = ToJson::to_json(annotations)
  }
  if !self.meta.is_empty() {
    fields["_meta"] = Json::object(self.meta.copy_json())
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for ResourceTemplate with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ResourceTemplate raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let uri_template = match fields.get("uriTemplate") {
    Some(String(s)) => s
    Some(_) =>
      raise JsonDecodeError((path.add_key("uriTemplate"), "expected string"))
    None =>
      raise JsonDecodeError(
        (path.add_key("uriTemplate"), "uriTemplate is required"),
      )
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
  let mime_type = match fields.get("mimeType") {
    Some(String(s)) => Some(s)
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
  let annotations : Annotations? = match fields.get("annotations") {
    Some(v) => Some(@json.from_json(v, path=path.add_key("annotations")))
    None => None
  }
  let meta : Map[String, Json] = match fields.get("_meta") {
    Some(Object(m)) => {
      validate_meta_map(m) catch {
        error => raise JsonDecodeError((path.add_key("_meta"), error.message()))
      }
      m.copy_json()
    }
    Some(Null) | None => Map([])
    Some(_) => raise JsonDecodeError((path.add_key("_meta"), "expected object"))
  }
  ResourceTemplate(
    uri_template~,
    name~,
    title?,
    description?,
    mime_type?,
    icons~,
    annotations?,
    meta~,
  ) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub fn ResourceTemplate::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ResourceTemplate raise McpError {
  decode_json(value, path?)
}

///|
/// Resource contents returned by `resources/read`.
pub(all) enum ResourceContent {
  ResourceText(
    uri~ : String,
    text~ : String,
    mime_type~ : String?,
    meta~ : Json?
  )
  ResourceBlob(
    uri~ : String,
    blob~ : String,
    mime_type~ : String?,
    meta~ : Json?
  )
} derive(Debug, Eq)

///|
pub impl ToJson for ResourceContent with fn to_json(self : ResourceContent) -> Json {
  let fields : Map[String, Json] = Map([])
  match self {
    ResourceText(uri~, text~, mime_type~, meta~) => {
      fields["uri"] = Json::string(uri)
      fields["text"] = Json::string(text)
      fields.set_opt("mimeType", mime_type.map(Json::string))
      fields.set_opt("_meta", meta.map(fn(m) { m.copy() }))
    }
    ResourceBlob(uri~, blob~, mime_type~, meta~) => {
      fields["uri"] = Json::string(uri)
      fields["blob"] = Json::string(blob)
      fields.set_opt("mimeType", mime_type.map(Json::string))
      fields.set_opt("_meta", meta.map(fn(m) { m.copy() }))
    }
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for ResourceContent with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ResourceContent raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let uri = match fields.get("uri") {
    Some(String(u)) => u
    Some(_) => raise JsonDecodeError((path.add_key("uri"), "expected string"))
    None => raise JsonDecodeError((path.add_key("uri"), "uri is required"))
  }
  let mime_type = match fields.get("mimeType") {
    Some(String(m)) => Some(m)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("mimeType"), "expected string"))
  }
  let meta = fields.get("_meta")
  match (fields.get("text"), fields.get("blob")) {
    (Some(_), Some(_)) =>
      raise JsonDecodeError((path, "cannot contain both text and blob"))
    (Some(String(text)), None) =>
      ResourceContent::text(uri~, text~, mime_type?, meta?)
    (None, Some(String(blob))) =>
      ResourceContent::blob(uri~, blob~, mime_type?, meta?)
    (Some(_), None) | (None, Some(_)) =>
      raise JsonDecodeError((path, "text/blob must be a string"))
    (None, None) =>
      raise JsonDecodeError((path, "requires text or blob content"))
  }
}

///|
pub fn ResourceContent::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ResourceContent raise McpError {
  decode_json(value, path?)
}

///|
/// Construct text resource contents.
pub fn ResourceContent::text(
  uri~ : String,
  text~ : String,
  mime_type? : String,
  meta? : Json,
) -> ResourceContent {
  ResourceText(uri~, text~, mime_type~, meta~)
}

///|
/// Construct blob resource contents from base64-encoded data.
pub fn ResourceContent::blob(
  uri~ : String,
  blob~ : String,
  mime_type? : String,
  meta? : Json,
) -> ResourceContent {
  ResourceBlob(uri~, blob~, mime_type~, meta~)
}

///|
pub struct ReadResourceResult {
  contents : Array[ResourceContent]
  cache_policy : CachePolicy?
  meta : ResultMeta?
} derive(Debug, Eq)

///|
/// Construct a resource read result with typed contents and caching advice.
pub fn ReadResourceResult::ReadResourceResult(
  contents~ : Array[ResourceContent],
  cache_policy? : CachePolicy,
  meta? : ResultMeta,
) -> ReadResourceResult {
  {
    contents: contents.copy(),
    cache_policy,
    meta: meta.map(fn(m) { m.copy() }),
  }
}

///|
pub impl ToJson for ReadResourceResult with fn to_json(
  self : ReadResourceResult,
) -> Json {
  let fields : Map[String, Json] = {
    "contents": self.contents
    .map(fn(content) { ToJson::to_json(content) })
    .to_json(),
  }
  if self.cache_policy is Some(policy) {
    policy.put(fields)
  }
  if self.meta is Some(meta) {
    fields["_meta"] = ToJson::to_json(meta)
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for ReadResourceResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ReadResourceResult raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let contents : Array[ResourceContent] = match fields.get("contents") {
    Some(Array(arr)) => {
      let result : Array[ResourceContent] = []
      for i, it in arr {
        result.push(
          @json.from_json(it) catch {
            JsonDecodeError((_, msg)) =>
              raise JsonDecodeError(
                (path.add_key("contents").add_index(i), msg),
              )
          },
        )
      }
      result
    }
    Some(_) =>
      raise JsonDecodeError((path.add_key("contents"), "expected array"))
    None =>
      raise JsonDecodeError((path.add_key("contents"), "contents is required"))
  }
  let cache_policy : CachePolicy? = if fields.contains("ttlMs") {
    Some(
      @json.from_json(value) catch {
        JsonDecodeError((_, msg)) => raise JsonDecodeError((path, msg))
      },
    )
  } else {
    None
  }
  let meta : ResultMeta? = match fields.get("_meta") {
    Some(v) => Some(@json.from_json(v, path=path.add_key("_meta")))
    None => None
  }
  ReadResourceResult(contents~, cache_policy?, meta?)
}

///|
pub fn ReadResourceResult::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ReadResourceResult raise McpError {
  decode_json(value, path?)
}

///|
/// Construct a single text resource read result.
pub fn ReadResourceResult::text(
  uri~ : String,
  text~ : String,
  mime_type? : String,
) -> ReadResourceResult {
  ReadResourceResult(contents=[ResourceContent::text(uri~, text~, mime_type?)])
}

///|
/// Canonical decoded result of `resources/list`.
pub struct ListResourcesResult {
  resources : Array[Resource]
  next_cursor : String?
  cache_policy : CachePolicy
  meta : ResultMeta?
} derive(Debug, Eq)

///|
pub impl ToJson for ListResourcesResult with fn to_json(
  self : ListResourcesResult,
) -> Json {
  let fields : Map[String, Json] = {
    "resultType": ToJson::to_json(ResultType::Complete),
    "resources": self.resources.map(fn(r) { ToJson::to_json(r) }).to_json(),
  }
  fields.set_opt("nextCursor", self.next_cursor.map(Json::string))
  self.cache_policy.put(fields)
  if self.meta is Some(meta) {
    fields["_meta"] = ToJson::to_json(meta)
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for ListResourcesResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ListResourcesResult raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let resources : Array[Resource] = match fields.get("resources") {
    Some(Array(arr)) => {
      let result : Array[Resource] = []
      for i, it in arr {
        result.push(
          @json.from_json(it, path=path.add_key("resources").add_index(i)),
        )
      }
      result
    }
    Some(_) =>
      raise JsonDecodeError((path.add_key("resources"), "expected array"))
    None =>
      raise JsonDecodeError(
        (path.add_key("resources"), "resources is required"),
      )
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
  { resources, next_cursor, cache_policy, meta }
}

///|
pub fn ListResourcesResult::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ListResourcesResult raise McpError {
  decode_json(value, path?)
}

///|
/// Canonical decoded result of `resources/templates/list`.
pub struct ListResourceTemplatesResult {
  resource_templates : Array[ResourceTemplate]
  next_cursor : String?
  cache_policy : CachePolicy
  meta : ResultMeta?
} derive(Debug, Eq)

///|
pub impl ToJson for ListResourceTemplatesResult with fn to_json(
  self : ListResourceTemplatesResult,
) -> Json {
  let fields : Map[String, Json] = {
    "resultType": ToJson::to_json(ResultType::Complete),
    "resourceTemplates": self.resource_templates
    .map(fn(t) { ToJson::to_json(t) })
    .to_json(),
  }
  fields.set_opt("nextCursor", self.next_cursor.map(Json::string))
  self.cache_policy.put(fields)
  if self.meta is Some(meta) {
    fields["_meta"] = ToJson::to_json(meta)
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for ListResourceTemplatesResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ListResourceTemplatesResult raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let resource_templates : Array[ResourceTemplate] = match
    fields.get("resourceTemplates") {
    Some(Array(arr)) => {
      let result : Array[ResourceTemplate] = []
      for i, it in arr {
        result.push(
          @json.from_json(
            it,
            path=path.add_key("resourceTemplates").add_index(i),
          ),
        )
      }
      result
    }
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("resourceTemplates"), "expected array"),
      )
    None =>
      raise JsonDecodeError(
        (path.add_key("resourceTemplates"), "resourceTemplates is required"),
      )
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
  { resource_templates, next_cursor, cache_policy, meta }
}

///|
pub fn ListResourceTemplatesResult::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ListResourceTemplatesResult raise McpError {
  decode_json(value, path?)
}
