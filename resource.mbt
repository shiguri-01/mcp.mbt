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
/// Convenience descriptor for a text-oriented resource.
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
/// Construct a single text resource read result.
pub fn ReadResourceResult::text(
  uri~ : String,
  text~ : String,
  mime_type? : String,
) -> ReadResourceResult {
  { contents: [ResourceText(uri~, text~, mime_type~)], meta: None }
}
