///|
/// Transport-neutral MCP 2026-07-28 request builder and response decoder.
///
/// The client keeps only defaults and a request-id counter. Every request is
/// self-contained and receives a fresh copy of protocol metadata.
pub struct Client {
  priv info : Implementation
  priv capabilities : ClientCapabilities
  priv protocol_version : String
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
  protocol_version? : String = latest_protocol_version,
) -> Client {
  {
    info: Implementation(
      name~,
      version~,
      title?,
      description?,
      icons~,
      website_url?,
    ),
    capabilities,
    protocol_version,
    next_request_id: 1,
  }
}

///|
pub fn Client::protocol_version(self : Client) -> String {
  self.protocol_version
}

///|
pub fn Client::capabilities(self : Client) -> ClientCapabilities {
  self.capabilities
}

///|
pub fn Client::info(self : Client) -> Implementation {
  self.info
}

///|
fn Client::fresh_id(self : Client) -> Json {
  let id = self.next_request_id
  self.next_request_id += 1
  Json::number(id.to_double(), repr="\{id}")
}

///|
/// Build a custom extension request with mandatory modern request metadata.
pub fn Client::request(
  self : Client,
  method_name~ : String,
  params? : Map[String, Json] = Map([]),
  options? : RequestOptions = RequestOptions(),
) -> Json {
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
) -> Json {
  self.request(method_name="server/discover", options~)
}

///|
pub fn Client::list_tools_request(
  self : Client,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> Json {
  let params : Map[String, Json] = Map([])
  put_optional_string(params, "cursor", cursor)
  self.request(method_name="tools/list", params~, options~)
}

///|
pub fn Client::call_tool_request(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  ignore(expect_object(arguments, "tool arguments"))
  self.request(
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
) -> Json {
  let params : Map[String, Json] = Map([])
  put_optional_string(params, "cursor", cursor)
  self.request(method_name="resources/list", params~, options~)
}

///|
pub fn Client::list_resource_templates_request(
  self : Client,
  cursor? : String,
  options? : RequestOptions = RequestOptions(),
) -> Json {
  let params : Map[String, Json] = Map([])
  put_optional_string(params, "cursor", cursor)
  self.request(method_name="resources/templates/list", params~, options~)
}

///|
pub fn Client::read_resource_request(
  self : Client,
  uri~ : String,
  options? : RequestOptions = RequestOptions(),
) -> Json {
  self.request(
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
) -> Json {
  let params : Map[String, Json] = Map([])
  put_optional_string(params, "cursor", cursor)
  self.request(method_name="prompts/list", params~, options~)
}

///|
pub fn Client::get_prompt_request(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : RequestOptions = RequestOptions(),
) -> Json raise McpError {
  ignore(expect_object(arguments, "prompt arguments"))
  self.request(
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
) -> Json {
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
  self.request(method_name="completion/complete", params~, options~)
}

///|
pub fn Client::listen_request(
  self : Client,
  notifications~ : SubscriptionFilter,
  options? : RequestOptions = RequestOptions(),
) -> Json {
  self.request(
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
    _ => raise InvalidRequest("unreachable result type")
  }
}

///|
pub fn Client::decode_discover(
  self : Client,
  message : Json,
) -> DiscoverResult raise McpError {
  match self.decode_response(message) {
    Complete(result) => parse_discover_result(result)
    InputRequired(_) =>
      raise InvalidRequest("server/discover cannot return input_required")
  }
}

///|
pub fn structured_content(result : Json) -> Json raise McpError {
  let fields = expect_object(result, "tools/call result")
  match fields.get("structuredContent") {
    Some(value) => value
    None => raise InvalidRequest("tools/call result has no structuredContent")
  }
}

///|
pub fn[T : FromJson] decode_structured_content(
  result : Json,
) -> T raise McpError {
  @json.from_json(structured_content(result)) catch {
    error => raise InvalidParams(error.to_string())
  }
}
