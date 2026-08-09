///|
/// Metadata required on every MCP 2026-07-28 request.
pub(all) struct RequestMeta {
  protocol_version : String
  client_info : Implementation?
  client_capabilities : ClientCapabilities
  progress_token : Json?
  log_level : LoggingLevel?
  extra : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn RequestMeta::RequestMeta(
  protocol_version? : String = latest_protocol_version,
  client_info? : Implementation,
  client_capabilities? : ClientCapabilities = ClientCapabilities::empty(),
  progress_token? : Json,
  log_level? : LoggingLevel,
  extra? : Map[String, Json] = {},
) -> RequestMeta {
  {
    protocol_version,
    client_info,
    client_capabilities,
    progress_token,
    log_level,
    extra,
  }
}

///|
pub impl ToJson for RequestMeta with fn to_json(self : RequestMeta) -> Json {
  // Vendor metadata is inserted first so protocol-reserved keys always win.
  let fields = self.extra.copy()
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
pub fn parse_request_meta(value : Json) -> RequestMeta raise McpError {
  let context = "request params._meta"
  let fields = expect_object(value, context)
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
pub(all) struct RequestOptions {
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
  { progress_token, log_level, input_responses, request_state, meta }
}

///|
/// Transport-provided request hooks. Built-in defaults are inert, while
/// streaming adapters can emit progress and expose cancellation without
/// storing connection state on `Server`.
pub struct RequestHooks {
  priv emit_notification : async (Json) -> Unit raise McpError
  priv is_cancelled : () -> Bool
  priv transport_meta : Json?
}

///|
pub fn RequestHooks::RequestHooks(
  emit_notification? : async (Json) -> Unit raise McpError = fn(_) { () },
  is_cancelled? : () -> Bool = fn() { false },
  transport_meta? : Json,
) -> RequestHooks {
  { emit_notification, is_cancelled, transport_meta }
}

///|
pub fn RequestOptions::request_meta(
  self : RequestOptions,
  client_capabilities~ : ClientCapabilities,
  client_info? : Implementation,
  protocol_version? : String = latest_protocol_version,
) -> RequestMeta {
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
  protocol_version? : String = latest_protocol_version,
) -> Json {
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
  { request_id, method_name, meta, input_responses, request_state, hooks }
}

///|
pub fn RequestContext::request_id(self : RequestContext) -> Json {
  self.request_id
}

///|
pub fn RequestContext::method_name(self : RequestContext) -> String {
  self.method_name
}

///|
pub fn RequestContext::meta(self : RequestContext) -> RequestMeta {
  self.meta
}

///|
pub fn RequestContext::input_responses(
  self : RequestContext,
) -> Map[String, InputResponse]? {
  self.input_responses
}

///|
pub fn RequestContext::request_state(self : RequestContext) -> String? {
  self.request_state
}

///|
pub fn RequestContext::is_cancelled(self : RequestContext) -> Bool {
  (self.hooks.is_cancelled)()
}

///|
pub fn RequestContext::transport_meta(self : RequestContext) -> Json? {
  self.hooks.transport_meta
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
  (self.hooks.emit_notification)(
    progress_notification(progress_token=token, progress~, total?, message?),
  )
}
