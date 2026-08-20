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
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
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
    InvalidEnvelope(msg) => raise @mcp.InvalidParams(msg)
  }
  request.to_json()
}

///|
fn Client::discover_request(
  self : Client,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  self.request_raw(method_name="server/discover", options~)
}

///|
fn Client::list_tools_request(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  let params : Map[String, Json] = Map([])
  params.set_opt("cursor", cursor.map(Json::string))
  self.request_raw(method_name="tools/list", params~, options~)
}

///|
fn Client::call_tool_request(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  guard arguments is Object(_) else {
    raise @mcp.InvalidParams("tool arguments must be an object")
  }
  self.request_raw(
    method_name="tools/call",
    params={ "name": Json::string(name), "arguments": arguments },
    options~,
  )
}

///|
fn Client::list_resources_request(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  let params : Map[String, Json] = Map([])
  params.set_opt("cursor", cursor.map(Json::string))
  self.request_raw(method_name="resources/list", params~, options~)
}

///|
fn Client::list_resource_templates_request(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  let params : Map[String, Json] = Map([])
  params.set_opt("cursor", cursor.map(Json::string))
  self.request_raw(method_name="resources/templates/list", params~, options~)
}

///|
fn Client::read_resource_request(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  self.request_raw(
    method_name="resources/read",
    params={ "uri": Json::string(uri) },
    options~,
  )
}

///|
fn Client::list_prompts_request(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  let params : Map[String, Json] = Map([])
  params.set_opt("cursor", cursor.map(Json::string))
  self.request_raw(method_name="prompts/list", params~, options~)
}

///|
fn Client::get_prompt_request(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  guard arguments is Object(_) else {
    raise @mcp.InvalidParams("prompt arguments must be an object")
  }
  self.request_raw(
    method_name="prompts/get",
    params={ "name": Json::string(name), "arguments": arguments },
    options~,
  )
}

///|
fn Client::complete_request(
  self : Client,
  reference~ : @mcp.CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
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
fn Client::listen_request(
  self : Client,
  notifications~ : @mcp.SubscriptionFilter,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  self.request_raw(
    method_name="subscriptions/listen",
    params={ "notifications": notifications.to_json() },
    options~,
  )
}
