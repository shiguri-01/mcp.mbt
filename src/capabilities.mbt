///|
/// Client support for server-initiated elicitation during an MRTR.
pub(all) struct ElicitationCapability {
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
/// Wire-compatible capabilities retained only for deprecated MRTR methods.
/// New applications should prefer elicitation and extension methods.
pub(all) struct DeprecatedClientCapabilities {
  roots : Json?
  sampling : Json?
} derive(Debug, Eq)

///|
pub fn DeprecatedClientCapabilities::DeprecatedClientCapabilities(
  roots? : Json,
  sampling? : Json,
) -> DeprecatedClientCapabilities {
  { roots: copy_optional_json(roots), sampling: copy_optional_json(sampling) }
}

///|
fn DeprecatedClientCapabilities::copy(
  self : DeprecatedClientCapabilities,
) -> DeprecatedClientCapabilities {
  DeprecatedClientCapabilities(roots?=self.roots, sampling?=self.sampling)
}

///|
/// Capabilities declared independently on every request.
pub(all) struct ClientCapabilities {
  elicitation : ElicitationCapability?
  deprecated : DeprecatedClientCapabilities?
  extensions : Map[String, Json]
  experimental : Map[String, Json]
  extra : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn ClientCapabilities::ClientCapabilities(
  elicitation? : ElicitationCapability,
  deprecated? : DeprecatedClientCapabilities,
  extensions? : Map[String, Json] = {},
  experimental? : Map[String, Json] = {},
  extra? : Map[String, Json] = {},
) -> ClientCapabilities {
  {
    elicitation,
    deprecated,
    extensions: copy_json_map(extensions),
    experimental: copy_json_map(experimental),
    extra: copy_json_map(extra),
  }
}

///|
fn ClientCapabilities::copy(self : ClientCapabilities) -> ClientCapabilities {
  ClientCapabilities(
    elicitation?=self.elicitation.map(value => value.copy()),
    deprecated?=self.deprecated.map(value => value.copy()),
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
  fields.remove("elicitation")
  fields.remove("roots")
  fields.remove("sampling")
  fields.remove("extensions")
  fields.remove("experimental")
  if self.elicitation is Some(value) {
    fields["elicitation"] = value.to_json()
  }
  if self.deprecated is Some(value) {
    put_optional_json(fields, "roots", value.roots)
    put_optional_json(fields, "sampling", value.sampling)
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
fn parse_elicitation_capability(
  value : Json,
  context : String,
) -> ElicitationCapability raise McpError {
  let fields = expect_object(value, context)
  ElicitationCapability(
    form?=get_optional_object(fields, "form", context),
    url?=get_optional_object(fields, "url", context),
  )
}

///|
fn parse_client_capabilities(
  value : Json,
  context? : String = "client capabilities",
) -> ClientCapabilities raise McpError {
  let fields = expect_object(value, context)
  let parse_deprecated = fn(key : String) -> Json? raise McpError {
    match fields.get(key) {
      Some(Object(_) as value) => Some(value)
      Some(Null) | None => None
      Some(_) => raise InvalidParams("\{context}.\{key} must be an object")
    }
  }
  let roots = parse_deprecated("roots")
  let sampling = parse_deprecated("sampling")
  let extra : Map[String, Json] = Map([])
  for key, value in fields {
    match key {
      "elicitation" | "roots" | "sampling" | "extensions" | "experimental" => ()
      _ => extra[key] = value
    }
  }
  ClientCapabilities(
    elicitation?=match fields.get("elicitation") {
      Some(value) =>
        Some(parse_elicitation_capability(value, "\{context}.elicitation"))
      None => None
    },
    deprecated?=if roots is Some(_) || sampling is Some(_) {
      Some(DeprecatedClientCapabilities(roots?, sampling?))
    } else {
      None
    },
    extensions=parse_capability_map(fields, "extensions", context),
    experimental=parse_capability_map(fields, "experimental", context),
    extra~,
  )
}

///|
pub(all) struct ToolsCapability {
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
pub(all) struct PromptsCapability {
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
pub(all) struct ResourcesCapability {
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
/// Core server capabilities. Deprecated logging and extension-defined task
/// capabilities intentionally do not appear here.
pub(all) struct ServerCapabilities {
  tools : ToolsCapability?
  resources : ResourcesCapability?
  prompts : PromptsCapability?
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
  completions? : Bool = false,
  extensions? : Map[String, Json] = {},
  experimental? : Map[String, Json] = {},
  extra? : Map[String, Json] = {},
) -> ServerCapabilities {
  {
    tools,
    resources,
    prompts,
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
      "tools", "resources", "prompts", "completions", "extensions", "experimental",
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
  if self.completions {
    fields["completions"] = Json::object({})
  }
  put_capability_map(fields, "extensions", self.extensions)
  put_capability_map(fields, "experimental", self.experimental)
  Json::object(fields)
}

///|
fn parse_server_capabilities(value : Json) -> ServerCapabilities raise McpError {
  let context = "server capabilities"
  let fields = expect_object(value, context)
  let extra : Map[String, Json] = Map([])
  for key, item in fields {
    match key {
      "tools"
      | "resources"
      | "prompts"
      | "completions"
      | "extensions"
      | "experimental" => ()
      _ => extra[key] = item
    }
  }
  ServerCapabilities(
    tools?=match fields.get("tools") {
      Some(value) => {
        let item = expect_object(value, "\{context}.tools")
        Some(
          ToolsCapability(
            list_changed?=get_optional_bool(
              item,
              "listChanged",
              "\{context}.tools",
            ),
          ),
        )
      }
      None => None
    },
    resources?=match fields.get("resources") {
      Some(value) => {
        let item = expect_object(value, "\{context}.resources")
        Some(
          ResourcesCapability(
            subscribe?=get_optional_bool(
              item,
              "subscribe",
              "\{context}.resources",
            ),
            list_changed?=get_optional_bool(
              item,
              "listChanged",
              "\{context}.resources",
            ),
          ),
        )
      }
      None => None
    },
    prompts?=match fields.get("prompts") {
      Some(value) => {
        let item = expect_object(value, "\{context}.prompts")
        Some(
          PromptsCapability(
            list_changed?=get_optional_bool(
              item,
              "listChanged",
              "\{context}.prompts",
            ),
          ),
        )
      }
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
