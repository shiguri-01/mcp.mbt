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
  meta : Json?
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
) -> Resource raise McpError {
  Resource::Resource(
    uri~,
    name~,
    title?,
    description?,
    mime_type~,
    annotations?,
    size?,
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
  meta? : Json,
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
pub impl ToJson for Resource with fn to_json(self : Resource) -> Json {
  let fields : Map[String, Json] = {
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
  Resource(
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
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub fn Resource::from_json(
  value : Json,
  context? : String = "resource",
) -> Resource raise McpError {
  decode_json(value, context~)
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
  meta : Json?
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
  meta? : Json,
) -> ResourceTemplate {
  {
    uri_template,
    name,
    title,
    description,
    mime_type,
    icons: icons.map(icon => icon.copy()),
    annotations: copy_optional_annotations(annotations),
    meta: copy_optional_json(meta),
  }
}

///|
pub impl ToJson for ResourceTemplate with fn to_json(self : ResourceTemplate) -> Json {
  let fields : Map[String, Json] = {
    "uriTemplate": Json::string(self.uri_template),
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
  put_optional_json(fields, "_meta", self.meta)
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
  let annotations : Annotations? = match fields {
    { "annotations": v, .. } =>
      Some(@json.from_json(v, path=path.add_key("annotations")))
    _ => None
  }
  let meta = fields.get("_meta")
  ResourceTemplate(
    uri_template~,
    name~,
    title?,
    description?,
    mime_type?,
    icons~,
    annotations?,
    meta?,
  )
}

///|
pub fn ResourceTemplate::from_json(
  value : Json,
  context? : String = "resource template",
) -> ResourceTemplate raise McpError {
  decode_json(value, context~)
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
      put_optional_string(fields, "mimeType", mime_type)
      put_optional_json(fields, "_meta", meta)
    }
    ResourceBlob(uri~, blob~, mime_type~, meta~) => {
      fields["uri"] = Json::string(uri)
      fields["blob"] = Json::string(blob)
      put_optional_string(fields, "mimeType", mime_type)
      put_optional_json(fields, "_meta", meta)
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
    (Some(String(text)), None) =>
      ResourceContent::text(uri~, text~, mime_type?, meta?)
    (None, Some(String(blob))) =>
      ResourceContent::blob(uri~, blob~, mime_type?, meta?)
    (Some(_), Some(_)) =>
      raise JsonDecodeError((path, "cannot contain both text and blob"))
    (None, None) =>
      raise JsonDecodeError((path, "requires text or blob content"))
    _ => raise JsonDecodeError((path, "text/blob must be a string"))
  }
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
    meta: copy_optional_result_meta(meta),
  }
}

///|
pub impl ToJson for ReadResourceResult with fn to_json(
  self : ReadResourceResult,
) -> Json {
  let fields : Map[String, Json] = {
    "contents": self.contents.map(fn(content) { content.to_json() }).to_json(),
  }
  if self.cache_policy is Some(policy) {
    policy.put(fields)
  }
  if self.meta is Some(meta) {
    fields["_meta"] = meta.to_json()
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
  let contents_val = match fields.get("contents") {
    Some(Array(arr)) => arr
    Some(_) =>
      raise JsonDecodeError((path.add_key("contents"), "expected array"))
    None =>
      raise JsonDecodeError((path.add_key("contents"), "contents is required"))
  }
  let contents : Array[ResourceContent] = []
  for i, it in contents_val {
    contents.push(
      @json.from_json(it) catch {
        JsonDecodeError((_, msg)) =>
          raise JsonDecodeError((path.add_key("contents").add_index(i), msg))
      },
    )
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
  let meta : ResultMeta? = match fields {
    { "_meta": v, .. } => Some(@json.from_json(v, path=path.add_key("_meta")))
    _ => None
  }
  { contents, cache_policy, meta }
}

///|
pub fn ReadResourceResult::from_json(
  value : Json,
) -> ReadResourceResult raise McpError {
  decode_json(value, context="resources/read result")
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
    "resultType": ResultType::Complete.to_json(),
    "resources": self.resources.map(fn(r) { r.to_json() }).to_json(),
  }
  put_optional_string(fields, "nextCursor", self.next_cursor)
  self.cache_policy.put(fields)
  if self.meta is Some(meta) {
    fields["_meta"] = meta.to_json()
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
  let res_val = match fields.get("resources") {
    Some(Array(arr)) => arr
    Some(_) =>
      raise JsonDecodeError((path.add_key("resources"), "expected array"))
    None =>
      raise JsonDecodeError(
        (path.add_key("resources"), "resources is required"),
      )
  }
  let resources : Array[Resource] = []
  for i, it in res_val {
    resources.push(
      @json.from_json(it, path=path.add_key("resources").add_index(i)),
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
  let meta : ResultMeta? = match fields {
    { "_meta": v, .. } => Some(@json.from_json(v, path=path.add_key("_meta")))
    _ => None
  }
  { resources, next_cursor, cache_policy, meta }
}

///|
pub fn ListResourcesResult::from_json(
  value : Json,
) -> ListResourcesResult raise McpError {
  decode_json(value, context="resources/list result")
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
    "resultType": ResultType::Complete.to_json(),
    "resourceTemplates": self.resource_templates
    .map(fn(t) { t.to_json() })
    .to_json(),
  }
  put_optional_string(fields, "nextCursor", self.next_cursor)
  self.cache_policy.put(fields)
  if self.meta is Some(meta) {
    fields["_meta"] = meta.to_json()
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
  let t_val = match fields.get("resourceTemplates") {
    Some(Array(arr)) => arr
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("resourceTemplates"), "expected array"),
      )
    None =>
      raise JsonDecodeError(
        (path.add_key("resourceTemplates"), "resourceTemplates is required"),
      )
  }
  let resource_templates : Array[ResourceTemplate] = []
  for i, it in t_val {
    resource_templates.push(
      @json.from_json(it, path=path.add_key("resourceTemplates").add_index(i)),
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
  let meta : ResultMeta? = match fields {
    { "_meta": v, .. } => Some(@json.from_json(v, path=path.add_key("_meta")))
    _ => None
  }
  { resource_templates, next_cursor, cache_policy, meta }
}

///|
pub fn ListResourceTemplatesResult::from_json(
  value : Json,
) -> ListResourceTemplatesResult raise McpError {
  decode_json(value, context="resources/templates/list result")
}
