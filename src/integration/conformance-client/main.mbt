///|
fn conformance_capabilities() -> @mcp.ClientCapabilities {
  @mcp.ClientCapabilities(
    roots=@mcp.RootsCapability(),
    sampling=@mcp.SamplingCapability(),
    elicitation=@mcp.ElicitationCapability(form=Json::object({})),
  )
}

///|
fn make_client(
  endpoint : String,
  protocol_version : String,
) -> @mcp_http.Client {
  try! @mcp_http.Client(
    endpoint,
    name="moonbit-mcp-conformance-client",
    version="2026.7.28",
    capabilities=conformance_capabilities(),
    supported_protocol_versions=[protocol_version, @mcp.latest_protocol_version],
  )
}

///|
async fn dispatch(
  scenario : String,
  endpoint : String,
  protocol_version : String,
) -> Unit raise @mcp.McpError {
  if scenario.has_prefix("auth/"[:]) {
    return run_auth_scenario(scenario, endpoint, protocol_version)
  }
  let client = make_client(endpoint, protocol_version)
  match scenario {
    "tools_call" | "tools-call" => run_tools_call(client)
    "request-metadata" => run_request_metadata(client)
    "sep-2322-client-request-state" => run_request_state(client)
    "http-standard-headers" => run_standard_headers(client)
    "http-custom-headers" => run_custom_headers(client)
    "http-invalid-tool-headers" => run_invalid_tool_headers(client)
    "json-schema-ref-no-deref" => run_json_schema_ref_no_deref(client)
    _ => abort("Unsupported MCP conformance scenario: \{scenario}")
  }
}

///|
async fn main {
  let arguments = @env.args()
  let scenario = match @env.get_env_var("MCP_CONFORMANCE_SCENARIO") {
    Some(value) => value
    None => abort("MCP_CONFORMANCE_SCENARIO is required")
  }
  let protocol_version = match
    @env.get_env_var("MCP_CONFORMANCE_PROTOCOL_VERSION") {
    Some(value) => value
    None => @mcp.latest_protocol_version
  }
  let endpoint = match arguments.last() {
    Some(value) => value
    None => abort("Usage: conformance-client <server-url>")
  }
  dispatch(scenario, endpoint, protocol_version) catch {
    error => abort("\{Repr(error)}")
  }
}
