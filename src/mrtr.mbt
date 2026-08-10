///|
/// A server-initiated request carried inside an MRTR result. It deliberately
/// omits JSON-RPC framing: keys in `inputRequests` provide correlation.
pub struct InputRequest {
  method_name : String
  params : Json
} derive(Debug, Eq)

///|
pub fn InputRequest::InputRequest(
  method_name~ : String,
  params? : Json = Json::object({}),
) -> InputRequest raise McpError {
  let fields = expect_object(params, "input request params")
  validate_core_input_request(method_name, fields)
  { method_name, params }
}

///|
fn validate_core_input_request(
  method_name : String,
  fields : Map[String, Json],
) -> Unit raise McpError {
  match method_name {
    "elicitation/create" => {
      ignore(get_string(fields, "message", "elicitation/create params"))
      match fields.get("mode") {
        Some(String("url")) =>
          ignore(get_string(fields, "url", "elicitation/create params"))
        Some(String("form")) | None => {
          guard fields.get("requestedSchema") is Some(Object(schema)) else {
            raise InvalidParams(
              "elicitation/create form params.requestedSchema is required",
            )
          }
          guard schema.get("type") == Some(Json::string("object")) &&
            schema.get("properties") is Some(Object(_)) else {
            raise InvalidParams(
              "elicitation/create requestedSchema requires object properties",
            )
          }
        }
        Some(_) =>
          raise InvalidParams("elicitation/create params.mode is invalid")
      }
    }
    "sampling/createMessage" => {
      guard fields.get("messages") is Some(Array(_)) else {
        raise InvalidParams(
          "sampling/createMessage params.messages is required",
        )
      }
      guard fields.get("maxTokens") is Some(Number(value, ..)) && value > 0.0 else {
        raise InvalidParams(
          "sampling/createMessage params.maxTokens must be positive",
        )
      }
    }
    "roots/list" => ()
    _ => () // Explicit extension escape hatch.
  }
}

///|
pub fn InputRequest::method_name(self : InputRequest) -> String {
  self.method_name
}

///|
pub fn InputRequest::params(self : InputRequest) -> Json {
  self.params
}

///|
pub impl ToJson for InputRequest with fn to_json(self : InputRequest) -> Json {
  Json::object({
    "method": Json::string(self.method_name),
    "params": self.params,
  })
}

///|
pub fn parse_input_request(value : Json) -> InputRequest raise McpError {
  let fields = expect_object(value, "input request")
  InputRequest(
    method_name=get_string(fields, "method", "input request"),
    params=match fields.get("params") {
      Some(value) => value
      None => Json::object({})
    },
  )
}

///|
/// A raw client result for a server-initiated input request.
pub struct InputResponse {
  result : Json
} derive(Debug, Eq)

///|
pub fn InputResponse::InputResponse(result : Json) -> InputResponse {
  { result, }
}

///|
pub fn InputResponse::result(self : InputResponse) -> Json {
  self.result
}

///|
pub impl ToJson for InputResponse with fn to_json(self : InputResponse) -> Json {
  self.result
}

///|
pub fn parse_input_responses(
  value : Json,
) -> Map[String, InputResponse] raise McpError {
  let fields = expect_object(value, "inputResponses")
  let responses : Map[String, InputResponse] = Map([])
  for key, result in fields {
    responses[key] = InputResponse(result)
  }
  responses
}

///|
pub struct InputRequiredResult {
  input_requests : Map[String, InputRequest]?
  request_state : String?
  meta : ResultMeta?
} derive(Debug, Eq)

///|
pub fn InputRequiredResult::InputRequiredResult(
  input_requests? : Map[String, InputRequest],
  request_state? : String,
  meta? : ResultMeta,
) -> InputRequiredResult raise McpError {
  let has_requests = match input_requests {
    Some(requests) => !requests.is_empty()
    None => false
  }
  if !has_requests && request_state is None {
    raise InvalidParams(
      "input_required result needs non-empty inputRequests or requestState",
    )
  }
  { input_requests, request_state, meta }
}

///|
pub fn InputRequiredResult::input_requests(
  self : InputRequiredResult,
) -> Map[String, InputRequest]? {
  self.input_requests
}

///|
pub fn InputRequiredResult::request_state(
  self : InputRequiredResult,
) -> String? {
  self.request_state
}

///|
pub fn InputRequiredResult::meta(self : InputRequiredResult) -> ResultMeta? {
  self.meta
}

///|
/// Build retry options while preserving the server's opaque request state.
/// Every requested input must have exactly one response; callers never need to
/// inspect or copy `requestState` themselves.
pub fn InputRequiredResult::retry_options(
  self : InputRequiredResult,
  responses : Map[String, InputResponse],
  base? : RequestOptions = RequestOptions(),
) -> RequestOptions raise McpError {
  match self.input_requests {
    Some(requests) => {
      for key, _ in requests {
        if !responses.contains(key) {
          raise InvalidParams("missing input response: \{key}")
        }
      }
      for key, _ in responses {
        if !requests.contains(key) {
          raise InvalidParams("unexpected input response: \{key}")
        }
      }
      for key, request in requests {
        validate_core_input_response(
          request.method_name(),
          responses[key].result(),
        )
      }
    }
    None if !responses.is_empty() =>
      raise InvalidParams("input_required result did not request responses")
    None => ()
  }
  RequestOptions(
    progress_token?=base.progress_token,
    log_level?=base.log_level,
    input_responses?=if responses.is_empty() { None } else { Some(responses) },
    request_state?=self.request_state,
    meta=base.meta,
  )
}

///|
fn validate_core_input_response(
  method_name : String,
  result : Json,
) -> Unit raise McpError {
  let fields = expect_object(result, "input response")
  match method_name {
    "elicitation/create" =>
      match fields.get("action") {
        Some(String("accept" | "decline" | "cancel")) => ()
        _ => raise InvalidParams("elicitation response.action is invalid")
      }
    "sampling/createMessage" => {
      ignore(get_string(fields, "model", "sampling response"))
      ignore(get_string(fields, "role", "sampling response"))
      guard fields.contains("content") else {
        raise InvalidParams("sampling response.content is required")
      }
    }
    "roots/list" => {
      guard fields.get("roots") is Some(Array(_)) else {
        raise InvalidParams("roots response.roots is required")
      }
    }
    _ => ()
  }
}

///|
pub impl ToJson for InputRequiredResult with fn to_json(
  self : InputRequiredResult,
) -> Json {
  let fields : Map[String, Json] = {
    "resultType": ResultType::InputRequired.to_json(),
  }
  if self.input_requests is Some(requests) {
    let values : Map[String, Json] = Map([])
    for key, request in requests {
      values[key] = request.to_json()
    }
    fields["inputRequests"] = Json::object(values)
  }
  put_optional_string(fields, "requestState", self.request_state)
  if self.meta is Some(value) {
    fields["_meta"] = value.to_json()
  }
  Json::object(fields)
}

///|
pub fn parse_input_required_result(
  value : Json,
) -> InputRequiredResult raise McpError {
  let fields = expect_object(value, "input_required result")
  guard fields.get("resultType") is Some(result_type) &&
    parse_result_type(result_type) == InputRequired else {
    raise InvalidRequest("result.resultType must be 'input_required'")
  }
  InputRequiredResult(
    input_requests?=match fields.get("inputRequests") {
      Some(Object(values)) => {
        let requests : Map[String, InputRequest] = Map([])
        for key, request in values {
          requests[key] = parse_input_request(request)
        }
        Some(requests)
      }
      Some(_) => raise InvalidRequest("result.inputRequests must be an object")
      None => None
    },
    request_state?=get_optional_string(fields, "requestState", "result"),
    meta?=match fields.get("_meta") {
      Some(value) =>
        Some(parse_result_meta(value, "input_required result._meta"))
      None => None
    },
  )
}

///|
/// A typed handler can either finish or ask the client for more input.
pub(all) enum HandlerOutcome[T] {
  Complete(T)
  InputRequired(InputRequiredResult)
  ExtensionResult(String, Json)
}
