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
pub(all) struct Annotations {
  audience : Array[Role]
  priority : Double?
  last_modified : String?
} derive(Debug, Eq)

///|
pub fn Annotations::Annotations(
  audience? : Array[Role] = [],
  priority? : Double,
  last_modified? : String,
) -> Annotations {
  { audience, priority, last_modified }
}

///|
pub impl ToJson for Annotations with fn to_json(self : Annotations) -> Json {
  let fields : Map[String, Json] = {}
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
pub(all) struct ResourceLink {
  uri : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  icons : Array[Icon]
  annotations : Annotations?
  size : Int?
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
  size? : Int,
  meta? : Json,
) -> ResourceLink {
  { uri, name, title, description, mime_type, icons, annotations, size, meta }
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
  put_optional_int(fields, "size", self.size)
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
pub(all) enum ContentBlock {
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
  Raw(Json)
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
pub impl ToJson for ContentBlock with fn to_json(self : ContentBlock) -> Json {
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
    Raw(raw) => raw
  }
}

///|
pub fn ContentBlock::text(
  text : String,
  annotations? : Annotations,
  meta? : Json,
) -> ContentBlock {
  TextContent(text~, annotations~, meta~)
}

///|
pub fn ContentBlock::image(
  data~ : String,
  mime_type~ : String,
  annotations? : Annotations,
  meta? : Json,
) -> ContentBlock {
  ImageContent(data~, mime_type~, annotations~, meta~)
}

///|
pub fn ContentBlock::audio(
  data~ : String,
  mime_type~ : String,
  annotations? : Annotations,
  meta? : Json,
) -> ContentBlock {
  AudioContent(data~, mime_type~, annotations~, meta~)
}

///|
pub fn ContentBlock::embedded_resource(
  resource~ : ResourceContent,
  annotations? : Annotations,
  meta? : Json,
) -> ContentBlock {
  EmbeddedResource(resource~, annotations~, meta~)
}

///|
pub fn ContentBlock::resource_link(
  resource_link : ResourceLink,
) -> ContentBlock {
  ResourceLink(resource_link)
}

///|
pub fn ContentBlock::raw(raw : Json) -> ContentBlock {
  Raw(raw)
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
/// Return a plain text tool result.
pub fn CallToolResult::text(
  text : String,
  annotations? : Annotations,
  meta? : Json,
) -> CallToolResult {
  {
    content: [ContentBlock::text(text, annotations?, meta?)],
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
pub fn CallToolResult::text_json(
  text : String,
  value : Json,
  annotations? : Annotations,
  meta? : Json,
) -> CallToolResult {
  {
    content: [ContentBlock::text(text, annotations?, meta?)],
    structured_content: Some(value),
    is_error: false,
    meta: None,
  }
}

///|
/// Return a tool error as MCP content, not as a JSON-RPC protocol error.
pub fn CallToolResult::error_text(
  text : String,
  annotations? : Annotations,
  meta? : Json,
) -> CallToolResult {
  {
    content: [ContentBlock::text(text, annotations?, meta?)],
    structured_content: None,
    is_error: true,
    meta: None,
  }
}
