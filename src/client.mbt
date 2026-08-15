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
  protocol_version? : String = LATEST_PROTOCOL_VERSION,
) -> Client raise McpError {
  if name.is_empty() || version.is_empty() || protocol_version.is_empty() {
    raise InvalidParams(
      "client name, version, and protocol version must not be empty",
    )
  }
  validate_extension_map(capabilities.extensions)
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
fn Client::fresh_id(self : Client) -> @jsonrpc.RequestId {
  let id = self.next_request_id
  self.next_request_id += 1
  try! @jsonrpc.RequestId::number(id.to_double(), repr="\{id}")
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
  let payload = options.request_params(
    params,
    client_capabilities=self.capabilities,
    client_info=self.info,
    protocol_version=self.protocol_version,
  )
  let request = @jsonrpc.Request(
    id=self.fresh_id(),
    method_name~,
    params=payload,
  ) catch {
    InvalidEnvelope(msg) => raise InvalidParams(msg)
  }
  request.to_json()
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
  params.set_opt("cursor", cursor.map(Json::string))
  self.request_raw(method_name="tools/list", params~, options~)
}

///|
pub fn Client::call_tool_request(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  guard arguments is Object(_) else {
    raise InvalidParams("tool arguments must be an object")
  }
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
  params.set_opt("cursor", cursor.map(Json::string))
  self.request_raw(method_name="resources/list", params~, options~)
}

///|
pub fn Client::list_resource_templates_request(
  self : Client,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  let params : Map[String, Json] = Map([])
  params.set_opt("cursor", cursor.map(Json::string))
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
  params.set_opt("cursor", cursor.map(Json::string))
  self.request_raw(method_name="prompts/list", params~, options~)
}

///|
pub fn Client::get_prompt_request(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  guard arguments is Object(_) else {
    raise InvalidParams("prompt arguments must be an object")
  }
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
    "input_required" => InputRequired(InputRequiredResult::from_json(result))
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
    Complete(result) => DiscoverResult::from_json(result)
    InputRequired(_) =>
      raise InvalidRequest("server/discover cannot return input_required")
    ExtensionResult(result_type, _) =>
      raise InvalidRequest(
        "server/discover cannot return extension result type \{result_type}",
      )
  }
}

///|
/// A transport interface for client operations.
pub(open) trait ClientTransport {
  async fn request_with_notifications(
    self : Self,
    request : Json,
    on_notification~ : (Json) -> Unit,
  ) -> HandlerOutcome[Json] raise McpError
  async fn notify(self : Self, notification : Json) -> Unit raise McpError
}

///|
pub async fn[T : ClientTransport] Client::request(
  self : Client,
  transport : T,
  request : Json,
) -> HandlerOutcome[Json] raise McpError {
  ignore(self)
  transport.request_with_notifications(request, on_notification=fn(_) { () })
}

///|
pub fn require_complete(
  outcome : HandlerOutcome[Json],
  method_name : String,
) -> Json raise McpError {
  match outcome {
    Complete(result) => result
    InputRequired(_) =>
      raise InvalidRequest("\{method_name} cannot return input_required")
    ExtensionResult(result_type, _) =>
      raise InvalidRequest(
        "\{method_name} cannot return extension result type \{result_type}",
      )
  }
}

///|
pub fn validate_max_rounds(max_rounds : Int) -> Unit raise McpError {
  if max_rounds <= 0 {
    raise InvalidRequest("max_rounds must be positive")
  }
}

///|
pub async fn[T : ClientTransport] Client::discover(
  self : Client,
  transport : T,
  options? : RequestOptions = RequestOptions(),
) -> DiscoverResult raise McpError {
  let outcome = self.request(transport, self.discover_request(options~))
  DiscoverResult::from_json(require_complete(outcome, "server/discover"))
}

///|
pub async fn[T : ClientTransport] Client::list_tools_raw(
  self : Client,
  transport : T,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  require_complete(
    self.request(transport, self.list_tools_request(cursor?, options~)),
    "tools/list",
  )
}

///|
pub async fn[T : ClientTransport] Client::list_tools(
  self : Client,
  transport : T,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> ListToolsResult raise McpError {
  ListToolsResult::from_json(self.list_tools_raw(transport, cursor?, options~))
}

///|
pub async fn[T : ClientTransport] Client::call_tool_raw(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
) -> HandlerOutcome[Json] raise McpError {
  self.request(transport, self.call_tool_request(name~, arguments~, options~))
}

///|
pub async fn[T : ClientTransport] Client::call_tool(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
) -> HandlerOutcome[CallToolResult] raise McpError {
  match self.call_tool_raw(transport, name~, arguments~, options~) {
    Complete(result) => Complete(CallToolResult::from_json(result))
    InputRequired(value) => InputRequired(value)
    ExtensionResult(result_type, value) => ExtensionResult(result_type, value)
  }
}

///|
pub async fn[T : ClientTransport, R : FromJson] Client::call_tool_as(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
) -> HandlerOutcome[R] raise McpError {
  match self.call_tool_raw(transport, name~, arguments~, options~) {
    Complete(result) =>
      Complete(CallToolResult::from_json(result).decode_structured())
    InputRequired(value) => InputRequired(value)
    ExtensionResult(result_type, value) => ExtensionResult(result_type, value)
  }
}

///|
pub async fn[T : ClientTransport] Client::list_resources_raw(
  self : Client,
  transport : T,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  require_complete(
    self.request(transport, self.list_resources_request(cursor?, options~)),
    "resources/list",
  )
}

///|
pub async fn[T : ClientTransport] Client::list_resources(
  self : Client,
  transport : T,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> ListResourcesResult raise McpError {
  ListResourcesResult::from_json(
    self.list_resources_raw(transport, cursor?, options~),
  )
}

///|
pub async fn[T : ClientTransport] Client::list_resource_templates_raw(
  self : Client,
  transport : T,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  require_complete(
    self.request(
      transport,
      self.list_resource_templates_request(cursor?, options~),
    ),
    "resources/templates/list",
  )
}

///|
pub async fn[T : ClientTransport] Client::list_resource_templates(
  self : Client,
  transport : T,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> ListResourceTemplatesResult raise McpError {
  ListResourceTemplatesResult::from_json(
    self.list_resource_templates_raw(transport, cursor?, options~),
  )
}

///|
pub async fn[T : ClientTransport] Client::read_resource_raw(
  self : Client,
  transport : T,
  uri~ : String,
  options? : RequestOptions = RequestOptions(),
) -> HandlerOutcome[Json] raise McpError {
  self.request(transport, self.read_resource_request(uri~, options~))
}

///|
pub async fn[T : ClientTransport] Client::read_resource(
  self : Client,
  transport : T,
  uri~ : String,
  options? : RequestOptions = RequestOptions(),
) -> HandlerOutcome[ReadResourceResult] raise McpError {
  match self.read_resource_raw(transport, uri~, options~) {
    Complete(result) => Complete(ReadResourceResult::from_json(result))
    InputRequired(value) => InputRequired(value)
    ExtensionResult(result_type, value) => ExtensionResult(result_type, value)
  }
}

///|
pub async fn[T : ClientTransport] Client::list_prompts_raw(
  self : Client,
  transport : T,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  require_complete(
    self.request(transport, self.list_prompts_request(cursor?, options~)),
    "prompts/list",
  )
}

///|
pub async fn[T : ClientTransport] Client::list_prompts(
  self : Client,
  transport : T,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> ListPromptsResult raise McpError {
  ListPromptsResult::from_json(
    self.list_prompts_raw(transport, cursor?, options~),
  )
}

///|
pub async fn[T : ClientTransport] Client::get_prompt_raw(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
) -> HandlerOutcome[Json] raise McpError {
  self.request(transport, self.get_prompt_request(name~, arguments~, options~))
}

///|
pub async fn[T : ClientTransport] Client::get_prompt(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
) -> HandlerOutcome[GetPromptResult] raise McpError {
  match self.get_prompt_raw(transport, name~, arguments~, options~) {
    Complete(result) => Complete(GetPromptResult::from_json(result))
    InputRequired(value) => InputRequired(value)
    ExtensionResult(result_type, value) => ExtensionResult(result_type, value)
  }
}

///|
pub async fn[T : ClientTransport] Client::complete_raw(
  self : Client,
  transport : T,
  reference~ : CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  let request = self.complete_request(
    reference~,
    argument_name~,
    argument_value~,
    context_arguments?,
    options~,
  )
  require_complete(self.request(transport, request), "completion/complete")
}

///|
pub async fn[T : ClientTransport] Client::complete(
  self : Client,
  transport : T,
  reference~ : CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
  options? : RequestOptions = RequestOptions(),
) -> CompleteResult raise McpError {
  CompleteResult::from_json(
    self.complete_raw(
      transport,
      reference~,
      argument_name~,
      argument_value~,
      context_arguments?,
      options~,
    ),
  )
}

///|
pub async fn[T : ClientTransport] Client::listen(
  self : Client,
  transport : T,
  notifications~ : SubscriptionFilter,
  on_notification~ : (Json) -> Unit,
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  require_complete(
    transport.request_with_notifications(
      self.listen_request(notifications~, options~),
      on_notification~,
    ),
    "subscriptions/listen",
  )
}

///|
pub async fn[T : ClientTransport] Client::resolve_mrtr(
  self : Client,
  transport : T,
  build : (RequestOptions) -> Json raise McpError,
  resolve : async (Map[String, InputRequest]) -> Map[String, InputResponse] raise McpError,
  options : RequestOptions,
  rounds_left : Int,
) -> Json raise McpError {
  match self.request(transport, build(options)) {
    Complete(result) => result
    InputRequired(pending) => {
      if rounds_left <= 0 {
        raise InvalidRequest("MRTR exceeded max_rounds")
      }
      let requests = pending.input_requests.unwrap_or(Map([]))
      let responses = resolve(requests)
      self.resolve_mrtr(
        transport,
        build,
        resolve,
        pending.retry_options(responses, base=options),
        rounds_left - 1,
      )
    }
    ExtensionResult(_, result) => result
  }
}

///|
pub async fn[T : ClientTransport] Client::call_tool_resolving_raw(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, InputRequest]) -> Map[String, InputResponse] raise McpError,
) -> Json raise McpError {
  validate_max_rounds(max_rounds)
  self.resolve_mrtr(
    transport,
    options => self.call_tool_request(name~, arguments~, options~),
    resolve,
    options,
    max_rounds,
  )
}

///|
pub async fn[T : ClientTransport] Client::call_tool_resolving(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, InputRequest]) -> Map[String, InputResponse] raise McpError,
) -> CallToolResult raise McpError {
  CallToolResult::from_json(
    self.call_tool_resolving_raw(
      transport,
      name~,
      arguments~,
      options~,
      max_rounds~,
      resolve~,
    ),
  )
}

///|
pub async fn[T : ClientTransport] Client::read_resource_resolving_raw(
  self : Client,
  transport : T,
  uri~ : String,
  options? : RequestOptions = RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, InputRequest]) -> Map[String, InputResponse] raise McpError,
) -> Json raise McpError {
  validate_max_rounds(max_rounds)
  self.resolve_mrtr(
    transport,
    options => self.read_resource_request(uri~, options~),
    resolve,
    options,
    max_rounds,
  )
}

///|
pub async fn[T : ClientTransport] Client::read_resource_resolving(
  self : Client,
  transport : T,
  uri~ : String,
  options? : RequestOptions = RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, InputRequest]) -> Map[String, InputResponse] raise McpError,
) -> ReadResourceResult raise McpError {
  ReadResourceResult::from_json(
    self.read_resource_resolving_raw(
      transport,
      uri~,
      options~,
      max_rounds~,
      resolve~,
    ),
  )
}

///|
pub async fn[T : ClientTransport] Client::get_prompt_resolving_raw(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, InputRequest]) -> Map[String, InputResponse] raise McpError,
) -> Json raise McpError {
  validate_max_rounds(max_rounds)
  self.resolve_mrtr(
    transport,
    options => self.get_prompt_request(name~, arguments~, options~),
    resolve,
    options,
    max_rounds,
  )
}

///|
pub async fn[T : ClientTransport] Client::get_prompt_resolving(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, InputRequest]) -> Map[String, InputResponse] raise McpError,
) -> GetPromptResult raise McpError {
  GetPromptResult::from_json(
    self.get_prompt_resolving_raw(
      transport,
      name~,
      arguments~,
      options~,
      max_rounds~,
      resolve~,
    ),
  )
}

///|
