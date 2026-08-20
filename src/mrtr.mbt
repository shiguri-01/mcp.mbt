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
  guard params is Object(_) else {
    raise InvalidParams("input request params must be an object")
  }
  validate_core_input_request(method_name, params)
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
        "content": Json::array(content.map(fn(c) { ToJson::to_json(c) })),
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
    Single(block) => ToJson::to_json(block)
    Multiple(blocks) => Json::array(blocks.map(fn(b) { ToJson::to_json(b) }))
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
    "role": ToJson::to_json(self.role),
    "content": ToJson::to_json(self.content),
  })
}

///|
pub struct SamplingCreateMessageParams {
  messages : Array[SamplingMessage]
  max_tokens : Double
} derive(Debug, Eq)

///|
pub impl @json.FromJson for SamplingCreateMessageParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> SamplingCreateMessageParams raise {
  match value {
    Object(
      {
        "messages": Array(messages_arr),
        "maxTokens": Number(max_tokens, ..),
        ..
      }
    ) => {
      let messages : Array[SamplingMessage] = []
      for index, message_json in messages_arr {
        messages.push(
          @json.from_json(
            message_json,
            path=path.add_key("messages").add_index(index),
          ),
        )
      }
      { messages, max_tokens }
    }
    Object({ "messages": Array(_), .. }) =>
      raise @json.JsonDecodeError(
        (
          path.add_key("maxTokens"),
          "sampling/createMessage params.maxTokens is required",
        ),
      )
    _ =>
      raise @json.JsonDecodeError(
        (
          path.add_key("messages"),
          "sampling/createMessage params.messages must be an array",
        ),
      )
  }
}

///|
pub fn SamplingCreateMessageParams::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> SamplingCreateMessageParams raise McpError {
  decode_json(value, path?)
}

///|
pub struct SamplingCreateMessageResult {
  model : String
  role : Role
  content : SamplingContent
} derive(Debug, Eq)

///|
pub impl @json.FromJson for SamplingCreateMessageResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> SamplingCreateMessageResult raise {
  match value {
    Object(
      {
        "model": String(model),
        "role": String("user"),
        "content": content_val,
        ..
      }
    ) => {
      let content : SamplingContent = @json.from_json(
        content_val,
        path=path.add_key("content"),
      )
      { model, role: Role::User, content }
    }
    Object(
      {
        "model": String(model),
        "role": String("assistant"),
        "content": content_val,
        ..
      }
    ) => {
      let content : SamplingContent = @json.from_json(
        content_val,
        path=path.add_key("content"),
      )
      { model, role: Role::Assistant, content }
    }
    Object({ "model": String(_), "role": String("user" | "assistant"), .. }) =>
      raise @json.JsonDecodeError(
        (path.add_key("content"), "sampling response.content is required"),
      )
    Object({ "model": String(_), .. }) =>
      raise @json.JsonDecodeError(
        (path.add_key("role"), "sampling response.role is invalid"),
      )
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key("model"), "sampling response.model is required"),
      )
  }
}

///|
pub fn SamplingCreateMessageResult::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> SamplingCreateMessageResult raise McpError {
  decode_json(value, path?)
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
pub impl @json.FromJson for ElicitationPrimitiveSchema with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ElicitationPrimitiveSchema raise {
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
      raise @json.JsonDecodeError(
        (
          path.add_key("items"),
          "elicitation array schema items require enum options",
        ),
      )
    Object({ "type": String("array"), "items": Object(_), .. }) =>
      raise @json.JsonDecodeError(
        (
          path.add_key("items"),
          "elicitation array schema items must be strings",
        ),
      )
    Object({ "type": String("array"), "items": _, .. }) =>
      raise @json.JsonDecodeError(
        (path.add_key("items"), "elicitation enum items must be an object"),
      )
    Object({ "type": String("array"), .. }) =>
      raise @json.JsonDecodeError(
        (path.add_key("items"), "elicitation array schema.items is required"),
      )
    Object(_) =>
      raise @json.JsonDecodeError(
        (path, "elicitation properties must use primitive schemas"),
      )
    _ =>
      raise @json.JsonDecodeError(
        (path, "elicitation primitive schema must be an object"),
      )
  }
}

///|
pub fn ElicitationPrimitiveSchema::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ElicitationPrimitiveSchema raise McpError {
  decode_json(value, path?)
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
pub impl @json.FromJson for ElicitationCreateParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ElicitationCreateParams raise {
  guard value is Object(fields) else {
    raise @json.JsonDecodeError(
      (path, "elicitation/create params must be an object"),
    )
  }
  guard fields is { "message": String(message), .. } else {
    raise @json.JsonDecodeError(
      (path.add_key("message"), "elicitation/create params.message is required"),
    )
  }
  let parse_form = fn() -> ElicitationMode raise @json.JsonDecodeError {
    guard fields
      is {
        "requestedSchema": Object(
          { "type": String("object"), "properties": Object(properties_map), .. } as schema
        ),
        ..
      } else {
      guard fields is { "requestedSchema": Object(_), .. } else {
        raise @json.JsonDecodeError(
          (
            path.add_key("requestedSchema"),
            "elicitation/create form params.requestedSchema is required",
          ),
        )
      }
      raise @json.JsonDecodeError(
        (
          path.add_key("requestedSchema"),
          "elicitation/create requestedSchema requires object properties",
        ),
      )
    }
    let properties : Map[String, ElicitationPrimitiveSchema] = Map([])
    for key, property_schema in properties_map {
      properties[key] = @json.from_json(
        property_schema,
        path=path.add_key("requestedSchema").add_key("properties").add_key(key),
      )
    }
    let compiled_schema = compile_mrtr_schema(Json::object(schema)) catch {
      _ =>
        raise @json.JsonDecodeError(
          (path.add_key("requestedSchema"), "invalid JSON schema"),
        )
    }
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
      raise @json.JsonDecodeError(
        (path.add_key("url"), "elicitation/create params.url is required"),
      )
    { "mode": String("form"), .. } => parse_form()
    { "mode": String(_), .. } =>
      raise @json.JsonDecodeError(
        (path.add_key("mode"), "elicitation/create params.mode is invalid"),
      )
    { "mode": _, .. } =>
      raise @json.JsonDecodeError(
        (path.add_key("mode"), "elicitation/create params.mode is invalid"),
      )
    _ => parse_form()
  }
  { message, mode }
}

///|
pub fn ElicitationCreateParams::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ElicitationCreateParams raise McpError {
  decode_json(value, path?)
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
pub impl @json.FromJson for ElicitationCreateResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ElicitationCreateResult raise {
  match value {
    Object({ "action": String("accept"), .. } as fields) =>
      { action: Accept, content: fields.get("content") }
    Object({ "action": String("decline"), .. } as fields) =>
      { action: Decline, content: fields.get("content") }
    Object({ "action": String("cancel"), .. } as fields) =>
      { action: Cancel, content: fields.get("content") }
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key("action"), "elicitation response.action is invalid"),
      )
  }
}

///|
pub fn ElicitationCreateResult::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ElicitationCreateResult raise McpError {
  decode_json(value, path?)
}

///|
pub fn ElicitationCreateResult::validate_against_request(
  self : ElicitationCreateResult,
  request_params : Json,
) -> Unit raise McpError {
  if self.action == Accept {
    guard request_params is Object(request) else {
      raise InvalidParams("elicitation request must be an object")
    }
    if !(request is { "mode": String("url"), .. }) {
      guard self.content is Some(content_val) else {
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
}

///|
pub impl ToJson for ElicitationCreateResult with fn to_json(
  self : ElicitationCreateResult,
) -> Json {
  let fields : Map[String, Json] = {
    "action": match self.action {
      Accept => Json::string("accept")
      Decline => Json::string("decline")
      Cancel => Json::string("cancel")
    },
  }
  fields.set_opt("content", self.content)
  Json::object(fields)
}

///|
pub struct Root {
  uri : String
  name : String?
} derive(Debug, Eq)

///|
pub impl @json.FromJson for Root with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> Root raise {
  match value {
    Object({ "uri": String(uri), "name": String(name), .. }) =>
      { uri, name: Some(name) }
    Object({ "uri": String(uri), "name": Null, .. }) => { uri, name: None }
    Object({ "uri": String(_), "name": _, .. }) =>
      raise @json.JsonDecodeError(
        (path.add_key("name"), "roots response root.name must be a string"),
      )
    Object({ "uri": String(uri), .. }) => { uri, name: None }
    Object(_) =>
      raise @json.JsonDecodeError(
        (path.add_key("uri"), "roots response root.uri is required"),
      )
    _ =>
      raise @json.JsonDecodeError(
        (path, "roots response root must be an object"),
      )
  }
}

///|
pub fn Root::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> Root raise McpError {
  decode_json(value, path?)
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
pub impl @json.FromJson for RootsListResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> RootsListResult raise {
  match value {
    Object({ "roots": Array(roots_arr), .. }) => {
      let roots : Array[Root] = []
      for index, root_json in roots_arr {
        roots.push(
          @json.from_json(
            root_json,
            path=path.add_key("roots").add_index(index),
          ),
        )
      }
      { roots, }
    }
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key("roots"), "roots response.roots is required"),
      )
  }
}

///|
pub fn RootsListResult::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> RootsListResult raise McpError {
  decode_json(value, path?)
}

///|
pub impl ToJson for RootsListResult with fn to_json(self : RootsListResult) -> Json {
  Json::object({
    "roots": Json::array(self.roots.map(fn(r) { ToJson::to_json(r) })),
  })
}

///|
fn validate_core_input_request(
  method_name : String,
  params : Json,
) -> Unit raise McpError {
  match method_name {
    "elicitation/create" => ignore(ElicitationCreateParams::from_json(params))
    "sampling/createMessage" =>
      ignore(SamplingCreateMessageParams::from_json(params))
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
  match method_name {
    "elicitation/create" => {
      let elicitation = ElicitationCreateResult::from_json(result)
      elicitation.validate_against_request(request_params)
    }
    "sampling/createMessage" =>
      ignore(SamplingCreateMessageResult::from_json(result))
    "roots/list" => ignore(RootsListResult::from_json(result))
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
    "resultType": ToJson::to_json(ResultType::InputRequired),
  }
  if self.input_requests is Some(requests) {
    let values : Map[String, Json] = Map([])
    for key, request in requests {
      values[key] = ToJson::to_json(request)
    }
    fields["inputRequests"] = Json::object(values)
  }
  fields.set_opt("requestState", self.request_state.map(Json::string))
  if self.meta is Some(value) {
    fields["_meta"] = ToJson::to_json(value)
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

///|
/// Decode a raw JSON-RPC response message into a HandlerOutcome.
pub fn HandlerOutcome::decode_response(
  message : Json,
) -> HandlerOutcome[Json] raise McpError {
  let decoded = decode_message(message)
  let result = match decoded {
    Response(Success(result~, ..)) => result
    Response(Failure(error~, ..)) => raise McpError::from_error_object(error)
    _ => raise InvalidRequest("JSON-RPC response expected")
  }
  match result {
    Object({ "resultType": String("input_required"), .. }) =>
      InputRequired(InputRequiredResult::from_json(result))
    Object({ "resultType": String("complete"), .. }) => Complete(result)
    Object({ "resultType": String(type_name), .. }) =>
      ExtensionResult(type_name, result)
    Object(_) => Complete(result)
    _ => raise InvalidRequest("MCP result must be an object")
  }
}
