///|
pub async fn[T : ClientTransport] Client::resolve_mrtr(
  self : Client,
  transport : T,
  build : (@mcp.RequestOptions) -> Json raise @mcp.McpError,
  resolve : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
  options : @mcp.RequestOptions,
  rounds_left : Int,
) -> Json raise @mcp.McpError {
  match self.request(transport, build(options)) {
    @mcp.Complete(result) => result
    @mcp.InputRequired(pending) => {
      if rounds_left <= 0 {
        raise @mcp.InvalidRequest("MRTR exceeded max_rounds")
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
    @mcp.ExtensionResult(_, result) => result
  }
}

///|
pub async fn[T : ClientTransport] Client::call_tool_resolving_raw(
  self : Client,
  transport : T,
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
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> @mcp.CallToolResult raise @mcp.McpError {
  @mcp.CallToolResult::from_json(
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
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> Json raise @mcp.McpError {
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
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> @mcp.ReadResourceResult raise @mcp.McpError {
  @mcp.ReadResourceResult::from_json(
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
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> Json raise @mcp.McpError {
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
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> @mcp.GetPromptResult raise @mcp.McpError {
  @mcp.GetPromptResult::from_json(
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
