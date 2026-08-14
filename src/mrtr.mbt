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
            schema.get("properties") is Some(Object(properties)) else {
            raise InvalidParams(
              "elicitation/create requestedSchema requires object properties",
            )
          }
          for _, property_schema in properties {
            validate_elicitation_primitive_schema(property_schema)
          }
          ignore(compile_mrtr_schema(Json::object(schema)))
        }
        Some(_) =>
          raise InvalidParams("elicitation/create params.mode is invalid")
      }
    }
    "sampling/createMessage" => {
      guard fields.get("messages") is Some(Array(messages)) else {
        raise InvalidParams(
          "sampling/createMessage params.messages must be an array",
        )
      }
      for message in messages {
        let item = expect_object(message, "sampling message")
        match item.get("role") {
          Some(String("user" | "assistant")) => ()
          _ => raise InvalidParams("sampling message.role is invalid")
        }
        guard item.get("content") is Some(content) else {
          raise InvalidParams("sampling message.content is required")
        }
        validate_sampling_content(content)
      }
      guard fields.get("maxTokens") is Some(Number(_)) else {
        raise InvalidParams(
          "sampling/createMessage params.maxTokens is required",
        )
      }
    }
    "roots/list" => ()
    _ => () // Explicit extension escape hatch.
  }
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
          request.method_name,
          request.params,
          responses[key].result,
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
  request_params : Json,
  result : Json,
) -> Unit raise McpError {
  let fields = expect_object(result, "input response")
  match method_name {
    "elicitation/create" =>
      match fields.get("action") {
        Some(String("accept")) => {
          let request = expect_object(request_params, "elicitation request")
          if request.get("mode") is Some(String("url")) {
            ()
          } else {
            guard fields.get("content") is Some(content) else {
              raise InvalidParams(
                "accepted form elicitation response.content is required",
              )
            }
            let request_schema = match request.get("requestedSchema") {
              Some(value) => value
              None =>
                raise InvalidParams(
                  "elicitation request.requestedSchema is required",
                )
            }
            let validator = compile_mrtr_schema(request_schema)
            let validation = validator.validate(content)
            if !validation.valid {
              let error = validation.errors.to_json().stringify()
              raise InvalidParams(
                "elicitation response.content does not match requestedSchema: \{error}",
              )
            }
          }
        }
        Some(String("decline" | "cancel")) => ()
        _ => raise InvalidParams("elicitation response.action is invalid")
      }
    "sampling/createMessage" => {
      ignore(get_string(fields, "model", "sampling response"))
      guard fields.get("role") is Some(String("user" | "assistant")) else {
        raise InvalidParams("sampling response.role is invalid")
      }
      guard fields.get("content") is Some(content) else {
        raise InvalidParams("sampling response.content is required")
      }
      validate_sampling_content(content)
    }
    "roots/list" => {
      guard fields.get("roots") is Some(Array(roots)) else {
        raise InvalidParams("roots response.roots is required")
      }
      for root in roots {
        let item = expect_object(root, "roots response root")
        ignore(get_string(item, "uri", "roots response root"))
        ignore(get_optional_string(item, "name", "roots response root"))
      }
    }
    _ => ()
  }
}

///|
/// Compile an MRTR request schema through the independent JSON Schema package.
fn compile_mrtr_schema(value : Json) -> @schema.CompiledSchema raise McpError {
  let document = @schema.Document(value) catch {
    _ => raise InvalidParams("MRTR requestedSchema is not a valid JSON Schema")
  }
  document.compile() catch {
    _ => raise InvalidParams("MRTR requestedSchema is not compilable")
  }
}

///|
fn validate_sampling_content(value : Json) -> Unit raise McpError {
  let validate_one = fn(content : Json) -> Unit raise McpError {
    let fields = expect_object(content, "sampling content")
    match fields.get("type") {
      Some(String("text")) =>
        ignore(get_string(fields, "text", "sampling text content"))
      Some(String("image" | "audio")) => {
        ignore(get_string(fields, "data", "sampling media content"))
        ignore(get_string(fields, "mimeType", "sampling media content"))
      }
      Some(String("tool_use")) => {
        ignore(get_string(fields, "id", "sampling tool use content"))
        ignore(get_string(fields, "name", "sampling tool use content"))
        guard fields.get("input") is Some(Object(_)) else {
          raise InvalidParams("sampling tool use input must be an object")
        }
      }
      Some(String("tool_result")) => {
        ignore(get_string(fields, "toolUseId", "sampling tool result content"))
        guard fields.get("content") is Some(Array(contents)) else {
          raise InvalidParams("sampling tool result content must be an array")
        }
        for content in contents {
          validate_sampling_tool_result_content(content)
        }
      }
      Some(String(_)) => raise InvalidParams("sampling content.type is invalid")
      _ => raise InvalidParams("sampling content.type is required")
    }
  }
  match value {
    Array(values) if !values.is_empty() =>
      for content in values {
        validate_one(content)
      }
    Object(_) => validate_one(value)
    _ => raise InvalidParams("sampling content must be an object or array")
  }
}

///|
fn validate_sampling_tool_result_content(value : Json) -> Unit raise McpError {
  let fields = expect_object(value, "sampling tool result content block")
  match fields.get("type") {
    Some(String("text")) =>
      ignore(get_string(fields, "text", "sampling tool result text"))
    Some(String("image" | "audio")) => {
      ignore(get_string(fields, "data", "sampling tool result media"))
      ignore(get_string(fields, "mimeType", "sampling tool result media"))
    }
    Some(String("resource_link")) => {
      ignore(get_string(fields, "uri", "sampling resource link"))
      ignore(get_string(fields, "name", "sampling resource link"))
    }
    Some(String("resource")) => {
      guard fields.get("resource") is Some(Object(resource)) else {
        raise InvalidParams("sampling embedded resource is required")
      }
      ignore(get_string(resource, "uri", "sampling embedded resource"))
      guard resource.get("text") is Some(String(_)) ||
        resource.get("blob") is Some(String(_)) else {
        raise InvalidParams("sampling embedded resource requires text or blob")
      }
    }
    _ => raise InvalidParams("sampling tool result content type is invalid")
  }
}

///|
fn validate_elicitation_primitive_schema(value : Json) -> Unit raise McpError {
  let fields = expect_object(value, "elicitation primitive schema")
  match fields.get("type") {
    Some(String("string" | "number" | "integer" | "boolean")) => ()
    Some(String("array")) => {
      let items = match fields.get("items") {
        Some(value) => expect_object(value, "elicitation enum items")
        None =>
          raise InvalidParams("elicitation array schema.items is required")
      }
      guard items.get("type") == Some(Json::string("string")) else {
        raise InvalidParams("elicitation array schema items must be strings")
      }
      guard items.get("enum") is Some(Array(_)) ||
        items.get("anyOf") is Some(Array(_)) else {
        raise InvalidParams(
          "elicitation array schema items require enum options",
        )
      }
    }
    _ =>
      raise InvalidParams("elicitation properties must use primitive schemas")
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
