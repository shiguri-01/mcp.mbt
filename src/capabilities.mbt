///|
/// Roots capability declared by an MCP client.
pub struct RootsCapability {
  list_changed : Bool?
} derive(Debug, Eq)

///|
pub fn RootsCapability::RootsCapability(
  list_changed? : Bool,
) -> RootsCapability {
  { list_changed, }
}

///|
pub impl ToJson for RootsCapability with fn to_json(self : RootsCapability) -> Json {
  let fields : Map[String, Json] = Map([])
  fields.set_opt("listChanged", self.list_changed.map(Json::boolean))
  Json::object(fields)
}

///|
pub impl @json.FromJson for RootsCapability with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> RootsCapability raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let list_changed = match fields.get("listChanged") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("listChanged"), "expected boolean"))
  }
  RootsCapability(list_changed?)
}

///|
pub fn RootsCapability::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> RootsCapability raise McpError {
  decode_json(value, path?)
}

///|
/// Sampling capability declared by an MCP client.
pub struct SamplingCapability {} derive(Debug, Eq)

///|
pub fn SamplingCapability::SamplingCapability() -> SamplingCapability {
  SamplingCapability::{  }
}

///|
pub impl ToJson for SamplingCapability with fn to_json(
  self : SamplingCapability,
) -> Json {
  ignore(self)
  Json::object(Map([]))
}

///|
pub impl @json.FromJson for SamplingCapability with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> SamplingCapability raise {
  guard value is Object(_) else {
    raise JsonDecodeError((path, "expected object"))
  }
  SamplingCapability()
}

///|
pub fn SamplingCapability::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> SamplingCapability raise McpError {
  decode_json(value, path?)
}

///|
/// Client support for server-initiated elicitation.
pub struct ElicitationCapability {
  form : Json?
  url : Json?
} derive(Debug, Eq)

///|
pub fn ElicitationCapability::ElicitationCapability(
  form? : Json,
  url? : Json,
) -> ElicitationCapability {
  { form: form.map(fn(f) { f.copy() }), url: url.map(fn(u) { u.copy() }) }
}

///|
fn ElicitationCapability::copy(
  self : ElicitationCapability,
) -> ElicitationCapability {
  ElicitationCapability(form?=self.form, url?=self.url)
}

///|
pub impl ToJson for ElicitationCapability with fn to_json(
  self : ElicitationCapability,
) -> Json {
  let fields : Map[String, Json] = Map([])
  fields.set_opt("form", self.form.map(fn(f) { f.copy() }))
  fields.set_opt("url", self.url.map(fn(u) { u.copy() }))
  Json::object(fields)
}

///|
pub impl @json.FromJson for ElicitationCapability with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ElicitationCapability raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let form = match fields.get("form") {
    Some(Object(_) as v) => Some(v)
    Some(Null) | None => None
    Some(_) => raise JsonDecodeError((path.add_key("form"), "expected object"))
  }
  let url = match fields.get("url") {
    Some(Object(_) as v) => Some(v)
    Some(Null) | None => None
    Some(_) => raise JsonDecodeError((path.add_key("url"), "expected object"))
  }
  ElicitationCapability(form?, url?)
}

///|
pub fn ElicitationCapability::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ElicitationCapability raise McpError {
  decode_json(value, path?)
}

///|
/// Capabilities declared by an MCP client.
pub struct ClientCapabilities {
  roots : RootsCapability?
  sampling : SamplingCapability?
  elicitation : ElicitationCapability?
  extensions : Map[String, Json]
  experimental : Map[String, Json]
  extra : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn ClientCapabilities::ClientCapabilities(
  roots? : RootsCapability,
  sampling? : SamplingCapability,
  elicitation? : ElicitationCapability,
  extensions? : Map[String, Json] = {},
  experimental? : Map[String, Json] = {},
  extra? : Map[String, Json] = {},
) -> ClientCapabilities {
  {
    roots,
    sampling,
    elicitation,
    extensions: extensions.copy_json(),
    experimental: experimental.copy_json(),
    extra: extra.copy_json(),
  }
}

///|
pub fn ClientCapabilities::copy(
  self : ClientCapabilities,
) -> ClientCapabilities {
  ClientCapabilities(
    roots?=self.roots,
    sampling?=self.sampling,
    elicitation?=self.elicitation.map(value => value.copy()),
    extensions=self.extensions,
    experimental=self.experimental,
    extra=self.extra,
  )
}

///|
pub fn ClientCapabilities::empty() -> ClientCapabilities {
  ClientCapabilities()
}

///|
fn valid_extension_identifier(identifier : String) -> Bool {
  let length = identifier.length()
  if length < 3 || length > 255 {
    return false
  }
  let mut slash_index = -1
  for index in 0..<length {
    let char = identifier[index]
    if char == '/' {
      if slash_index != -1 {
        return false
      }
      slash_index = index
    }
  }
  if slash_index <= 0 || slash_index == length - 1 {
    return false
  }
  let vendor = identifier[0:slash_index].to_owned()
  let name = identifier[slash_index + 1:].to_owned()
  valid_identifier_segment(vendor) && valid_identifier_segment(name)
}

///|
fn valid_identifier_segment(segment : String) -> Bool {
  let length = segment.length()
  if length == 0 {
    return false
  }
  for index in 0..<length {
    let char = segment[index]
    let is_valid = (char >= 'a' && char <= 'z') ||
      (char >= '0' && char <= '9') ||
      char == '-' ||
      char == '.'
    if !is_valid {
      return false
    }
  }
  true
}

///|
fn validate_extension_keys(
  values : Map[String, Json],
  path? : @json.JsonPath,
) -> Unit raise McpError {
  for key, _ in values {
    if !valid_extension_identifier(key) {
      let p = match path {
        Some(path) => path.add_key(key).to_string()
        None => "extension '\{key}'"
      }
      raise InvalidParams("\{p}: not a valid extension identifier")
    }
  }
}

///|
fn validate_experimental_keys(
  values : Map[String, Json],
  path? : @json.JsonPath,
) -> Unit raise McpError {
  for key, _ in values {
    if valid_extension_identifier(key) {
      let p = match path {
        Some(path) => path.add_key(key).to_string()
        None => "experimental '\{key}'"
      }
      raise InvalidParams("\{p}: must not use namespaced extension syntax")
    }
    if !valid_identifier_segment(key) {
      let p = match path {
        Some(path) => path.add_key(key).to_string()
        None => "experimental '\{key}'"
      }
      raise InvalidParams("\{p}: not a valid experimental feature name")
    }
  }
}

///|
fn put_capability_map(
  fields : Map[String, Json],
  key : String,
  values : Map[String, Json],
) -> Unit {
  if !values.is_empty() {
    fields[key] = Json::object(values.copy_json())
  }
}

///|
pub impl ToJson for ClientCapabilities with fn to_json(
  self : ClientCapabilities,
) -> Json {
  let fields = self.extra.copy_json()
  for key in ["roots", "sampling", "elicitation", "extensions", "experimental"] {
    fields.remove(key)
  }
  if self.roots is Some(value) {
    fields["roots"] = value.to_json()
  }
  if self.sampling is Some(value) {
    fields["sampling"] = value.to_json()
  }
  if self.elicitation is Some(value) {
    fields["elicitation"] = value.to_json()
  }
  put_capability_map(fields, "extensions", self.extensions)
  put_capability_map(fields, "experimental", self.experimental)
  Json::object(fields)
}

///|
fn decode_capability_map(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> Map[String, Json] raise @json.JsonDecodeError {
  let subpath = path.add_key(key)
  match fields.get(key) {
    Some(Object(values)) => {
      if key == "extensions" {
        validate_extension_keys(values, path=subpath) catch {
          error => raise @json.JsonDecodeError((subpath, error.message()))
        }
      } else if key == "experimental" {
        validate_experimental_keys(values, path=subpath) catch {
          error => raise @json.JsonDecodeError((subpath, error.message()))
        }
      }
      values.copy_json()
    }
    Some(Null) | None => Map([])
    Some(_) => raise @json.JsonDecodeError((subpath, "expected object"))
  }
}

///|
pub impl @json.FromJson for ClientCapabilities with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ClientCapabilities raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let extra : Map[String, Json] = Map([])
  for key, val in fields {
    match key {
      "roots" | "sampling" | "elicitation" | "extensions" | "experimental" => ()
      _ => extra[key] = val
    }
  }
  let roots : RootsCapability? = match fields {
    { "roots": v, .. } => Some(@json.from_json(v, path=path.add_key("roots")))
    _ => None
  }
  let sampling : SamplingCapability? = match fields {
    { "sampling": v, .. } =>
      Some(@json.from_json(v, path=path.add_key("sampling")))
    _ => None
  }
  let elicitation : ElicitationCapability? = match fields {
    { "elicitation": v, .. } =>
      Some(@json.from_json(v, path=path.add_key("elicitation")))
    _ => None
  }
  let extensions = decode_capability_map(fields, "extensions", path)
  let experimental = decode_capability_map(fields, "experimental", path)
  ClientCapabilities(
    roots?,
    sampling?,
    elicitation?,
    extensions~,
    experimental~,
    extra~,
  )
}

///|
pub fn ClientCapabilities::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ClientCapabilities raise McpError {
  decode_json(value, path?)
}

///|
/// Tools capability declared by an MCP server.
pub struct ToolsCapability {
  list_changed : Bool?
} derive(Debug, Eq)

///|
pub fn ToolsCapability::ToolsCapability(
  list_changed? : Bool,
) -> ToolsCapability {
  { list_changed, }
}

///|
pub impl ToJson for ToolsCapability with fn to_json(self : ToolsCapability) -> Json {
  let fields : Map[String, Json] = Map([])
  fields.set_opt("listChanged", self.list_changed.map(Json::boolean))
  Json::object(fields)
}

///|
pub impl @json.FromJson for ToolsCapability with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ToolsCapability raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let list_changed = match fields.get("listChanged") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("listChanged"), "expected boolean"))
  }
  ToolsCapability(list_changed?)
}

///|
pub fn ToolsCapability::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ToolsCapability raise McpError {
  decode_json(value, path?)
}

///|
/// Prompts capability declared by an MCP server.
pub struct PromptsCapability {
  list_changed : Bool?
} derive(Debug, Eq)

///|
pub fn PromptsCapability::PromptsCapability(
  list_changed? : Bool,
) -> PromptsCapability {
  { list_changed, }
}

///|
pub impl ToJson for PromptsCapability with fn to_json(self : PromptsCapability) -> Json {
  let fields : Map[String, Json] = Map([])
  fields.set_opt("listChanged", self.list_changed.map(Json::boolean))
  Json::object(fields)
}

///|
pub impl @json.FromJson for PromptsCapability with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> PromptsCapability raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let list_changed = match fields.get("listChanged") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("listChanged"), "expected boolean"))
  }
  PromptsCapability(list_changed?)
}

///|
pub fn PromptsCapability::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> PromptsCapability raise McpError {
  decode_json(value, path?)
}

///|
/// Resources capability declared by an MCP server.
pub struct ResourcesCapability {
  subscribe : Bool?
  list_changed : Bool?
} derive(Debug, Eq)

///|
pub fn ResourcesCapability::ResourcesCapability(
  subscribe? : Bool,
  list_changed? : Bool,
) -> ResourcesCapability {
  { subscribe, list_changed }
}

///|
pub impl ToJson for ResourcesCapability with fn to_json(
  self : ResourcesCapability,
) -> Json {
  let fields : Map[String, Json] = Map([])
  fields.set_opt("subscribe", self.subscribe.map(Json::boolean))
  fields.set_opt("listChanged", self.list_changed.map(Json::boolean))
  Json::object(fields)
}

///|
pub impl @json.FromJson for ResourcesCapability with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ResourcesCapability raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let subscribe = match fields.get("subscribe") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("subscribe"), "expected boolean"))
  }
  let list_changed = match fields.get("listChanged") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("listChanged"), "expected boolean"))
  }
  ResourcesCapability(subscribe?, list_changed?)
}

///|
pub fn ResourcesCapability::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ResourcesCapability raise McpError {
  decode_json(value, path?)
}

///|
/// Logging capability declared by an MCP server.
pub struct LoggingCapability {} derive(Debug, Eq)

///|
pub fn LoggingCapability::LoggingCapability() -> LoggingCapability {
  LoggingCapability::{  }
}

///|
pub impl ToJson for LoggingCapability with fn to_json(self : LoggingCapability) -> Json {
  ignore(self)
  Json::object(Map([]))
}

///|
pub impl @json.FromJson for LoggingCapability with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> LoggingCapability raise {
  guard value is Object(_) else {
    raise JsonDecodeError((path, "expected object"))
  }
  LoggingCapability()
}

///|
pub fn LoggingCapability::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> LoggingCapability raise McpError {
  decode_json(value, path?)
}

///|
/// Capabilities declared by an MCP server.
pub struct ServerCapabilities {
  tools : ToolsCapability?
  resources : ResourcesCapability?
  prompts : PromptsCapability?
  logging : LoggingCapability?
  completions : Bool
  extensions : Map[String, Json]
  experimental : Map[String, Json]
  extra : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn ServerCapabilities::ServerCapabilities(
  tools? : ToolsCapability,
  resources? : ResourcesCapability,
  prompts? : PromptsCapability,
  logging? : LoggingCapability,
  completions? : Bool = false,
  extensions? : Map[String, Json] = {},
  experimental? : Map[String, Json] = {},
  extra? : Map[String, Json] = {},
) -> ServerCapabilities {
  {
    tools,
    resources,
    prompts,
    logging,
    completions,
    extensions: extensions.copy_json(),
    experimental: experimental.copy_json(),
    extra: extra.copy_json(),
  }
}

///|
fn ServerCapabilities::copy(self : ServerCapabilities) -> ServerCapabilities {
  ServerCapabilities(
    tools?=self.tools,
    resources?=self.resources,
    prompts?=self.prompts,
    logging?=self.logging,
    completions=self.completions,
    extensions=self.extensions,
    experimental=self.experimental,
    extra=self.extra,
  )
}

///|
pub fn ServerCapabilities::empty() -> ServerCapabilities {
  ServerCapabilities()
}

///|
pub impl ToJson for ServerCapabilities with fn to_json(
  self : ServerCapabilities,
) -> Json {
  let fields = self.extra.copy_json()
  for
    key in [
      "tools", "resources", "prompts", "logging", "completions", "extensions", "experimental",
    ] {
    fields.remove(key)
  }
  if self.tools is Some(value) {
    fields["tools"] = value.to_json()
  }
  if self.resources is Some(value) {
    fields["resources"] = value.to_json()
  }
  if self.prompts is Some(value) {
    fields["prompts"] = value.to_json()
  }
  if self.logging is Some(value) {
    fields["logging"] = value.to_json()
  }
  if self.completions {
    fields["completions"] = Json::object({})
  }
  put_capability_map(fields, "extensions", self.extensions)
  put_capability_map(fields, "experimental", self.experimental)
  Json::object(fields)
}

///|
pub impl @json.FromJson for ServerCapabilities with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ServerCapabilities raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let extra : Map[String, Json] = Map([])
  for key, item in fields {
    match key {
      "tools"
      | "resources"
      | "prompts"
      | "logging"
      | "completions"
      | "extensions"
      | "experimental" => ()
      _ => extra[key] = item
    }
  }
  let tools : ToolsCapability? = match fields {
    { "tools": v, .. } => Some(@json.from_json(v, path=path.add_key("tools")))
    _ => None
  }
  let resources : ResourcesCapability? = match fields {
    { "resources": v, .. } =>
      Some(@json.from_json(v, path=path.add_key("resources")))
    _ => None
  }
  let prompts : PromptsCapability? = match fields {
    { "prompts": v, .. } =>
      Some(@json.from_json(v, path=path.add_key("prompts")))
    _ => None
  }
  let logging : LoggingCapability? = match fields {
    { "logging": v, .. } =>
      Some(@json.from_json(v, path=path.add_key("logging")))
    _ => None
  }
  let completions = match fields.get("completions") {
    Some(Object(_)) => true
    Some(_) =>
      raise JsonDecodeError((path.add_key("completions"), "expected object"))
    None => false
  }
  let extensions = decode_capability_map(fields, "extensions", path)
  let experimental = decode_capability_map(fields, "experimental", path)
  ServerCapabilities(
    tools?,
    resources?,
    prompts?,
    logging?,
    completions~,
    extensions~,
    experimental~,
    extra~,
  )
}

///|
pub fn ServerCapabilities::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ServerCapabilities raise McpError {
  decode_json(value, path?)
}
