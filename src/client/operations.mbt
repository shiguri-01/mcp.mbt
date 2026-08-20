///|
/// A transport interface for client operations.
pub(open) trait ClientTransport {
  async fn request_with_notifications(
    self : Self,
    request : Json,
    on_notification~ : (Json) -> Unit,
  ) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError
  async fn notify(self : Self, notification : Json) -> Unit raise @mcp.McpError
  fn close(self : Self) -> Unit
}

///|
pub async fn Client::request_with_notifications(
  self : Client,
  request : Json,
  on_notification~ : (Json) -> Unit,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.transport.request_with_notifications(request, on_notification~)
}

///|
pub async fn Client::request(
  self : Client,
  request : Json,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.transport.request_with_notifications(request, on_notification=fn(_) {
    ()
  })
}

///|
pub async fn Client::notify(
  self : Client,
  notification : Json,
) -> Unit raise @mcp.McpError {
  self.transport.notify(notification)
}

///|
pub async fn Client::discover(
  self : Client,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.DiscoverResult raise @mcp.McpError {
  let outcome = self.request(self.discover_request(options~))
  @mcp.DiscoverResult::from_json(
    outcome.require_complete(context="server/discover"),
  )
}

///|

///|
async fn Client::list_tools_raw(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  self
  .request(self.list_tools_request(cursor?, options~))
  .require_complete(context="tools/list")
}

///|
pub async fn Client::list_tools(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.ListToolsResult raise @mcp.McpError {
  @mcp.ListToolsResult::from_json(self.list_tools_raw(cursor?, options~))
}

///|
async fn Client::call_tool_raw(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.request(self.call_tool_request(name~, arguments~, options~))
}

///|

///|
pub async fn Client::call_tool(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve_input? : InputResolver,
) -> @mcp.HandlerOutcome[@mcp.CallToolResult] raise @mcp.McpError {
  match resolve_input {
    Some(resolve) => {
      let result = self.resolve_mrtr(
        request_builder=options => {
          self.call_tool_request(name~, arguments~, options~)
        },
        resolve~,
        options~,
        max_rounds~,
      )
      @mcp.Complete(@mcp.CallToolResult::from_json(result))
    }
    None =>
      match self.call_tool_raw(name~, arguments~, options~) {
        @mcp.Complete(result) =>
          @mcp.Complete(@mcp.CallToolResult::from_json(result))
        @mcp.InputRequired(value) => @mcp.InputRequired(value)
        @mcp.ExtensionResult(result_type, value) =>
          @mcp.ExtensionResult(result_type, value)
      }
  }
}

///|
async fn Client::list_resources_raw(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  self
  .request(self.list_resources_request(cursor?, options~))
  .require_complete(context="resources/list")
}

///|
pub async fn Client::list_resources(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.ListResourcesResult raise @mcp.McpError {
  @mcp.ListResourcesResult::from_json(
    self.list_resources_raw(cursor?, options~),
  )
}

///|
async fn Client::list_resource_templates_raw(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  self
  .request(self.list_resource_templates_request(cursor?, options~))
  .require_complete(context="resources/templates/list")
}

///|
pub async fn Client::list_resource_templates(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.ListResourceTemplatesResult raise @mcp.McpError {
  @mcp.ListResourceTemplatesResult::from_json(
    self.list_resource_templates_raw(cursor?, options~),
  )
}

///|
async fn Client::read_resource_raw(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.request(self.read_resource_request(uri~, options~))
}

///|
pub async fn Client::read_resource(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve_input? : InputResolver,
) -> @mcp.HandlerOutcome[@mcp.ReadResourceResult] raise @mcp.McpError {
  match resolve_input {
    Some(resolve) => {
      let result = self.resolve_mrtr(
        request_builder=options => self.read_resource_request(uri~, options~),
        resolve~,
        options~,
        max_rounds~,
      )
      @mcp.Complete(@mcp.ReadResourceResult::from_json(result))
    }
    None =>
      match self.read_resource_raw(uri~, options~) {
        @mcp.Complete(result) =>
          @mcp.Complete(@mcp.ReadResourceResult::from_json(result))
        @mcp.InputRequired(value) => @mcp.InputRequired(value)
        @mcp.ExtensionResult(result_type, value) =>
          @mcp.ExtensionResult(result_type, value)
      }
  }
}

///|
async fn Client::list_prompts_raw(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  self
  .request(self.list_prompts_request(cursor?, options~))
  .require_complete(context="prompts/list")
}

///|
pub async fn Client::list_prompts(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.ListPromptsResult raise @mcp.McpError {
  @mcp.ListPromptsResult::from_json(self.list_prompts_raw(cursor?, options~))
}

///|
async fn Client::get_prompt_raw(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.request(self.get_prompt_request(name~, arguments~, options~))
}

///|
pub async fn Client::get_prompt(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve_input? : InputResolver,
) -> @mcp.HandlerOutcome[@mcp.GetPromptResult] raise @mcp.McpError {
  match resolve_input {
    Some(resolve) => {
      let result = self.resolve_mrtr(
        request_builder=options => {
          self.get_prompt_request(name~, arguments~, options~)
        },
        resolve~,
        options~,
        max_rounds~,
      )
      @mcp.Complete(@mcp.GetPromptResult::from_json(result))
    }
    None =>
      match self.get_prompt_raw(name~, arguments~, options~) {
        @mcp.Complete(result) =>
          @mcp.Complete(@mcp.GetPromptResult::from_json(result))
        @mcp.InputRequired(value) => @mcp.InputRequired(value)
        @mcp.ExtensionResult(result_type, value) =>
          @mcp.ExtensionResult(result_type, value)
      }
  }
}

///|
async fn Client::complete_raw(
  self : Client,
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
  self.request(request).require_complete(context="completion/complete")
}

///|
pub async fn Client::complete(
  self : Client,
  reference~ : @mcp.CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.CompleteResult raise @mcp.McpError {
  @mcp.CompleteResult::from_json(
    self.complete_raw(
      reference~,
      argument_name~,
      argument_value~,
      context_arguments?,
      options~,
    ),
  )
}

///|
pub async fn Client::listen(
  self : Client,
  notifications~ : @mcp.SubscriptionFilter,
  on_notification~ : (Json) -> Unit,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  self.transport
  .request_with_notifications(
    self.listen_request(notifications~, options~),
    on_notification~,
  )
  .require_complete(context="subscriptions/listen")
}
