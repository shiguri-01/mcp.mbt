///|
/// A resource descriptor advertised by `resources/list`.
///
/// `size`, when known, is the raw resource byte length before base64 encoding
/// or tokenization.
pub(all) struct Resource {
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
) -> Resource {
  { uri, name, title, description, mime_type, icons, annotations, size, meta }
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
/// Convenience descriptor for a text-oriented resource.
pub fn Resource::text(
  uri~ : String,
  name~ : String,
  title? : String,
  description? : String,
  mime_type? : String = "text/plain",
  annotations? : Annotations,
  size? : Int64,
) -> Resource {
  {
    uri,
    name,
    title,
    description,
    mime_type: Some(mime_type),
    icons: [],
    annotations,
    size,
    meta: None,
  }
}

///|
pub(all) struct ResourceTemplate {
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
    icons,
    annotations,
    meta,
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
  let fields : Map[String, Json] = {}
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
/// Construct a single text resource read result.
pub fn ReadResourceResult::text(
  uri~ : String,
  text~ : String,
  mime_type? : String,
) -> ReadResourceResult {
  { contents: [ResourceContent::text(uri~, text~, mime_type?)], meta: None }
}
