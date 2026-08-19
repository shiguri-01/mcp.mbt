///|
fn first_tool_name(result : Json) -> String raise @mcp.McpError {
  guard result
    is Object(
      { "tools": Array([Object({ "name": String(name), .. }), ..]), .. }
    ) else {
    raise @mcp.InvalidRequest("tools/list did not return a tool")
  }
  name
}

///|
fn first_resource_uri(result : Json) -> String raise @mcp.McpError {
  guard result
    is Object(
      { "resources": Array([Object({ "uri": String(uri), .. }), ..]), .. }
    ) else {
    raise @mcp.InvalidRequest("resources/list did not return a resource")
  }
  uri
}

///|
fn first_prompt_name(result : Json) -> String raise @mcp.McpError {
  guard result
    is Object(
      { "prompts": Array([Object({ "name": String(name), .. }), ..]), .. }
    ) else {
    raise @mcp.InvalidRequest("prompts/list did not return a prompt")
  }
  name
}

///|
async fn run_tools_call(
  client : @mcp_client.Client,
) -> Unit raise @mcp.McpError {
  let tools = client.list_tools_raw()
  ignore(
    client.call_tool(
      name=first_tool_name(tools),
      arguments=Json::object({ "a": Json::number(2.0), "b": Json::number(3.0) }),
    ),
  )
}

///|
async fn run_request_metadata(
  client : @mcp_client.Client,
) -> Unit raise @mcp.McpError {
  ignore(client.discover())
  ignore(client.list_tools_raw())
}

///|
async fn run_standard_headers(
  client : @mcp_client.Client,
) -> Unit raise @mcp.McpError {
  let tools = client.list_tools_raw()
  ignore(
    client.call_tool(name=first_tool_name(tools), arguments=Json::object({})),
  )
  let resources = client.list_resources_raw()
  ignore(client.read_resource(uri=first_resource_uri(resources)))
  let prompts = client.list_prompts_raw()
  ignore(
    client.get_prompt(
      name=first_prompt_name(prompts),
      arguments=Json::object({}),
    ),
  )
}

///|
fn conformance_tool_calls() -> Array[(String, Json)] raise @mcp.McpError {
  let raw = match @env.get_env_var("MCP_CONFORMANCE_CONTEXT") {
    Some(value) => value
    None => raise @mcp.InvalidParams("MCP_CONFORMANCE_CONTEXT is required")
  }
  let context : Json = @json.parse(raw) catch {
    error => raise @mcp.InvalidParams(error.to_string())
  }
  guard context is Object({ "toolCalls": Array(calls), .. }) else {
    raise @mcp.InvalidParams(
      "MCP_CONFORMANCE_CONTEXT.toolCalls must be an array",
    )
  }
  let parsed : Array[(String, Json)] = []
  for call in calls {
    guard call
      is Object(
        { "name": String(name), "arguments": Object(_) as arguments, .. }
      ) else {
      raise @mcp.InvalidParams(
        "each MCP_CONFORMANCE_CONTEXT.toolCalls item needs a name and arguments",
      )
    }
    parsed.push((name, arguments))
  }
  parsed
}

///|
async fn run_custom_headers(
  client : @mcp_client.Client,
) -> Unit raise @mcp.McpError {
  ignore(client.list_tools_raw())
  for call in conformance_tool_calls() {
    let (name, arguments) = call
    ignore(client.call_tool(name~, arguments~))
  }
}

///|
async fn run_invalid_tool_headers(
  client : @mcp_client.Client,
) -> Unit raise @mcp.McpError {
  let tools = client.list_tools_raw()
  let name = first_tool_name(tools)
  if name != "valid_tool" {
    raise @mcp.InvalidRequest(
      "the first accepted tool must be valid_tool after schema filtering",
    )
  }
  ignore(
    client.call_tool(
      name~,
      arguments=Json::object({ "region": Json::string("us-east1") }),
    ),
  )
}

///|
async fn run_json_schema_ref_no_deref(
  client : @mcp_client.Client,
) -> Unit raise @mcp.McpError {
  ignore(client.list_tools_raw())
}
