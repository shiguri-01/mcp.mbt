///|
pub async fn Client::resolve_mrtr(
  self : Client,
  build : (@mcp.RequestOptions) -> Json raise @mcp.McpError,
  resolve : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
  options : @mcp.RequestOptions,
  rounds_left : Int,
) -> Json raise @mcp.McpError {
  match self.request(build(options)) {
    @mcp.Complete(result) => result
    @mcp.InputRequired(pending) => {
      if rounds_left <= 0 {
        raise @mcp.InvalidRequest("MRTR exceeded max_rounds")
      }
      let requests = pending.input_requests.unwrap_or(Map([]))
      let responses = resolve(requests)
      self.resolve_mrtr(
        build,
        resolve,
        pending.retry_options(responses, base=options),
        rounds_left - 1,
      )
    }
    @mcp.ExtensionResult(_, result) => result
  }
}

///|
pub async fn Client::call_tool_resolving_raw(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> Json raise @mcp.McpError {
  validate_max_rounds(max_rounds)
  self.resolve_mrtr(
    options => self.call_tool_request(name~, arguments~, options~),
    resolve,
    options,
    max_rounds,
  )
}

///|
pub async fn Client::call_tool_resolving(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> @mcp.CallToolResult raise @mcp.McpError {
  @mcp.CallToolResult::from_json(
    self.call_tool_resolving_raw(
      name~,
      arguments~,
      options~,
      max_rounds~,
      resolve~,
    ),
  )
}

///|
pub async fn Client::read_resource_resolving_raw(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> Json raise @mcp.McpError {
  validate_max_rounds(max_rounds)
  self.resolve_mrtr(
    options => self.read_resource_request(uri~, options~),
    resolve,
    options,
    max_rounds,
  )
}

///|
pub async fn Client::read_resource_resolving(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> @mcp.ReadResourceResult raise @mcp.McpError {
  @mcp.ReadResourceResult::from_json(
    self.read_resource_resolving_raw(uri~, options~, max_rounds~, resolve~),
  )
}

///|
pub async fn Client::get_prompt_resolving_raw(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> Json raise @mcp.McpError {
  validate_max_rounds(max_rounds)
  self.resolve_mrtr(
    options => self.get_prompt_request(name~, arguments~, options~),
    resolve,
    options,
    max_rounds,
  )
}

///|
pub async fn Client::get_prompt_resolving(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> @mcp.GetPromptResult raise @mcp.McpError {
  @mcp.GetPromptResult::from_json(
    self.get_prompt_resolving_raw(
      name~,
      arguments~,
      options~,
      max_rounds~,
      resolve~,
    ),
  )
}
