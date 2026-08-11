///|
fn accept_elicitation_requests(
  requests : Map[String, @mcp.InputRequest],
) -> Map[String, @mcp.InputResponse] raise @mcp.McpError {
  let responses : Map[String, @mcp.InputResponse] = Map([])
  for key, request in requests {
    if request.method_name() != "elicitation/create" {
      raise @mcp.InvalidRequest(
        "request-state fixture only supports elicitation/create",
      )
    }
    responses[key] = @mcp.InputResponse(
      Json::object({
        "action": Json::string("accept"),
        "content": Json::object({ "confirmed": Json::boolean(true) }),
      }),
    )
  }
  responses
}

///|
async fn complete_echo_state_round(
  client : @mcp_http.Client,
) -> Unit raise @mcp.McpError {
  match client.call_tool(name="test_mrtr_echo_state") {
    @mcp.InputRequired(required) => {
      ignore(client.call_tool(name="test_mrtr_unrelated"))
      let requests = required.input_requests().unwrap_or(Map([]))
      let options = required.retry_options(
        accept_elicitation_requests(requests),
      )
      guard client.call_tool(name="test_mrtr_echo_state", options~)
        is @mcp.Complete(_) else {
        raise @mcp.InvalidRequest("requestState retry did not complete")
      }
    }
    _ => raise @mcp.InvalidRequest("echo-state tool did not require input")
  }
}

///|
async fn complete_no_state_round(
  client : @mcp_http.Client,
) -> Unit raise @mcp.McpError {
  match client.call_tool(name="test_mrtr_no_state") {
    @mcp.InputRequired(required) => {
      let requests = required.input_requests().unwrap_or(Map([]))
      let options = required.retry_options(
        accept_elicitation_requests(requests),
      )
      guard client.call_tool(name="test_mrtr_no_state", options~)
        is @mcp.Complete(_) else {
        raise @mcp.InvalidRequest("no-state retry did not complete")
      }
    }
    _ => raise @mcp.InvalidRequest("no-state tool did not require input")
  }
}

///|
async fn run_request_state(
  client : @mcp_http.Client,
) -> Unit raise @mcp.McpError {
  ignore(client.list_tools_raw())
  complete_echo_state_round(client)
  complete_no_state_round(client)
  guard client.call_tool(name="test_mrtr_no_result_type") is @mcp.Complete(_) else {
    raise @mcp.InvalidRequest("missing resultType was not treated as complete")
  }
}
