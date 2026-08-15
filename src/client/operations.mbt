///|
/// A transport interface for client operations.
pub(open) trait ClientTransport {
  async fn request_with_notifications(
    self : Self,
    request : Json,
    on_notification~ : (Json) -> Unit,
  ) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError
  async fn notify(self : Self, notification : Json) -> Unit raise @mcp.McpError
}

///|
pub async fn[T : ClientTransport] Client::request(
  self : Client,
  transport : T,
  request : Json,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  ignore(self)
  transport.request_with_notifications(request, on_notification=fn(_) { () })
}

///|
pub async fn[T : ClientTransport] Client::discover(
  self : Client,
  transport : T,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.DiscoverResult raise @mcp.McpError {
  let outcome = self.request(transport, self.discover_request(options~))
  @mcp.DiscoverResult::from_json(
    outcome.require_complete(context="server/discover"),
  )
}

///|
pub async fn[T : ClientTransport] Client::list_tools_raw(
  self : Client,
  transport : T,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  self
  .request(transport, self.list_tools_request(cursor?, options~))
  .require_complete(context="tools/list")
}

///|
pub async fn[T : ClientTransport] Client::list_tools(
  self : Client,
  transport : T,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.ListToolsResult raise @mcp.McpError {
  @mcp.ListToolsResult::from_json(
    self.list_tools_raw(transport, cursor?, options~),
  )
}

///|
pub async fn[T : ClientTransport] Client::call_tool_raw(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.request(transport, self.call_tool_request(name~, arguments~, options~))
}

///|
pub async fn[T : ClientTransport] Client::call_tool(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[@mcp.CallToolResult] raise @mcp.McpError {
  match self.call_tool_raw(transport, name~, arguments~, options~) {
    @mcp.Complete(result) =>
      @mcp.Complete(@mcp.CallToolResult::from_json(result))
    @mcp.InputRequired(value) => @mcp.InputRequired(value)
    @mcp.ExtensionResult(result_type, value) =>
      @mcp.ExtensionResult(result_type, value)
  }
}

///|
pub async fn[T : ClientTransport, R : FromJson] Client::call_tool_as(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[R] raise @mcp.McpError {
  match self.call_tool_raw(transport, name~, arguments~, options~) {
    @mcp.Complete(result) =>
      @mcp.Complete(@mcp.CallToolResult::from_json(result).decode_structured())
    @mcp.InputRequired(value) => @mcp.InputRequired(value)
    @mcp.ExtensionResult(result_type, value) =>
      @mcp.ExtensionResult(result_type, value)
  }
}

///|
pub async fn[T : ClientTransport] Client::list_resources_raw(
  self : Client,
  transport : T,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  self
  .request(transport, self.list_resources_request(cursor?, options~))
  .require_complete(context="resources/list")
}

///|
pub async fn[T : ClientTransport] Client::list_resources(
  self : Client,
  transport : T,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.ListResourcesResult raise @mcp.McpError {
  @mcp.ListResourcesResult::from_json(
    self.list_resources_raw(transport, cursor?, options~),
  )
}

///|
pub async fn[T : ClientTransport] Client::list_resource_templates_raw(
  self : Client,
  transport : T,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  self
  .request(transport, self.list_resource_templates_request(cursor?, options~))
  .require_complete(context="resources/templates/list")
}

///|
pub async fn[T : ClientTransport] Client::list_resource_templates(
  self : Client,
  transport : T,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.ListResourceTemplatesResult raise @mcp.McpError {
  @mcp.ListResourceTemplatesResult::from_json(
    self.list_resource_templates_raw(transport, cursor?, options~),
  )
}

///|
pub async fn[T : ClientTransport] Client::read_resource_raw(
  self : Client,
  transport : T,
  uri~ : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.request(transport, self.read_resource_request(uri~, options~))
}

///|
pub async fn[T : ClientTransport] Client::read_resource(
  self : Client,
  transport : T,
  uri~ : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[@mcp.ReadResourceResult] raise @mcp.McpError {
  match self.read_resource_raw(transport, uri~, options~) {
    @mcp.Complete(result) =>
      @mcp.Complete(@mcp.ReadResourceResult::from_json(result))
    @mcp.InputRequired(value) => @mcp.InputRequired(value)
    @mcp.ExtensionResult(result_type, value) =>
      @mcp.ExtensionResult(result_type, value)
  }
}

///|
pub async fn[T : ClientTransport] Client::list_prompts_raw(
  self : Client,
  transport : T,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  self
  .request(transport, self.list_prompts_request(cursor?, options~))
  .require_complete(context="prompts/list")
}

///|
pub async fn[T : ClientTransport] Client::list_prompts(
  self : Client,
  transport : T,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.ListPromptsResult raise @mcp.McpError {
  @mcp.ListPromptsResult::from_json(
    self.list_prompts_raw(transport, cursor?, options~),
  )
}

///|
pub async fn[T : ClientTransport] Client::get_prompt_raw(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.request(transport, self.get_prompt_request(name~, arguments~, options~))
}

///|
pub async fn[T : ClientTransport] Client::get_prompt(
  self : Client,
  transport : T,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[@mcp.GetPromptResult] raise @mcp.McpError {
  match self.get_prompt_raw(transport, name~, arguments~, options~) {
    @mcp.Complete(result) =>
      @mcp.Complete(@mcp.GetPromptResult::from_json(result))
    @mcp.InputRequired(value) => @mcp.InputRequired(value)
    @mcp.ExtensionResult(result_type, value) =>
      @mcp.ExtensionResult(result_type, value)
  }
}

///|
pub async fn[T : ClientTransport] Client::complete_raw(
  self : Client,
  transport : T,
  reference~ : @mcp.CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  let request = self.complete_request(
    reference~,
    argument_name~,
    argument_value~,
    context_arguments?,
    options~,
  )
  self
  .request(transport, request)
  .require_complete(context="completion/complete")
}

///|
pub async fn[T : ClientTransport] Client::complete(
  self : Client,
  transport : T,
  reference~ : @mcp.CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.CompleteResult raise @mcp.McpError {
  @mcp.CompleteResult::from_json(
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
  notifications~ : @mcp.SubscriptionFilter,
  on_notification~ : (Json) -> Unit,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  transport
  .request_with_notifications(
    self.listen_request(notifications~, options~),
    on_notification~,
  )
  .require_complete(context="subscriptions/listen")
}
