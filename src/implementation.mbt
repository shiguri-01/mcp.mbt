///|
pub(all) enum IconTheme {
  Light
  Dark
} derive(Debug, Eq)

///|
pub fn IconTheme::to_string(self : IconTheme) -> String {
  match self {
    Light => "light"
    Dark => "dark"
  }
}

///|
pub impl ToJson for IconTheme with fn to_json(self : IconTheme) -> Json {
  Json::string(self.to_string())
}

///|
/// Icon metadata for an MCP implementation.
pub(all) struct Icon {
  src : String
  mime_type : String?
  sizes : Array[String]
  theme : IconTheme?
} derive(Debug, Eq)

///|
pub fn Icon::Icon(
  src~ : String,
  mime_type? : String,
  sizes? : Array[String] = [],
  theme? : IconTheme,
) -> Icon {
  { src, mime_type, sizes, theme }
}

///|
pub impl ToJson for Icon with fn to_json(self : Icon) -> Json {
  let fields : Map[String, Json] = { "src": Json::string(self.src) }
  put_optional_string(fields, "mimeType", self.mime_type)
  if !self.sizes.is_empty() {
    fields["sizes"] = self.sizes.to_json()
  }
  if self.theme is Some(theme) {
    fields["theme"] = theme.to_json()
  }
  Json::object(fields)
}

///|
/// MCP implementation metadata advertised during `initialize`.
pub(all) struct Implementation {
  name : String
  title : String?
  version : String
  description : String?
  icons : Array[Icon]
  website_url : String?
} derive(Debug, Eq)

///|
pub fn Implementation::Implementation(
  name~ : String,
  version~ : String,
  title? : String,
  description? : String,
  icons? : Array[Icon] = [],
  website_url? : String,
) -> Implementation {
  { name, title, version, description, icons, website_url }
}

///|
pub impl ToJson for Implementation with fn to_json(self : Implementation) -> Json {
  let fields : Map[String, Json] = {
    "name": Json::string(self.name),
    "version": Json::string(self.version),
  }
  put_optional_string(fields, "title", self.title)
  put_optional_string(fields, "description", self.description)
  if !self.icons.is_empty() {
    fields["icons"] = self.icons.map(fn(icon) { icon.to_json() }).to_json()
  }
  put_optional_string(fields, "websiteUrl", self.website_url)
  Json::object(fields)
}
