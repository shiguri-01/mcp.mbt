///|
pub(all) struct RootsCapability {
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
  let fields : Map[String, Json] = {}
  put_optional_bool(fields, "listChanged", self.list_changed)
  Json::object(fields)
}

///|
pub(all) struct SamplingCapability {
  context : Bool
  tools : Bool
} derive(Debug, Eq)

///|
pub fn SamplingCapability::SamplingCapability(
  context? : Bool = false,
  tools? : Bool = false,
) -> SamplingCapability {
  { context, tools }
}

///|
pub impl ToJson for SamplingCapability with fn to_json(
  self : SamplingCapability,
) -> Json {
  let fields : Map[String, Json] = {}
  if self.context {
    fields["context"] = Json::object({})
  }
  if self.tools {
    fields["tools"] = Json::object({})
  }
  Json::object(fields)
}

///|
pub(all) struct ElicitationCapability {
  form : Bool
  url : Bool
} derive(Debug, Eq)

///|
pub fn ElicitationCapability::ElicitationCapability(
  form? : Bool = false,
  url? : Bool = false,
) -> ElicitationCapability {
  { form, url }
}

///|
pub impl ToJson for ElicitationCapability with fn to_json(
  self : ElicitationCapability,
) -> Json {
  let fields : Map[String, Json] = {}
  if self.form {
    fields["form"] = Json::object({})
  }
  if self.url {
    fields["url"] = Json::object({})
  }
  Json::object(fields)
}

///|
pub(all) struct ClientTaskRequestCapabilities {
  sampling_create_message : Bool
  elicitation_create : Bool
} derive(Debug, Eq)

///|
pub fn ClientTaskRequestCapabilities::ClientTaskRequestCapabilities(
  sampling_create_message? : Bool = false,
  elicitation_create? : Bool = false,
) -> ClientTaskRequestCapabilities {
  { sampling_create_message, elicitation_create }
}

///|
pub impl ToJson for ClientTaskRequestCapabilities with fn to_json(
  self : ClientTaskRequestCapabilities,
) -> Json {
  let fields : Map[String, Json] = {}
  if self.sampling_create_message {
    fields["sampling"] = Json::object({ "createMessage": Json::object({}) })
  }
  if self.elicitation_create {
    fields["elicitation"] = Json::object({ "create": Json::object({}) })
  }
  Json::object(fields)
}

///|
pub(all) struct ClientTaskCapabilities {
  list : Bool
  cancel : Bool
  requests : ClientTaskRequestCapabilities?
} derive(Debug, Eq)

///|
pub fn ClientTaskCapabilities::ClientTaskCapabilities(
  list? : Bool = false,
  cancel? : Bool = false,
  requests? : ClientTaskRequestCapabilities,
) -> ClientTaskCapabilities {
  { list, cancel, requests }
}

///|
pub impl ToJson for ClientTaskCapabilities with fn to_json(
  self : ClientTaskCapabilities,
) -> Json {
  let fields : Map[String, Json] = {}
  if self.list {
    fields["list"] = Json::object({})
  }
  if self.cancel {
    fields["cancel"] = Json::object({})
  }
  if self.requests is Some(requests) {
    fields["requests"] = requests.to_json()
  }
  Json::object(fields)
}

///|
pub(all) struct ClientCapabilities {
  roots : RootsCapability?
  sampling : SamplingCapability?
  elicitation : ElicitationCapability?
  tasks : ClientTaskCapabilities?
  experimental : Json?
  extra : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn ClientCapabilities::ClientCapabilities(
  roots? : RootsCapability,
  sampling? : SamplingCapability,
  elicitation? : ElicitationCapability,
  tasks? : ClientTaskCapabilities,
  experimental? : Json,
  extra? : Map[String, Json] = {},
) -> ClientCapabilities {
  { roots, sampling, elicitation, tasks, experimental, extra }
}

///|
pub fn ClientCapabilities::empty() -> ClientCapabilities {
  ClientCapabilities()
}

///|
pub impl ToJson for ClientCapabilities with fn to_json(
  self : ClientCapabilities,
) -> Json {
  let fields : Map[String, Json] = {}
  for key, value in self.extra {
    fields[key] = value
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
  if self.tasks is Some(tasks) {
    fields["tasks"] = tasks.to_json()
  }
  put_optional_json(fields, "experimental", self.experimental)
  Json::object(fields)
}

///|
fn has_object_field(
  fields : Map[String, Json],
  key : String,
  context : String,
) -> Bool raise McpError {
  match fields.get(key) {
    Some(Object(_)) => true
    Some(Null) | None => false
    Some(_) => raise InvalidParams("\{context}.\{key} must be an object")
  }
}

///|
fn parse_roots_capability(
  value : Json,
  context : String,
) -> RootsCapability raise McpError {
  let fields = expect_object(value, context)
  RootsCapability(
    list_changed?=get_optional_bool(fields, "listChanged", context),
  )
}

///|
fn parse_sampling_capability(
  value : Json,
  context : String,
) -> SamplingCapability raise McpError {
  let fields = expect_object(value, context)
  SamplingCapability(
    context=has_object_field(fields, "context", context),
    tools=has_object_field(fields, "tools", context),
  )
}

///|
fn parse_elicitation_capability(
  value : Json,
  context : String,
) -> ElicitationCapability raise McpError {
  let fields = expect_object(value, context)
  ElicitationCapability(
    form=has_object_field(fields, "form", context),
    url=has_object_field(fields, "url", context),
  )
}

///|
fn parse_client_task_requests(
  value : Json,
  context : String,
) -> ClientTaskRequestCapabilities raise McpError {
  let fields = expect_object(value, context)
  let sampling_create_message = match
    get_optional_fields(fields, "sampling", context) {
    Some(sampling) =>
      has_object_field(sampling, "createMessage", "\{context}.sampling")
    None => false
  }
  let elicitation_create = match
    get_optional_fields(fields, "elicitation", context) {
    Some(elicitation) =>
      has_object_field(elicitation, "create", "\{context}.elicitation")
    None => false
  }
  ClientTaskRequestCapabilities(sampling_create_message~, elicitation_create~)
}

///|
fn parse_client_task_capabilities(
  value : Json,
  context : String,
) -> ClientTaskCapabilities raise McpError {
  let fields = expect_object(value, context)
  ClientTaskCapabilities(
    list=has_object_field(fields, "list", context),
    cancel=has_object_field(fields, "cancel", context),
    requests?=match fields.get("requests") {
      Some(value) =>
        Some(parse_client_task_requests(value, "\{context}.requests"))
      None => None
    },
  )
}

///|
fn parse_client_capabilities(value : Json) -> ClientCapabilities raise McpError {
  let fields = expect_object(value, "initialize params.capabilities")
  let extra : Map[String, Json] = {}
  for key, value in fields {
    match key {
      "roots" | "sampling" | "elicitation" | "tasks" | "experimental" => ()
      _ => extra[key] = value
    }
  }
  ClientCapabilities(
    roots?=match fields.get("roots") {
      Some(value) =>
        Some(
          parse_roots_capability(value, "initialize params.capabilities.roots"),
        )
      None => None
    },
    sampling?=match fields.get("sampling") {
      Some(value) =>
        Some(
          parse_sampling_capability(
            value, "initialize params.capabilities.sampling",
          ),
        )
      None => None
    },
    elicitation?=match fields.get("elicitation") {
      Some(value) =>
        Some(
          parse_elicitation_capability(
            value, "initialize params.capabilities.elicitation",
          ),
        )
      None => None
    },
    tasks?=match fields.get("tasks") {
      Some(value) =>
        Some(
          parse_client_task_capabilities(
            value, "initialize params.capabilities.tasks",
          ),
        )
      None => None
    },
    experimental?=match fields.get("experimental") {
      Some(Object(_) as value) => Some(value)
      Some(Null) | None => None
      Some(_) =>
        raise InvalidParams(
          "initialize params.capabilities.experimental must be an object",
        )
    },
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
  let fields : Map[String, Json] = {}
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
  let fields : Map[String, Json] = {}
  put_optional_bool(fields, "listChanged", self.list_changed)
  Json::object(fields)
}

///|
/// Server resource capability flags.
pub(all) struct ResourcesCapability {
  subscribe : Bool?
  list_changed : Bool?
} derive(Debug, Eq)

///|
/// Create resource capabilities for subscriptions and list change notifications.
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
  let fields : Map[String, Json] = {}
  put_optional_bool(fields, "subscribe", self.subscribe)
  put_optional_bool(fields, "listChanged", self.list_changed)
  Json::object(fields)
}

///|
pub(all) struct ServerTaskRequestCapabilities {
  tools_call : Bool
} derive(Debug, Eq)

///|
pub fn ServerTaskRequestCapabilities::ServerTaskRequestCapabilities(
  tools_call? : Bool = false,
) -> ServerTaskRequestCapabilities {
  { tools_call, }
}

///|
pub impl ToJson for ServerTaskRequestCapabilities with fn to_json(
  self : ServerTaskRequestCapabilities,
) -> Json {
  let fields : Map[String, Json] = {}
  if self.tools_call {
    fields["tools"] = Json::object({ "call": Json::object({}) })
  }
  Json::object(fields)
}

///|
pub(all) struct ServerTaskCapabilities {
  list : Bool
  cancel : Bool
  requests : ServerTaskRequestCapabilities?
} derive(Debug, Eq)

///|
pub fn ServerTaskCapabilities::ServerTaskCapabilities(
  list? : Bool = false,
  cancel? : Bool = false,
  requests? : ServerTaskRequestCapabilities,
) -> ServerTaskCapabilities {
  { list, cancel, requests }
}

///|
pub impl ToJson for ServerTaskCapabilities with fn to_json(
  self : ServerTaskCapabilities,
) -> Json {
  let fields : Map[String, Json] = {}
  if self.list {
    fields["list"] = Json::object({})
  }
  if self.cancel {
    fields["cancel"] = Json::object({})
  }
  if self.requests is Some(requests) {
    fields["requests"] = requests.to_json()
  }
  Json::object(fields)
}

///|
pub(all) struct ServerCapabilities {
  tools : ToolsCapability?
  resources : ResourcesCapability?
  prompts : PromptsCapability?
  logging : Bool
  completions : Bool
  tasks : ServerTaskCapabilities?
  experimental : Json?
  extra : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn ServerCapabilities::ServerCapabilities(
  tools? : ToolsCapability,
  resources? : ResourcesCapability,
  prompts? : PromptsCapability,
  logging? : Bool = false,
  completions? : Bool = false,
  tasks? : ServerTaskCapabilities,
  experimental? : Json,
  extra? : Map[String, Json] = {},
) -> ServerCapabilities {
  {
    tools,
    resources,
    prompts,
    logging,
    completions,
    tasks,
    experimental,
    extra,
  }
}

///|
pub fn ServerCapabilities::tools_only(
  list_changed? : Bool = false,
) -> ServerCapabilities {
  ServerCapabilities(tools=ToolsCapability(list_changed~))
}

///|
/// Create a server capability set with tools, prompts, resources, and utilities.
pub fn ServerCapabilities::full(
  list_changed? : Bool = false,
  resource_subscribe? : Bool,
  logging? : Bool = true,
  completions? : Bool = true,
  tasks? : ServerTaskCapabilities,
  experimental? : Json,
) -> ServerCapabilities {
  ServerCapabilities(
    tools=ToolsCapability(list_changed~),
    resources=ResourcesCapability(subscribe?=resource_subscribe, list_changed~),
    prompts=PromptsCapability(list_changed~),
    logging~,
    completions~,
    tasks?,
    experimental?,
  )
}

///|
pub impl ToJson for ServerCapabilities with fn to_json(
  self : ServerCapabilities,
) -> Json {
  let fields : Map[String, Json] = {}
  for key, value in self.extra {
    fields[key] = value
  }
  if self.tools is Some(tools) {
    fields["tools"] = tools.to_json()
  }
  if self.resources is Some(resources) {
    fields["resources"] = resources.to_json()
  }
  if self.prompts is Some(prompts) {
    fields["prompts"] = prompts.to_json()
  }
  if self.logging {
    fields["logging"] = Json::object({})
  }
  if self.completions {
    fields["completions"] = Json::object({})
  }
  if self.tasks is Some(tasks) {
    fields["tasks"] = tasks.to_json()
  }
  put_optional_json(fields, "experimental", self.experimental)
  Json::object(fields)
}

///|
pub(all) struct InitializeResult {
  protocol_version : String
  capabilities : ServerCapabilities
  server_info : Implementation
  instructions : String?
  meta : Json?
} derive(Debug, Eq)

///|
pub impl ToJson for InitializeResult with fn to_json(self : InitializeResult) -> Json {
  let fields : Map[String, Json] = {
    "protocolVersion": Json::string(self.protocol_version),
    "capabilities": self.capabilities.to_json(),
    "serverInfo": self.server_info.to_json(),
  }
  put_optional_string(fields, "instructions", self.instructions)
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}
