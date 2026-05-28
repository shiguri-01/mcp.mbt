///|
pub struct Client {
  priv endpoint : @jsonrpc.Endpoint
}

///|
pub fn Client::Client() -> Client {
  { endpoint: try! @jsonrpc.EndpointBuilder().build() }
}

///|
fn Client::jsonrpc_request(
  self : Client,
  method_name : String,
  params? : Json,
) -> Json {
  try! self.endpoint.request(method_name, params?)
}

///|
fn jsonrpc_notification(method_name : String, params? : Json) -> Json {
  try! @jsonrpc.EndpointBuilder().build().notify(method_name, params?)
}

///|
fn rpc_error_to_mcp_error(error : @jsonrpc.RpcError) -> McpError {
  let (code, message) = match error {
    @jsonrpc.RpcError(code~, message~) => (code, message)
    @jsonrpc.RpcErrorWithData(code~, message~, ..) => (code, message)
  }
  if error
    is @jsonrpc.RpcErrorWithData(
      code=-32002,
      data=Object({ "uri": String(uri), .. }),
      ..
    ) {
    return ResourceNotFound(uri)
  }
  match code {
    @jsonrpc.PARSE_ERROR_CODE => ParseError(message)
    @jsonrpc.INVALID_REQUEST_CODE => InvalidRequest(message)
    @jsonrpc.METHOD_NOT_FOUND_CODE => MethodNotFound(message)
    @jsonrpc.INVALID_PARAMS_CODE => InvalidParams(message)
    -32002 => ResourceNotFound(message)
    @jsonrpc.INTERNAL_ERROR_CODE => InternalError(message)
    _ => InternalError(message)
  }
}

///|
/// Receive one JSON-RPC response message and complete a pending client request.
pub async fn Client::receive_jsonrpc(
  self : Client,
  message : Json,
) -> Json? raise McpError {
  let received = self.endpoint.receive_json(message) catch {
    error => raise InternalError(error.to_string())
  }
  match received.completed {
    [{ result: Ok(result), .. }, ..] => Some(result)
    [{ result: Err(error), .. }, ..] => raise rpc_error_to_mcp_error(error)
    [] => None
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

///|
pub fn Client::initialize_request(
  self : Client,
  client_name~ : String,
  client_version~ : String,
  client_title? : String,
  client_description? : String,
  client_icons? : Array[Icon] = [],
  client_website_url? : String,
  capabilities? : ClientCapabilities = ClientCapabilities::empty(),
) -> Json {
  self.jsonrpc_request(
    "initialize",
    params=Json::object({
      "protocolVersion": Json::string(latest_protocol_version),
      "capabilities": capabilities.to_json(),
      "clientInfo": Implementation(
        name=client_name,
        version=client_version,
        title?=client_title,
        description?=client_description,
        icons=client_icons,
        website_url?=client_website_url,
      ).to_json(),
    }),
  )
}

///|
pub fn Client::initialized_notification(_self : Client) -> Json {
  jsonrpc_notification("notifications/initialized")
}

///|
pub fn Client::list_tools_request(self : Client, cursor? : String) -> Json {
  let params : Map[String, Json] = {}
  put_optional_string(params, "cursor", cursor)
  self.jsonrpc_request("tools/list", params=Json::object(params))
}

///|
pub fn Client::call_tool_request(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
) -> Json {
  self.jsonrpc_request(
    "tools/call",
    params=Json::object({ "name": Json::string(name), "arguments": arguments }),
  )
}

///|
pub fn Client::list_resources_request(self : Client, cursor? : String) -> Json {
  let params : Map[String, Json] = {}
  put_optional_string(params, "cursor", cursor)
  self.jsonrpc_request("resources/list", params=Json::object(params))
}

///|
pub fn Client::list_resource_templates_request(
  self : Client,
  cursor? : String,
) -> Json {
  let params : Map[String, Json] = {}
  put_optional_string(params, "cursor", cursor)
  self.jsonrpc_request("resources/templates/list", params=Json::object(params))
}

///|
pub fn Client::read_resource_request(self : Client, uri~ : String) -> Json {
  self.jsonrpc_request(
    "resources/read",
    params=Json::object({ "uri": Json::string(uri) }),
  )
}

///|
/// Build a `resources/subscribe` request for one resource URI.
pub fn Client::subscribe_resource_request(self : Client, uri~ : String) -> Json {
  self.jsonrpc_request(
    "resources/subscribe",
    params=Json::object({ "uri": Json::string(uri) }),
  )
}

///|
/// Build a `resources/unsubscribe` request for one resource URI.
pub fn Client::unsubscribe_resource_request(
  self : Client,
  uri~ : String,
) -> Json {
  self.jsonrpc_request(
    "resources/unsubscribe",
    params=Json::object({ "uri": Json::string(uri) }),
  )
}

///|
pub fn Client::list_prompts_request(self : Client, cursor? : String) -> Json {
  let params : Map[String, Json] = {}
  put_optional_string(params, "cursor", cursor)
  self.jsonrpc_request("prompts/list", params=Json::object(params))
}

///|
pub fn Client::get_prompt_request(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
) -> Json {
  self.jsonrpc_request(
    "prompts/get",
    params=Json::object({ "name": Json::string(name), "arguments": arguments }),
  )
}

///|
pub fn Client::complete_request(
  self : Client,
  reference~ : CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
) -> Json {
  let params : Map[String, Json] = {
    "ref": reference.to_json(),
    "argument": Json::object({
      "name": Json::string(argument_name),
      "value": Json::string(argument_value),
    }),
  }
  if context_arguments is Some(arguments) {
    let argument_fields : Map[String, Json] = {}
    for key, value in arguments {
      argument_fields[key] = Json::string(value)
    }
    params["context"] = Json::object({
      "arguments": Json::object(argument_fields),
    })
  }
  self.jsonrpc_request("completion/complete", params=Json::object(params))
}

///|
pub fn Client::set_logging_level_request(
  self : Client,
  level~ : LoggingLevel,
) -> Json {
  self.jsonrpc_request(
    "logging/setLevel",
    params=Json::object({ "level": level.to_json() }),
  )
}

///|
pub fn Client::ping_request(self : Client) -> Json {
  self.jsonrpc_request("ping")
}
