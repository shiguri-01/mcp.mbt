///|
/// Callback for resolving pending input requests during an MRTR loop.
pub type InputResolver = async (Map[String, @mcp.InputRequest]) -> Map[
  String,
  @mcp.InputResponse,
] raise @mcp.McpError

///|
/// Function that builds a JSON-RPC request with updated request options.
pub type RequestBuilder = (@mcp.RequestOptions) -> Json raise @mcp.McpError

///|
/// Executes an MRTR (Multi-Round Tool Resolution) loop until a terminal response
/// is reached or the maximum round count is exhausted.
pub async fn Client::resolve_mrtr(
  self : Client,
  request_builder~ : RequestBuilder,
  resolve~ : InputResolver,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
) -> Json raise @mcp.McpError {
  validate_max_rounds(max_rounds)
  self.do_resolve_mrtr(request_builder, resolve, options, max_rounds)
}

///|
async fn Client::do_resolve_mrtr(
  self : Client,
  request_builder : RequestBuilder,
  resolve : InputResolver,
  options : @mcp.RequestOptions,
  rounds_left : Int,
) -> Json raise @mcp.McpError {
  match self.request(request_builder(options)) {
    @mcp.Complete(result) => result
    @mcp.InputRequired(pending) => {
      if rounds_left <= 0 {
        raise @mcp.InvalidRequest("MRTR exceeded max_rounds")
      }
      let requests = pending.input_requests.unwrap_or(Map([]))
      let responses = resolve(requests)
      self.do_resolve_mrtr(
        request_builder,
        resolve,
        pending.retry_options(responses, base=options),
        rounds_left - 1,
      )
    }
    @mcp.ExtensionResult(_, result) => result
  }
}
