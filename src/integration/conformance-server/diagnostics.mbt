///|
fn sampling_capability() -> @mcp.ClientCapabilities {
  @mcp.ClientCapabilities(sampling=@mcp.SamplingCapability())
}

///|
fn register_stateless_diagnostics(server : @mcp_server.ServerBuilder) -> Unit {
  try! server.tool_raw(
    name="test_missing_capability",
    description="Require the client sampling capability.",
    input_schema=empty_object_schema(),
    (context, _arguments) => {
      let capabilities = context.meta.client_capabilities
      if capabilities.sampling is Some(_) {
        @mcp.Complete(@mcp.CallToolResult::text("sampling is available"))
      } else {
        raise @mcp.MissingRequiredClientCapability(
          "sampling capability is required",
          sampling_capability(),
        )
      }
    },
  )
  try! server.tool_raw(
    name="test_streaming_elicitation",
    description="Return an incomplete result on a request-scoped stream.",
    input_schema=empty_object_schema(),
    (context, _arguments) => {
      ignore(context)
      let requests : Map[String, @mcp.InputRequest] = {
        "confirm": elicitation_request(
          "Confirm the streaming conformance request", "confirmed", "boolean",
        ),
      }
      @mcp.InputRequired(@mcp.InputRequiredResult(input_requests=requests))
    },
  )
  try! server.tool_raw(
    name="test_logging_tool",
    description="Return without logging when the request omits logLevel.",
    input_schema=empty_object_schema(),
    fn(_context, _arguments) {
      @mcp.Complete(@mcp.CallToolResult::text("logging test completed"))
    },
  )
  try! server.tool_raw(
    name="test_trigger_prompt_change",
    description="A deterministic no-op because list-changed is not advertised.",
    input_schema=empty_object_schema(),
    fn(_context, _arguments) {
      @mcp.Complete(@mcp.CallToolResult::text("prompt registry unchanged"))
    },
  )
  try! server.tool_raw(
    name="test_trigger_tool_change",
    description="A deterministic no-op because list-changed is not advertised.",
    input_schema=empty_object_schema(),
    fn(_context, _arguments) {
      @mcp.Complete(@mcp.CallToolResult::text("tool registry unchanged"))
    },
  )
}
