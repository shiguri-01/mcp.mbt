///|
/// Transport-neutral MCP 2026-07-28 request builder and response decoder.
///
/// The client keeps only defaults and a request-id counter. Every request is
/// self-contained and receives a fresh copy of protocol metadata.
pub struct Client {
  info : Implementation
  capabilities : ClientCapabilities
  extension_result_types : Map[String, String]
  protocol_version : String
  priv mut next_request_id : Int
}

///|
pub fn Client::Client(
  name~ : String,
  version~ : String,
  title? : String,
  description? : String,
  icons? : Array[Icon] = [],
  website_url? : String,
  capabilities? : ClientCapabilities = ClientCapabilities::empty(),
  extension_result_types? : Map[String, String] = Map([]),
  protocol_version? : String = latest_protocol_version,
) -> Client raise McpError {
  if name.is_empty() || version.is_empty() || protocol_version.is_empty() {
    raise InvalidParams(
      "client name, version, and protocol version must not be empty",
    )
  }
  validate_extension_map(
    capabilities.extensions,
    "client capabilities.extensions",
  )
  validate_extension_result_types(
    extension_result_types,
    capabilities.extensions,
  )
  {
    info: Implementation(
      name~,
      version~,
      title?,
      description?,
      icons~,
      website_url?,
    ),
    capabilities: capabilities.copy(),
    extension_result_types: extension_result_types.copy(),
    protocol_version,
    next_request_id: 1,
  }
}

///|
fn Client::fresh_id(self : Client) -> Json {
  let id = self.next_request_id
  self.next_request_id += 1
  Json::number(id.to_double(), repr="\{id}")
}

///|
/// Build a raw custom/extension request with mandatory modern request metadata.
///
/// Standard MCP operations should use the typed transport clients. This escape
/// hatch is intentionally named `request_raw` so JSON construction is visible
/// at the call site.
pub fn Client::request_raw(
  self : Client,
  method_name~ : String,
  params? : Map[String, Json] = Map([]),
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  rpc_request(
    self.fresh_id(),
    method_name,
    options.request_params(
      params,
      client_capabilities=self.capabilities,
      client_info=self.info,
      protocol_version=self.protocol_version,
    ),
  )
}

///|
pub fn Client::discover_request(
  self : Client,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  self.request_raw(method_name="server/discover", options~)
}

///|
pub fn Client::list_tools_request(
  self : Client,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  let params : Map[String, Json] = Map([])
  put_optional_string(params, "cursor", cursor)
  self.request_raw(method_name="tools/list", params~, options~)
}

///|
pub fn Client::call_tool_request(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  ignore(expect_object(arguments, "tool arguments"))
  self.request_raw(
    method_name="tools/call",
    params={ "name": Json::string(name), "arguments": arguments },
    options~,
  )
}

///|
pub fn Client::list_resources_request(
  self : Client,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  let params : Map[String, Json] = Map([])
  put_optional_string(params, "cursor", cursor)
  self.request_raw(method_name="resources/list", params~, options~)
}

///|
pub fn Client::list_resource_templates_request(
  self : Client,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  let params : Map[String, Json] = Map([])
  put_optional_string(params, "cursor", cursor)
  self.request_raw(method_name="resources/templates/list", params~, options~)
}

///|
pub fn Client::read_resource_request(
  self : Client,
  uri~ : String,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  self.request_raw(
    method_name="resources/read",
    params={ "uri": Json::string(uri) },
    options~,
  )
}

///|
pub fn Client::list_prompts_request(
  self : Client,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  let params : Map[String, Json] = Map([])
  put_optional_string(params, "cursor", cursor)
  self.request_raw(method_name="prompts/list", params~, options~)
}

///|
pub fn Client::get_prompt_request(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  ignore(expect_object(arguments, "prompt arguments"))
  self.request_raw(
    method_name="prompts/get",
    params={ "name": Json::string(name), "arguments": arguments },
    options~,
  )
}

///|
pub fn Client::complete_request(
  self : Client,
  reference~ : CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  let params : Map[String, Json] = {
    "ref": reference.to_json(),
    "argument": Json::object({
      "name": Json::string(argument_name),
      "value": Json::string(argument_value),
    }),
  }
  if context_arguments is Some(arguments) {
    let values : Map[String, Json] = Map([])
    for key, value in arguments {
      values[key] = Json::string(value)
    }
    params["context"] = Json::object({ "arguments": Json::object(values) })
  }
  self.request_raw(method_name="completion/complete", params~, options~)
}

///|
pub fn Client::listen_request(
  self : Client,
  notifications~ : SubscriptionFilter,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  self.request_raw(
    method_name="subscriptions/listen",
    params={ "notifications": notifications.to_json() },
    options~,
  )
}

///|
/// Decode a modern JSON-RPC response without treating unknown result types as
/// successful core results.
pub fn Client::decode_response(
  self : Client,
  message : Json,
) -> HandlerOutcome[Json] raise McpError {
  ignore(self)
  let result = rpc_response_result(message)
  match require_result_type(result) {
    "complete" => Complete(result)
    "input_required" => InputRequired(parse_input_required_result(result))
    result_type =>
      if self.extension_result_types.contains(result_type) {
        ExtensionResult(result_type, result)
      } else {
        raise InvalidRequest("unknown resultType: \{result_type}")
      }
  }
}

///|
pub fn Client::decode_discover(
  self : Client,
  message : Json,
) -> DiscoverResult raise McpError {
  match self.decode_response(message) {
    Complete(result) => decode_discover_result(result)
    InputRequired(_) =>
      raise InvalidRequest("server/discover cannot return input_required")
    ExtensionResult(result_type, _) =>
      raise InvalidRequest(
        "server/discover cannot return extension result type \{result_type}",
      )
  }
}

///|
