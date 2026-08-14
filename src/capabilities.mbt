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
  put_optional_bool(fields, "listChanged", self.list_changed)
  Json::object(fields)
}

///|
pub fn RootsCapability::from_json(
  value : Json,
  context? : String = "roots capability",
) -> RootsCapability raise McpError {
  let fields = expect_object(value, context)
  RootsCapability(
    list_changed?=get_optional_bool(fields, "listChanged", context),
  )
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
pub fn SamplingCapability::from_json(
  value : Json,
  context? : String = "sampling capability",
) -> SamplingCapability raise McpError {
  ignore(expect_object(value, context))
  SamplingCapability()
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
  { form: copy_optional_json(form), url: copy_optional_json(url) }
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
  put_optional_json(fields, "form", self.form)
  put_optional_json(fields, "url", self.url)
  Json::object(fields)
}

///|
pub fn ElicitationCapability::from_json(
  value : Json,
  context? : String = "elicitation capability",
) -> ElicitationCapability raise McpError {
  let fields = expect_object(value, context)
  ElicitationCapability(
    form?=get_optional_object(fields, "form", context),
    url?=get_optional_object(fields, "url", context),
  )
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
    extensions: copy_json_map(extensions),
    experimental: copy_json_map(experimental),
    extra: copy_json_map(extra),
  }
}

///|
fn ClientCapabilities::copy(self : ClientCapabilities) -> ClientCapabilities {
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
  let segments = identifier.split("/").to_array()
  if segments.length() != 2 || segments[1].is_empty() {
    return false
  }
  let labels = segments[0].split(".").to_array()
  if labels.length() < 2 {
    return false
  }
  valid_meta_key(identifier)
}

///|
fn validate_extension_map(
  extensions : Map[String, Json],
  context : String,
) -> Unit raise McpError {
  for identifier, settings in extensions {
    if !valid_extension_identifier(identifier) {
      raise InvalidParams(
        "\{context} has invalid extension identifier: \{identifier}",
      )
    }
    if !(settings is Object(_)) {
      raise InvalidParams("\{context}.\{identifier} must be an object")
    }
  }
}

///|
fn validate_extension_result_types(
  result_types : Map[String, String],
  extensions : Map[String, Json],
) -> Unit raise McpError {
  for result_type, extension in result_types {
    if result_type.is_empty() ||
      result_type == "complete" ||
      result_type == "input_required" {
      raise InvalidParams("invalid extension result type: \{result_type}")
    }
    if !extensions.contains(extension) {
      raise InvalidParams(
        "result type \{result_type} references unadvertised extension \{extension}",
      )
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
    fields[key] = Json::object(copy_json_map(values))
  }
}

///|
pub impl ToJson for ClientCapabilities with fn to_json(
  self : ClientCapabilities,
) -> Json {
  let fields = copy_json_map(self.extra)
  for key in ["roots", "sampling", "elicitation", "extensions", "experimental"] {
    fields.remove(key)
  }
  if self.roots is Some(roots) {
    fields["roots"] = roots.to_json()
  }
  if self.sampling is Some(sampling) {
    fields["sampling"] = sampling.to_json()
  }
  if self.elicitation is Some(elicitation) {
    fields["elicitation"] = elicitation.to_json()
  }
  put_capability_map(fields, "extensions", self.extensions)
  put_capability_map(fields, "experimental", self.experimental)
  Json::object(fields)
}

///|
fn parse_capability_map(
  fields : Map[String, Json],
  key : String,
  context : String,
) -> Map[String, Json] raise McpError {
  match fields.get(key) {
    None | Some(Null) => Map([])
    Some(Object(values)) => {
      for name, value in values {
        if !(value is Object(_)) {
          raise InvalidParams("\{context}.\{key}.\{name} must be an object")
        }
      }
      if key == "extensions" {
        validate_extension_map(values, "\{context}.extensions")
      }
      values
    }
    Some(_) => raise InvalidParams("\{context}.\{key} must be an object")
  }
}

///|
pub fn ClientCapabilities::from_json(
  value : Json,
  context? : String = "client capabilities",
) -> ClientCapabilities raise McpError {
  let fields = expect_object(value, context)
  let extra : Map[String, Json] = Map([])
  for key, val in fields {
    match key {
      "roots" | "sampling" | "elicitation" | "extensions" | "experimental" => ()
      _ => extra[key] = val
    }
  }
  ClientCapabilities(
    roots?=match fields.get("roots") {
      Some(v) => Some(RootsCapability::from_json(v, context="\{context}.roots"))
      None => None
    },
    sampling?=match fields.get("sampling") {
      Some(v) =>
        Some(SamplingCapability::from_json(v, context="\{context}.sampling"))
      None => None
    },
    elicitation?=match fields.get("elicitation") {
      Some(v) =>
        Some(
          ElicitationCapability::from_json(v, context="\{context}.elicitation"),
        )
      None => None
    },
    extensions=parse_capability_map(fields, "extensions", context),
    experimental=parse_capability_map(fields, "experimental", context),
    extra~,
  )
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
  put_optional_bool(fields, "listChanged", self.list_changed)
  Json::object(fields)
}

///|
pub fn ToolsCapability::from_json(
  value : Json,
  context? : String = "tools capability",
) -> ToolsCapability raise McpError {
  let fields = expect_object(value, context)
  ToolsCapability(
    list_changed?=get_optional_bool(fields, "listChanged", context),
  )
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
  put_optional_bool(fields, "listChanged", self.list_changed)
  Json::object(fields)
}

///|
pub fn PromptsCapability::from_json(
  value : Json,
  context? : String = "prompts capability",
) -> PromptsCapability raise McpError {
  let fields = expect_object(value, context)
  PromptsCapability(
    list_changed?=get_optional_bool(fields, "listChanged", context),
  )
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
  put_optional_bool(fields, "subscribe", self.subscribe)
  put_optional_bool(fields, "listChanged", self.list_changed)
  Json::object(fields)
}

///|
pub fn ResourcesCapability::from_json(
  value : Json,
  context? : String = "resources capability",
) -> ResourcesCapability raise McpError {
  let fields = expect_object(value, context)
  ResourcesCapability(
    subscribe?=get_optional_bool(fields, "subscribe", context),
    list_changed?=get_optional_bool(fields, "listChanged", context),
  )
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
pub fn LoggingCapability::from_json(
  value : Json,
  context? : String = "logging capability",
) -> LoggingCapability raise McpError {
  ignore(expect_object(value, context))
  LoggingCapability()
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
    extensions: copy_json_map(extensions),
    experimental: copy_json_map(experimental),
    extra: copy_json_map(extra),
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
  let fields = copy_json_map(self.extra)
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
pub fn ServerCapabilities::from_json(
  value : Json,
  context? : String = "server capabilities",
) -> ServerCapabilities raise McpError {
  let fields = expect_object(value, context)
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
  ServerCapabilities(
    tools?=match fields.get("tools") {
      Some(value) =>
        Some(ToolsCapability::from_json(value, context="\{context}.tools"))
      None => None
    },
    resources?=match fields.get("resources") {
      Some(value) =>
        Some(
          ResourcesCapability::from_json(value, context="\{context}.resources"),
        )
      None => None
    },
    prompts?=match fields.get("prompts") {
      Some(value) =>
        Some(PromptsCapability::from_json(value, context="\{context}.prompts"))
      None => None
    },
    logging?=match fields.get("logging") {
      Some(value) =>
        Some(LoggingCapability::from_json(value, context="\{context}.logging"))
      None => None
    },
    completions=match fields.get("completions") {
      Some(Object(_)) => true
      Some(_) => raise InvalidParams("\{context}.completions must be an object")
      None => false
    },
    extensions=parse_capability_map(fields, "extensions", context),
    experimental=parse_capability_map(fields, "experimental", context),
    extra~,
  )
}
