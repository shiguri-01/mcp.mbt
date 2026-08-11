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
  { src, mime_type, sizes: sizes.copy(), theme }
}

///|
fn Icon::copy(self : Icon) -> Icon {
  { ..self, sizes: self.sizes.copy() }
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
pub impl @json.FromJson for Icon with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> Icon raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected an icon object"))
  }
  let src : String = match fields.get("src") {
    Some(value) => @json.from_json(value, path=path.add_key("src"))
    None => raise JsonDecodeError((path, "missing required field 'src'"))
  }
  let mime_type : String? = match fields.get("mimeType") {
    Some(value) => Some(@json.from_json(value, path=path.add_key("mimeType")))
    None => None
  }
  let sizes : Array[String] = match fields.get("sizes") {
    Some(value) => @json.from_json(value, path=path.add_key("sizes"))
    None => []
  }
  let theme : IconTheme? = match fields.get("theme") {
    Some(String("light")) => Some(Light)
    Some(String("dark")) => Some(Dark)
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("theme"), "expected 'light' or 'dark'"),
      )
    None => None
  }
  Icon(src~, mime_type?, sizes~, theme?)
}

///|
/// MCP implementation metadata repeated in each stateless request or result.
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
  {
    name,
    title,
    version,
    description,
    icons: icons.map(icon => icon.copy()),
    website_url,
  }
}

///|
fn Implementation::copy(self : Implementation) -> Implementation {
  { ..self, icons: self.icons.map(icon => icon.copy()) }
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

///|
pub impl @json.FromJson for Implementation with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> Implementation raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected an implementation object"))
  }
  let required_string = fn(key : String) -> String raise @json.JsonDecodeError {
    match fields.get(key) {
      Some(value) => @json.from_json(value, path=path.add_key(key))
      None => raise JsonDecodeError((path, "missing required field '\{key}'"))
    }
  }
  let optional_string = fn(
    key : String,
  ) -> String? raise @json.JsonDecodeError {
    match fields.get(key) {
      Some(value) => Some(@json.from_json(value, path=path.add_key(key)))
      None => None
    }
  }
  let icons : Array[Icon] = match fields.get("icons") {
    Some(value) => @json.from_json(value, path=path.add_key("icons"))
    None => []
  }
  Implementation(
    name=required_string("name"),
    version=required_string("version"),
    title?=optional_string("title"),
    description?=optional_string("description"),
    icons~,
    website_url?=optional_string("websiteUrl"),
  )
}
