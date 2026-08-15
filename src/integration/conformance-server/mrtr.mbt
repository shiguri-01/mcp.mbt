///|
fn elicitation_request(
  message : String,
  field : String,
  field_type : String,
) -> @mcp.InputRequest {
  let properties : Map[String, Json] = Map([])
  properties[field] = Json::object({ "type": Json::string(field_type) })
  try! @mcp.InputRequest(
    method_name="elicitation/create",
    params=Json::object({
      "message": Json::string(message),
      "requestedSchema": Json::object({
        "type": Json::string("object"),
        "properties": Json::object(properties),
        "required": [field].to_json(),
      }),
    }),
  )
}

///|
fn sampling_request() -> @mcp.InputRequest {
  try! @mcp.InputRequest(
    method_name="sampling/createMessage",
    params=Json::object({
      "messages": [
        Json::object({
          "role": Json::string("user"),
          "content": Json::object({
            "type": Json::string("text"),
            "text": Json::string("What is the capital of France?"),
          }),
        }),
      ].to_json(),
      "maxTokens": Json::number(100.0),
    }),
  )
}

///|
fn roots_request() -> @mcp.InputRequest {
  try! @mcp.InputRequest(method_name="roots/list", params=Json::object({}))
}

///|
fn has_response(context : @mcp.RequestContext, key : String) -> Bool {
  match context.input_responses {
    Some(responses) => responses.contains(key)
    None => false
  }
}

///|
fn complete_text(text : String) -> @mcp.HandlerOutcome[@mcp.CallToolResult] {
  @mcp.Complete(@mcp.CallToolResult::text(text))
}

///|
fn register_mrtr_fixtures(server : @mcp_server.Server) -> Unit {
  try! server.tool_raw(
    name="test_input_required_result_elicitation",
    description="Request one elicitation response and complete when it is supplied.",
    input_schema=empty_object_schema(),
    (context, _arguments) => {
      if has_response(context, "user_name") {
        complete_text("Hello, Alice!")
      } else {
        @mcp.InputRequired(
          @mcp.InputRequiredResult(input_requests={
            "user_name": elicitation_request(
              "What is your name?", "name", "string",
            ),
          }),
        )
      }
    },
  )
  try! server.tool_raw(
    name="test_input_required_result_sampling",
    description="Request one sampling response and complete on retry.",
    input_schema=empty_object_schema(),
    (context, _arguments) => {
      if has_response(context, "capital_question") {
        complete_text("The capital response was received.")
      } else {
        @mcp.InputRequired(
          @mcp.InputRequiredResult(input_requests={
            "capital_question": sampling_request(),
          }),
        )
      }
    },
  )
  try! server.tool_raw(
    name="test_input_required_result_list_roots",
    description="Request the client's roots and complete on retry.",
    input_schema=empty_object_schema(),
    (context, _arguments) => {
      if has_response(context, "client_roots") {
        complete_text("Client roots were received.")
      } else {
        @mcp.InputRequired(
          @mcp.InputRequiredResult(input_requests={
            "client_roots": roots_request(),
          }),
        )
      }
    },
  )
  try! server.tool_raw(
    name="test_input_required_result_request_state",
    description="Require an exact opaque requestState echo.",
    input_schema=empty_object_schema(),
    (context, _arguments) => {
      if context.input_responses is Some(_) {
        if context.request_state != Some("request-state-v1") {
          raise @mcp.InvalidParams("requestState integrity check failed")
        }
        complete_text("state-ok")
      } else {
        @mcp.InputRequired(
          @mcp.InputRequiredResult(
            input_requests={
              "confirm": elicitation_request("Please confirm", "ok", "boolean"),
            },
            request_state="request-state-v1",
          ),
        )
      }
    },
  )
  register_multiple_and_round_mrtr(server)
  register_capability_and_tamper_mrtr(server)
  register_prompt_mrtr(server)
}

///|
fn register_multiple_and_round_mrtr(server : @mcp_server.Server) -> Unit {
  try! server.tool_raw(
    name="test_input_required_result_multiple_inputs",
    description="Request elicitation, sampling, and roots in one result.",
    input_schema=empty_object_schema(),
    (context, _arguments) => {
      let all_present = has_response(context, "user_name") &&
        has_response(context, "greeting") &&
        has_response(context, "client_roots")
      if all_present {
        if context.request_state != Some("multiple-state-v1") {
          raise @mcp.InvalidParams("requestState integrity check failed")
        }
        complete_text("All input responses were received.")
      } else {
        @mcp.InputRequired(
          @mcp.InputRequiredResult(
            input_requests={
              "user_name": elicitation_request(
                "What is your name?", "name", "string",
              ),
              "greeting": sampling_request(),
              "client_roots": roots_request(),
            },
            request_state="multiple-state-v1",
          ),
        )
      }
    },
  )
  try! server.tool_raw(
    name="test_input_required_result_multi_round",
    description="Return two input-required rounds with distinct requestState values.",
    input_schema=empty_object_schema(),
    (context, _arguments) => {
      match context.request_state {
        None =>
          @mcp.InputRequired(
            @mcp.InputRequiredResult(
              input_requests={
                "step1": elicitation_request(
                  "Step 1: What is your name?", "name", "string",
                ),
              },
              request_state="round-state-1",
            ),
          )
        Some("round-state-1") => {
          if !has_response(context, "step1") {
            raise @mcp.InvalidParams("step1 response is required")
          }
          @mcp.InputRequired(
            @mcp.InputRequiredResult(
              input_requests={
                "step2": elicitation_request(
                  "Step 2: What is your favorite color?", "color", "string",
                ),
              },
              request_state="round-state-2",
            ),
          )
        }
        Some("round-state-2") =>
          if has_response(context, "step2") {
            complete_text("Multi-round input completed.")
          } else {
            raise @mcp.InvalidParams("step2 response is required")
          }
        Some(_) =>
          raise @mcp.InvalidParams("requestState integrity check failed")
      }
    },
  )
}

///|
fn register_capability_and_tamper_mrtr(server : @mcp_server.Server) -> Unit {
  try! server.tool_raw(
    name="test_input_required_result_tampered_state",
    description="Reject any requestState other than the issued opaque value.",
    input_schema=empty_object_schema(),
    (context, _arguments) => {
      match context.request_state {
        None =>
          @mcp.InputRequired(
            @mcp.InputRequiredResult(
              input_requests={
                "confirm": elicitation_request(
                  "Confirm the request", "ok", "boolean",
                ),
              },
              request_state="signed-state-fixture-v1",
            ),
          )
        Some("signed-state-fixture-v1") => complete_text("state accepted")
        Some(_) =>
          raise @mcp.InvalidParams("requestState integrity check failed")
      }
    },
  )
  try! server.tool_raw(
    name="test_input_required_result_capabilities",
    description="Only request input methods declared by the client.",
    input_schema=empty_object_schema(),
    (context, _arguments) => {
      let capabilities = context.meta.client_capabilities
      let requests : Map[String, @mcp.InputRequest] = Map([])
      if capabilities.sampling is Some(_) {
        requests["capital_question"] = sampling_request()
      }
      if capabilities.elicitation is Some(_) {
        requests["confirm"] = elicitation_request(
          "Confirm the request", "ok", "boolean",
        )
      }
      if requests.is_empty() {
        complete_text("No declared input capability is available.")
      } else {
        @mcp.InputRequired(@mcp.InputRequiredResult(input_requests=requests))
      }
    },
  )
}

///|
fn register_prompt_mrtr(server : @mcp_server.Server) -> Unit {
  try! server.prompt(
    name="test_input_required_result_prompt",
    description="Request elicitation before constructing a prompt.",
    (context, _arguments) => {
      if has_response(context, "user_context") {
        @mcp.Complete(
          @mcp.GetPromptResult::user("Prompt context was received."),
        )
      } else {
        @mcp.InputRequired(
          @mcp.InputRequiredResult(input_requests={
            "user_context": elicitation_request(
              "What context should the prompt use?", "context", "string",
            ),
          }),
        )
      }
    },
  )
}
