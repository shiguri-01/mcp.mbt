///|
/// Metadata required on every MCP 2026-07-28 request.
pub struct RequestMeta {
  protocol_version : String
  client_info : Implementation?
  client_capabilities : ClientCapabilities
  progress_token : Json?
  log_level : LoggingLevel?
  extra : Map[String, Json]
} derive(Debug, Eq)

///|
fn valid_meta_key(key : String) -> Bool {
  let segments = key.split("/").to_array()
  if segments.length() > 2 {
    return false
  }
  let name = segments[segments.length() - 1].to_owned()
  if !name.is_empty() {
    let chars = name.to_array()
    let endpoint = fn(char : Char) {
      char.is_ascii_alphabetic() || char.is_ascii_digit()
    }
    if !endpoint(chars[0]) ||
      !endpoint(chars[chars.length() - 1]) ||
      !chars.all(fn(char) {
        endpoint(char) || char == '-' || char == '_' || char == '.'
      }) {
      return false
    }
  }
  if segments.length() == 2 {
    let labels = segments[0].split(".").to_array()
    if labels.is_empty() {
      return false
    }
    for label in labels {
      let chars = label.to_array()
      if chars.is_empty() ||
        !chars[0].is_ascii_alphabetic() ||
        !(chars[chars.length() - 1].is_ascii_alphabetic() ||
        chars[chars.length() - 1].is_ascii_digit()) ||
        !chars.all(fn(char) {
          char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '-'
        }) {
        return false
      }
    }
  }
  true
}

///|
fn validate_meta_map(values : Map[String, Json]) -> Unit raise McpError {
  for key, _ in values {
    if !valid_meta_key(key) {
      raise InvalidParams("invalid _meta key: \{key}")
    }
  }
}

///|
pub fn RequestMeta::RequestMeta(
  protocol_version? : String = LATEST_PROTOCOL_VERSION,
  client_info? : Implementation,
  client_capabilities? : ClientCapabilities = ClientCapabilities::empty(),
  progress_token? : Json,
  log_level? : LoggingLevel,
  extra? : Map[String, Json] = {},
) -> RequestMeta raise McpError {
  if protocol_version.is_empty() {
    raise InvalidParams("protocol version must not be empty")
  }
  validate_meta_map(extra)
  {
    protocol_version,
    client_info: client_info.map(value => value.copy()),
    client_capabilities: client_capabilities.copy(),
    progress_token: copy_optional_json(progress_token),
    log_level,
    extra: copy_json_map(extra),
  }
}

///|
pub impl ToJson for RequestMeta with fn to_json(self : RequestMeta) -> Json {
  // Vendor metadata is inserted first so protocol-reserved keys always win.
  let fields = copy_json_map(self.extra)
  put_optional_json(fields, "progressToken", self.progress_token)
  fields["io.modelcontextprotocol/protocolVersion"] = Json::string(
    self.protocol_version,
  )
  if self.client_info is Some(value) {
    fields["io.modelcontextprotocol/clientInfo"] = value.to_json()
  }
  fields["io.modelcontextprotocol/clientCapabilities"] = self.client_capabilities.to_json()
  if self.log_level is Some(value) {
    fields["io.modelcontextprotocol/logLevel"] = value.to_json()
  }
  Json::object(fields)
}

///|
fn parse_progress_token(value : Json, context : String) -> Json raise McpError {
  match value {
    String(_) | Number(_) => value
    _ =>
      raise InvalidParams("\{context}.progressToken must be a string or number")
  }
}

///|
fn parse_request_implementation(
  value : Json,
  context : String,
) -> Implementation raise McpError {
  @json.from_json(value) catch {
    JsonDecodeError((_, message)) =>
      raise InvalidParams("\{context}: \{message}")
  }
}

///|
/// Decode the request `_meta` object at the MCP protocol boundary.
pub fn decode_request_meta(value : Json) -> RequestMeta raise McpError {
  let context = "request params._meta"
  let fields = expect_object(value, context)
  validate_meta_map(fields)
  let protocol_version = get_string(
    fields, "io.modelcontextprotocol/protocolVersion", context,
  )
  guard fields.get("io.modelcontextprotocol/clientCapabilities") is Some(caps) else {
    raise InvalidParams(
      "\{context}.io.modelcontextprotocol/clientCapabilities is required",
    )
  }
  let extra : Map[String, Json] = Map([])
  for key, item in fields {
    match key {
      "progressToken"
      | "io.modelcontextprotocol/protocolVersion"
      | "io.modelcontextprotocol/clientInfo"
      | "io.modelcontextprotocol/clientCapabilities"
      | "io.modelcontextprotocol/logLevel" => ()
      _ => extra[key] = item
    }
  }
  RequestMeta(
    protocol_version~,
    client_info?=match fields.get("io.modelcontextprotocol/clientInfo") {
      Some(item) =>
        Some(
          parse_request_implementation(
            item,
            "\{context}.io.modelcontextprotocol/clientInfo",
          ),
        )
      None => None
    },
    client_capabilities=parse_client_capabilities(
      caps,
      context="\{context}.io.modelcontextprotocol/clientCapabilities",
    ),
    progress_token?=match fields.get("progressToken") {
      Some(item) => Some(parse_progress_token(item, context))
      None => None
    },
    log_level?=match fields.get("io.modelcontextprotocol/logLevel") {
      Some(item) => Some(parse_logging_level(item))
      None => None
    },
    extra~,
  )
}

///|
/// Per-call overrides and MRTR retry data used by request builders.
pub struct RequestOptions {
  progress_token : Json?
  log_level : LoggingLevel?
  input_responses : Map[String, InputResponse]?
  request_state : String?
  meta : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn RequestOptions::RequestOptions(
  progress_token? : Json,
  log_level? : LoggingLevel,
  input_responses? : Map[String, InputResponse],
  request_state? : String,
  meta? : Map[String, Json] = {},
) -> RequestOptions {
  let copied_responses : Map[String, InputResponse]? = input_responses.map(fn(
    responses,
  ) {
    let copied : Map[String, InputResponse] = Map([])
    for key, response in responses {
      copied[key] = InputResponse(response.result)
    }
    copied
  })
  {
    progress_token: copy_optional_json(progress_token),
    log_level,
    input_responses: copied_responses,
    request_state,
    meta: copy_json_map(meta),
  }
}

///|
/// Transport-provided request hooks. Built-in defaults are inert, while
/// streaming adapters can emit progress and expose cancellation without
/// storing connection state on `Server`.
pub struct RequestHooks {
  priv emit_notification : async (Json) -> Unit raise McpError
  priv is_cancelled : () -> Bool
  priv transport_meta : Json?
  priv last_progress : Ref[Double?]
}

///|
pub fn RequestHooks::RequestHooks(
  emit_notification? : async (Json) -> Unit raise McpError = fn(_) { () },
  is_cancelled? : () -> Bool = fn() { false },
  transport_meta? : Json,
) -> RequestHooks {
  { emit_notification, is_cancelled, transport_meta, last_progress: Ref(None) }
}

///|
pub fn RequestOptions::request_meta(
  self : RequestOptions,
  client_capabilities~ : ClientCapabilities,
  client_info? : Implementation,
  protocol_version? : String = LATEST_PROTOCOL_VERSION,
) -> RequestMeta raise McpError {
  validate_meta_map(self.meta)
  RequestMeta(
    protocol_version~,
    client_info?,
    client_capabilities~,
    progress_token?=self.progress_token,
    log_level?=self.log_level,
    extra=self.meta,
  )
}

///|
/// Add common metadata and MRTR retry fields to method-specific parameters.
pub fn RequestOptions::request_params(
  self : RequestOptions,
  params : Map[String, Json],
  client_capabilities~ : ClientCapabilities,
  client_info? : Implementation,
  protocol_version? : String = LATEST_PROTOCOL_VERSION,
) -> Json raise McpError {
  let fields = params.copy()
  fields["_meta"] = self
    .request_meta(client_capabilities~, client_info?, protocol_version~)
    .to_json()
  if self.input_responses is Some(responses) {
    let values : Map[String, Json] = Map([])
    for key, response in responses {
      values[key] = response.to_json()
    }
    fields["inputResponses"] = Json::object(values)
  }
  put_optional_string(fields, "requestState", self.request_state)
  Json::object(fields)
}

///|
/// Request-scoped protocol data passed to application handlers.
pub struct RequestContext {
  request_id : Json
  method_name : String
  meta : RequestMeta
  input_responses : Map[String, InputResponse]?
  request_state : String?
  transport_meta : Json?
  hooks : RequestHooks
}

///|
pub fn RequestContext::RequestContext(
  request_id~ : Json,
  method_name~ : String,
  meta~ : RequestMeta,
  input_responses? : Map[String, InputResponse],
  request_state? : String,
  hooks? : RequestHooks = RequestHooks(),
) -> RequestContext raise McpError {
  if !(request_id is (String(_) | Number(_))) {
    raise InvalidRequest("request id must be a string or number")
  }
  {
    request_id,
    method_name,
    meta,
    input_responses,
    request_state,
    transport_meta: copy_optional_json(hooks.transport_meta),
    hooks,
  }
}

///|
pub fn RequestContext::is_cancelled(self : RequestContext) -> Bool {
  (self.hooks.is_cancelled)()
}

///|
/// Emit request-scoped progress using the token supplied by the client.
pub async fn RequestContext::report_progress(
  self : RequestContext,
  progress~ : Double,
  total? : Double,
  message? : String,
) -> Unit raise McpError {
  guard self.meta.progress_token is Some(token) else {
    raise InvalidRequest("request did not provide a progress token")
  }
  if progress < 0.0 || progress.is_nan() || progress.is_inf() {
    raise InvalidParams("progress must be a finite non-negative number")
  }
  if self.hooks.last_progress.val is Some(previous) && progress <= previous {
    raise InvalidParams("progress must increase with each notification")
  }
  if total is Some(limit) &&
    (limit <= 0.0 || limit.is_nan() || limit.is_inf() || progress > limit) {
    raise InvalidParams(
      "progress total must be finite, positive, and not below progress",
    )
  }
  (self.hooks.emit_notification)(
    progress_notification(progress_token=token, progress~, total?, message?),
  )
  self.hooks.last_progress.val = Some(progress)
}
