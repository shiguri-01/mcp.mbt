///|
pub(all) struct ServerCapabilities {
  tools_list_changed : Bool
  resources : Json?
  prompts : Json?
  experimental : Json?
} derive(Debug, Eq)

///|
pub fn ServerCapabilities::tools_only(
  list_changed? : Bool = false,
) -> ServerCapabilities {
  {
    tools_list_changed: list_changed,
    resources: None,
    prompts: None,
    experimental: None,
  }
}

///|
pub fn ServerCapabilities::full(
  list_changed? : Bool = false,
  experimental? : Json,
) -> ServerCapabilities {
  {
    tools_list_changed: list_changed,
    resources: Some(
      Json::object({ "listChanged": Json::boolean(list_changed) }),
    ),
    prompts: Some(Json::object({ "listChanged": Json::boolean(list_changed) })),
    experimental,
  }
}

///|
pub impl ToJson for ServerCapabilities with fn to_json(
  self : ServerCapabilities,
) -> Json {
  let fields : Map[String, Json] = {
    "tools": Json::object({
      "listChanged": Json::boolean(self.tools_list_changed),
    }),
  }
  put_optional_json(fields, "resources", self.resources)
  put_optional_json(fields, "prompts", self.prompts)
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
