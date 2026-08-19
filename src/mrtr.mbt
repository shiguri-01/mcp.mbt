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
  guard params is Object(fields) else {
    raise InvalidParams("input request params must be an object")
  }
  validate_core_input_request(method_name, fields)
  { method_name, params }
}

///|
pub(all) enum SamplingContentBlock {
  Text(text~ : String)
  Image(data~ : String, mime_type~ : String)
  Audio(data~ : String, mime_type~ : String)
  ToolUse(id~ : String, name~ : String, input~ : Map[String, Json])
  ToolResult(tool_use_id~ : String, content~ : Array[Content])
} derive(Debug, Eq)

///|
pub impl @json.FromJson for SamplingContentBlock with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> SamplingContentBlock raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  match fields.get("type") {
    Some(String("text")) =>
      match fields.get("text") {
        Some(String(text)) => Text(text~)
        Some(_) =>
          raise JsonDecodeError((path.add_key("text"), "expected string"))
        None =>
          raise JsonDecodeError((path.add_key("text"), "text is required"))
      }
    Some(String("image")) => {
      let data = match fields.get("data") {
        Some(String(d)) => d
        Some(_) =>
          raise JsonDecodeError((path.add_key("data"), "expected string"))
        None =>
          raise JsonDecodeError((path.add_key("data"), "data is required"))
      }
      let mime_type = match fields.get("mimeType") {
        Some(String(m)) => m
        Some(_) =>
          raise JsonDecodeError((path.add_key("mimeType"), "expected string"))
        None =>
          raise JsonDecodeError(
            (path.add_key("mimeType"), "mimeType is required"),
          )
      }
      Image(data~, mime_type~)
    }
    Some(String("audio")) => {
      let data = match fields.get("data") {
        Some(String(d)) => d
        Some(_) =>
          raise JsonDecodeError((path.add_key("data"), "expected string"))
        None =>
          raise JsonDecodeError((path.add_key("data"), "data is required"))
      }
      let mime_type = match fields.get("mimeType") {
        Some(String(m)) => m
        Some(_) =>
          raise JsonDecodeError((path.add_key("mimeType"), "expected string"))
        None =>
          raise JsonDecodeError(
            (path.add_key("mimeType"), "mimeType is required"),
          )
      }
      Audio(data~, mime_type~)
    }
    Some(String("tool_use")) => {
      let id = match fields.get("id") {
        Some(String(i)) => i
        Some(_) =>
          raise JsonDecodeError((path.add_key("id"), "expected string"))
        None => raise JsonDecodeError((path.add_key("id"), "id is required"))
      }
      let name = match fields.get("name") {
        Some(String(n)) => n
        Some(_) =>
          raise JsonDecodeError((path.add_key("name"), "expected string"))
        None =>
          raise JsonDecodeError((path.add_key("name"), "name is required"))
      }
      let input = match fields.get("input") {
        Some(Object(inp)) => inp
        Some(_) =>
          raise JsonDecodeError((path.add_key("input"), "expected object"))
        None =>
          raise JsonDecodeError((path.add_key("input"), "input is required"))
      }
      ToolUse(id~, name~, input~)
    }
    Some(String("tool_result")) => {
      let tool_use_id = match fields.get("toolUseId") {
        Some(String(id)) => id
        Some(_) =>
          raise JsonDecodeError((path.add_key("toolUseId"), "expected string"))
        None =>
          raise JsonDecodeError(
            (path.add_key("toolUseId"), "toolUseId is required"),
          )
      }
      let contents : Array[Content] = match fields.get("content") {
        Some(Array(arr)) => {
          let result : Array[Content] = []
          for i, it in arr {
            result.push(
              @json.from_json(it, path=path.add_key("content").add_index(i)),
            )
          }
          result
        }
        Some(_) =>
          raise JsonDecodeError((path.add_key("content"), "expected array"))
        None =>
          raise JsonDecodeError(
            (path.add_key("content"), "content is required"),
          )
      }
      ToolResult(tool_use_id~, content=contents)
    }
    Some(String(other)) =>
      raise JsonDecodeError(
        (path.add_key("type"), "unknown sampling content type: \{other}"),
      )
    Some(_) => raise JsonDecodeError((path.add_key("type"), "expected string"))
    None => raise JsonDecodeError((path.add_key("type"), "type is required"))
  }
}

///|
pub fn SamplingContentBlock::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> SamplingContentBlock raise McpError {
  decode_json(value, path?)
}

///|
pub impl ToJson for SamplingContentBlock with fn to_json(
  self : SamplingContentBlock,
) -> Json {
  match self {
    Text(text~) =>
      Json::object({ "type": Json::string("text"), "text": Json::string(text) })
    Image(data~, mime_type~) =>
      Json::object({
        "type": Json::string("image"),
        "data": Json::string(data),
        "mimeType": Json::string(mime_type),
      })
    Audio(data~, mime_type~) =>
      Json::object({
        "type": Json::string("audio"),
        "data": Json::string(data),
        "mimeType": Json::string(mime_type),
      })
    ToolUse(id~, name~, input~) =>
      Json::object({
        "type": Json::string("tool_use"),
        "id": Json::string(id),
        "name": Json::string(name),
        "input": Json::object(input),
      })
    ToolResult(tool_use_id~, content~) =>
      Json::object({
        "type": Json::string("tool_result"),
        "toolUseId": Json::string(tool_use_id),
        "content": Json::array(content.map(fn(c) { c.to_json() })),
      })
  }
}

///|
pub(all) enum SamplingContent {
  Single(SamplingContentBlock)
  Multiple(Array[SamplingContentBlock])
} derive(Debug, Eq)

///|
pub impl @json.FromJson for SamplingContent with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> SamplingContent raise {
  match value {
    Array(values) if !values.is_empty() => {
      let blocks : Array[SamplingContentBlock] = []
      for i, item in values {
        blocks.push(@json.from_json(item, path=path.add_index(i)))
      }
      Multiple(blocks)
    }
    Object(_) => Single(@json.from_json(value, path~))
    _ => raise JsonDecodeError((path, "expected object or array"))
  }
}

///|
pub fn SamplingContent::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> SamplingContent raise McpError {
  decode_json(value, path?)
}

///|
pub impl ToJson for SamplingContent with fn to_json(self : SamplingContent) -> Json {
  match self {
    Single(block) => block.to_json()
    Multiple(blocks) => Json::array(blocks.map(fn(b) { b.to_json() }))
  }
}

///|
pub struct SamplingMessage {
  role : Role
  content : SamplingContent
} derive(Debug, Eq)

///|
pub impl @json.FromJson for SamplingMessage with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> SamplingMessage raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  guard fields.get("role") is Some(role_val) else {
    raise JsonDecodeError((path.add_key("role"), "role is required"))
  }
  let role : Role = @json.from_json(role_val, path=path.add_key("role"))
  guard fields.get("content") is Some(content_val) else {
    raise JsonDecodeError((path.add_key("content"), "content is required"))
  }
  let content : SamplingContent = @json.from_json(
    content_val,
    path=path.add_key("content"),
  )
  { role, content }
}

///|
pub fn SamplingMessage::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> SamplingMessage raise McpError {
  decode_json(value, path?)
}

///|
pub impl ToJson for SamplingMessage with fn to_json(self : SamplingMessage) -> Json {
  Json::object({
    "role": self.role.to_json(),
    "content": self.content.to_json(),
  })
}

///|
pub struct SamplingCreateMessageParams {
  messages : Array[SamplingMessage]
  max_tokens : Double
} derive(Debug, Eq)

///|
pub fn SamplingCreateMessageParams::from_json(
  fields : Map[String, Json],
) -> SamplingCreateMessageParams raise McpError {
  match fields {
    { "messages": Array(messages_arr), "maxTokens": Number(max_tokens, ..), .. } => {
      let messages : Array[SamplingMessage] = []
      for message_json in messages_arr {
        messages.push(SamplingMessage::from_json(message_json))
      }
      { messages, max_tokens }
    }
    { "messages": Array(_), .. } =>
      raise InvalidParams("sampling/createMessage params.maxTokens is required")
    _ =>
      raise InvalidParams(
        "sampling/createMessage params.messages must be an array",
      )
  }
}

///|
pub struct SamplingCreateMessageResult {
  model : String
  role : Role
  content : SamplingContent
} derive(Debug, Eq)

///|
pub fn SamplingCreateMessageResult::from_json(
  fields : Map[String, Json],
) -> SamplingCreateMessageResult raise McpError {
  match fields {
    {
      "model": String(model),
      "role": String("user"),
      "content": content_val,
      ..
    } => {
      let content = SamplingContent::from_json(content_val)
      { model, role: Role::User, content }
    }
    {
      "model": String(model),
      "role": String("assistant"),
      "content": content_val,
      ..
    } => {
      let content = SamplingContent::from_json(content_val)
      { model, role: Role::Assistant, content }
    }
    { "model": String(_), "role": String("user" | "assistant"), .. } =>
      raise InvalidParams("sampling response.content is required")
    { "model": String(_), .. } =>
      raise InvalidParams("sampling response.role is invalid")
    _ => raise InvalidParams("sampling response.model is required")
  }
}

///|
pub(all) enum ElicitationPrimitiveType {
  String
  Number
  Integer
  Boolean
  Enum(Array[String])
} derive(Debug, Eq)

///|
pub struct ElicitationPrimitiveSchema {
  schema_type : ElicitationPrimitiveType
  raw : Json
} derive(Debug, Eq)

///|
pub fn ElicitationPrimitiveSchema::from_json(
  value : Json,
) -> ElicitationPrimitiveSchema raise McpError {
  match value {
    Object({ "type": String("string"), .. }) =>
      { schema_type: String, raw: value }
    Object({ "type": String("number"), .. }) =>
      { schema_type: Number, raw: value }
    Object({ "type": String("integer"), .. }) =>
      { schema_type: Integer, raw: value }
    Object({ "type": String("boolean"), .. }) =>
      { schema_type: Boolean, raw: value }
    Object(
      {
        "type": String("array"),
        "items": Object({ "type": String("string"), "enum": Array(arr), .. }),
        ..
      }
    ) => {
      let strings : Array[String] = []
      for it in arr {
        if it is String(s) {
          strings.push(s)
        }
      }
      { schema_type: Enum(strings), raw: value }
    }
    Object(
      {
        "type": String("array"),
        "items": Object({ "type": String("string"), "anyOf": Array(arr), .. }),
        ..
      }
    ) => {
      let strings : Array[String] = []
      for it in arr {
        if it is String(s) {
          strings.push(s)
        }
      }
      { schema_type: Enum(strings), raw: value }
    }
    Object(
      {
        "type": String("array"),
        "items": Object({ "type": String("string"), .. }),
        ..
      }
    ) =>
      raise InvalidParams("elicitation array schema items require enum options")
    Object({ "type": String("array"), "items": Object(_), .. }) =>
      raise InvalidParams("elicitation array schema items must be strings")
    Object({ "type": String("array"), "items": _, .. }) =>
      raise InvalidParams("elicitation enum items must be an object")
    Object({ "type": String("array"), .. }) =>
      raise InvalidParams("elicitation array schema.items is required")
    Object(_) =>
      raise InvalidParams("elicitation properties must use primitive schemas")
    _ => raise InvalidParams("elicitation primitive schema must be an object")
  }
}

///|
pub(all) enum ElicitationMode {
  Url(String)
  Form(
    requested_schema~ : Json,
    properties~ : Map[String, ElicitationPrimitiveSchema],
    compiled_schema~ : @schema.Schema
  )
} derive(Debug)

///|
pub struct ElicitationCreateParams {
  message : String
  mode : ElicitationMode
} derive(Debug)

///|
pub fn ElicitationCreateParams::from_json(
  fields : Map[String, Json],
) -> ElicitationCreateParams raise McpError {
  guard fields is { "message": String(message), .. } else {
    raise InvalidParams("elicitation/create params.message is required")
  }
  let parse_form = fn() -> ElicitationMode raise McpError {
    guard fields
      is {
        "requestedSchema": Object(
          { "type": String("object"), "properties": Object(properties_map), .. } as schema
        ),
        ..
      } else {
      guard fields is { "requestedSchema": Object(_), .. } else {
        raise InvalidParams(
          "elicitation/create form params.requestedSchema is required",
        )
      }
      raise InvalidParams(
        "elicitation/create requestedSchema requires object properties",
      )
    }
    let properties : Map[String, ElicitationPrimitiveSchema] = Map([])
    for key, property_schema in properties_map {
      properties[key] = ElicitationPrimitiveSchema::from_json(property_schema)
    }
    let compiled_schema = compile_mrtr_schema(Json::object(schema))
    ElicitationMode::Form(
      requested_schema=Json::object(schema),
      properties~,
      compiled_schema~,
    )
  }
  let mode = match fields {
    { "mode": String("url"), "url": String(url), .. } =>
      ElicitationMode::Url(url)
    { "mode": String("url"), .. } =>
      raise InvalidParams("elicitation/create params.url is required")
    { "mode": String("form"), .. } => parse_form()
    { "mode": String(_), .. } =>
      raise InvalidParams("elicitation/create params.mode is invalid")
    { "mode": _, .. } =>
      raise InvalidParams("elicitation/create params.mode is invalid")
    _ => parse_form()
  }
  { message, mode }
}

///|
pub(all) enum ElicitationAction {
  Accept
  Decline
  Cancel
} derive(Debug, Eq)

///|
pub struct ElicitationCreateResult {
  action : ElicitationAction
  content : Json?
} derive(Debug, Eq)

///|
pub fn ElicitationCreateResult::from_json(
  fields : Map[String, Json],
  request_params : Json,
) -> ElicitationCreateResult raise McpError {
  let action = match fields {
    { "action": String("accept"), .. } => ElicitationAction::Accept
    { "action": String("decline"), .. } => ElicitationAction::Decline
    { "action": String("cancel"), .. } => ElicitationAction::Cancel
    _ => raise InvalidParams("elicitation response.action is invalid")
  }
  let content = fields.get("content")
  if action == Accept {
    guard request_params is Object(request) else {
      raise InvalidParams("elicitation request must be an object")
    }
    if !(request is { "mode": String("url"), .. }) {
      guard content is Some(content_val) else {
        raise InvalidParams(
          "accepted form elicitation response.content is required",
        )
      }
      guard request is { "requestedSchema": request_schema, .. } else {
        raise InvalidParams("elicitation request.requestedSchema is required")
      }
      let validator = compile_mrtr_schema(request_schema)
      validator.validate(content_val) catch {
        ValidationIssues(issues) => {
          let error = issues.to_json().stringify()
          raise InvalidParams(
            "elicitation response.content does not match requestedSchema: \{error}",
          )
        }
      }
    }
  }
  { action, content }
}

///|
pub struct Root {
  uri : String
  name : String?
} derive(Debug, Eq)

///|
pub fn Root::from_json(value : Json) -> Root raise McpError {
  match value {
    Object({ "uri": String(uri), "name": String(name), .. }) =>
      { uri, name: Some(name) }
    Object({ "uri": String(uri), "name": Null, .. }) => { uri, name: None }
    Object({ "uri": String(_), "name": _, .. }) =>
      raise InvalidParams("roots response root.name must be a string")
    Object({ "uri": String(uri), .. }) => { uri, name: None }
    Object(_) => raise InvalidParams("roots response root.uri is required")
    _ => raise InvalidParams("roots response root must be an object")
  }
}

///|
pub impl ToJson for Root with fn to_json(self : Root) -> Json {
  let fields : Map[String, Json] = { "uri": Json::string(self.uri) }
  fields.set_opt("name", self.name.map(Json::string))
  Json::object(fields)
}

///|
pub struct RootsListResult {
  roots : Array[Root]
} derive(Debug, Eq)

///|
pub fn RootsListResult::from_json(
  fields : Map[String, Json],
) -> RootsListResult raise McpError {
  match fields {
    { "roots": Array(roots_arr), .. } => {
      let roots : Array[Root] = []
      for root_json in roots_arr {
        roots.push(Root::from_json(root_json))
      }
      { roots, }
    }
    _ => raise InvalidParams("roots response.roots is required")
  }
}

///|
pub impl ToJson for RootsListResult with fn to_json(self : RootsListResult) -> Json {
  Json::object({ "roots": Json::array(self.roots.map(fn(r) { r.to_json() })) })
}

///|
fn validate_core_input_request(
  method_name : String,
  fields : Map[String, Json],
) -> Unit raise McpError {
  match method_name {
    "elicitation/create" => ignore(ElicitationCreateParams::from_json(fields))
    "sampling/createMessage" =>
      ignore(SamplingCreateMessageParams::from_json(fields))
    "roots/list" => ()
    _ => ()
  }
}

///|
fn validate_core_input_response(
  method_name : String,
  request_params : Json,
  result : Json,
) -> Unit raise McpError {
  guard result is Object(fields) else {
    raise InvalidParams("input response must be an object")
  }
  match method_name {
    "elicitation/create" =>
      ignore(ElicitationCreateResult::from_json(fields, request_params))
    "sampling/createMessage" =>
      ignore(SamplingCreateMessageResult::from_json(fields))
    "roots/list" => ignore(RootsListResult::from_json(fields))
    _ => ()
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
pub impl @json.FromJson for InputRequest with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> InputRequest raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let method_name = match fields.get("method") {
    Some(String(s)) => s
    Some(_) =>
      raise JsonDecodeError((path.add_key("method"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("method"), "method is required"))
  }
  let params = fields.get("params").unwrap_or(Json::object({}))
  InputRequest(method_name~, params~) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub fn InputRequest::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> InputRequest raise McpError {
  decode_json(value, path?)
}

///|
/// A raw client result for a server-initiated input request.
pub struct InputResponse {
  result : Json
} derive(Debug, Eq)

///|
pub fn InputResponse::InputResponse(result : Json) -> InputResponse {
  { result: result.copy() }
}

///|
pub impl @json.FromJson for InputResponse with fn from_json(
  value : Json,
  _path : @json.JsonPath,
) -> InputResponse {
  InputResponse(value)
}

///|
pub fn InputResponse::from_json(value : Json) -> InputResponse {
  InputResponse(value)
}

///|
pub impl ToJson for InputResponse with fn to_json(self : InputResponse) -> Json {
  self.result
}

///|
pub fn InputResponse::map_from_json(
  value : Json,
) -> Map[String, InputResponse] raise McpError {
  guard value is Object(fields) else {
    raise InvalidParams("inputResponses must be an object")
  }
  let responses : Map[String, InputResponse] = Map([])
  for key, result in fields {
    responses[key] = InputResponse::from_json(result)
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
  {
    input_requests: input_requests.map(fn(
      requests,
    ) -> Map[String, InputRequest] raise McpError {
      let copied : Map[String, InputRequest] = Map([])
      for key, request in requests {
        copied[key] = InputRequest(
          method_name=request.method_name,
          params=request.params.copy(),
        )
      }
      copied
    }),
    request_state,
    meta: meta.map(fn(m) { m.copy() }),
  }
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
/// Compile an MRTR request schema through the independent JSON Schema package.
fn compile_mrtr_schema(value : Json) -> @schema.Schema raise McpError {
  @schema.Schema::from_json(value) catch {
    _ => raise InvalidParams("MRTR requestedSchema is not a valid JSON Schema")
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
  fields.set_opt("requestState", self.request_state.map(Json::string))
  if self.meta is Some(value) {
    fields["_meta"] = value.to_json()
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for InputRequiredResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> InputRequiredResult raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let input_requests : Map[String, InputRequest]? = match
    fields.get("inputRequests") {
    Some(Object(map)) => {
      let requests : Map[String, InputRequest] = Map([])
      for k, v in map {
        requests[k] = @json.from_json(
          v,
          path=path.add_key("inputRequests").add_key(k),
        )
      }
      Some(requests)
    }
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("inputRequests"), "expected object"))
  }
  let request_state = match fields.get("requestState") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("requestState"), "expected string"))
  }
  let meta : ResultMeta? = match fields.get("_meta") {
    Some(v) => Some(@json.from_json(v, path=path.add_key("_meta")))
    None => None
  }
  InputRequiredResult(input_requests?, request_state?, meta?) catch {
    error => raise JsonDecodeError((path, error.to_string()))
  }
}

///|
pub fn InputRequiredResult::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> InputRequiredResult raise McpError {
  decode_json(value, path?)
}

///|
/// A typed handler can either finish or ask the client for more input.
pub(all) enum HandlerOutcome[T] {
  Complete(T)
  InputRequired(InputRequiredResult)
  ExtensionResult(String, Json)
}

///|
/// Unwrap a Complete outcome or raise an error if more input is required or an extension result was returned.
pub fn[T] HandlerOutcome::require_complete(
  self : HandlerOutcome[T],
  context~ : String,
) -> T raise McpError {
  match self {
    Complete(result) => result
    InputRequired(_) =>
      raise InvalidRequest("\{context} cannot return input_required")
    ExtensionResult(result_type, _) =>
      raise InvalidRequest(
        "\{context} cannot return extension result type \{result_type}",
      )
  }
}
