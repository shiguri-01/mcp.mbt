///|
/// Stateless Streamable HTTP transport for a single MCP endpoint.
pub struct Transport {
  endpoint : String
  supported_protocol_versions : Array[String]
  mut protocol_version : String
  tool_schemas : Map[String, Json]
  authorization : AuthorizationOptions?
  credential_cache : @auth.CredentialCache
  token_cache : @auth.TokenCache
  retry_policy : @auth.RetryPolicy
  mut authorization_issuer : String?
  authorization_resource : String
  authorization_resource_exact : Bool
  max_response_body_bytes : Int
  max_sse_event_bytes : Int
}

///|
/// Optional MCP Authorization configuration. HTTP delivery, user interaction,
/// and secure random generation remain explicit host responsibilities through
/// `AuthorizationProvider`.
pub struct AuthorizationOptions {
  provider : @auth.AuthorizationProvider
  redirect_uri : String
  client_name : String
  client_id_metadata_url : String?
  pre_registered : Map[String, @auth.ClientCredentials]
  wants_refresh_token : Bool
  resource_uri : String?
}

///|
pub fn AuthorizationOptions::AuthorizationOptions(
  provider~ : @auth.AuthorizationProvider,
  redirect_uri~ : String,
  client_name? : String = "MoonBit MCP client",
  client_id_metadata_url? : String,
  pre_registered? : Map[String, @auth.ClientCredentials] = Map([]),
  wants_refresh_token? : Bool = false,
  resource_uri? : String,
) -> AuthorizationOptions raise @mcp.McpError {
  ignore(
    @auth.validate_secure_uri(
      redirect_uri,
      allow_loopback_http=provider.allow_insecure_loopback,
    ),
  ) catch {
    _ => raise @mcp.InvalidParams("authorization redirect_uri must be absolute")
  }
  if client_name.is_empty() {
    raise @mcp.InvalidParams("authorization client_name must not be empty")
  }
  {
    provider,
    redirect_uri,
    client_name,
    client_id_metadata_url,
    pre_registered: pre_registered.copy(),
    wants_refresh_token,
    resource_uri,
  }
}

///|
/// Create a modern MCP HTTP transport.
pub fn Transport::Transport(
  endpoint : String,
  supported_protocol_versions? : Array[String] = [@mcp.LATEST_PROTOCOL_VERSION],
  authorization? : AuthorizationOptions,
  max_response_body_bytes? : Int = default_max_response_body_bytes,
  max_sse_event_bytes? : Int = default_max_sse_event_bytes,
) -> Transport raise @mcp.McpError {
  if max_response_body_bytes <= 0 {
    raise @mcp.InvalidParams("max_response_body_bytes must be positive")
  }
  if max_sse_event_bytes <= 0 {
    raise @mcp.InvalidParams("max_sse_event_bytes must be positive")
  }
  guard supported_protocol_versions is [protocol_version, ..] else {
    raise @mcp.InvalidParams("supported_protocol_versions must not be empty")
  }
  for version in supported_protocol_versions {
    if version.is_empty() {
      raise @mcp.InvalidParams(
        "supported_protocol_versions must contain non-empty strings",
      )
    }
  }
  let (authorization_resource, authorization_resource_exact) = match
    authorization {
    Some(options) if options.resource_uri is Some(resource_uri) => {
      ignore(@auth.AbsoluteUri::parse(resource_uri)) catch {
        _ =>
          raise @mcp.InvalidParams(
            "authorization resource_uri must be absolute",
          )
      }
      options.provider.check_destination(resource_uri) catch {
        error => raise auth_error_to_mcp(error)
      }
      (resource_uri, true)
    }
    _ => {
      let canonical = @auth.canonical_resource_uri(endpoint) catch {
        _ => raise @mcp.InvalidParams("HTTP endpoint must be an absolute URI")
      }
      (canonical, false)
    }
  }
  if authorization is Some(options) {
    options.provider.check_destination(endpoint) catch {
      error => raise auth_error_to_mcp(error)
    }
  }
  let retry_policy = @auth.RetryPolicy() catch {
    _ => raise @mcp.InternalError("could not initialize authorization policy")
  }
  {
    endpoint,
    supported_protocol_versions: supported_protocol_versions.copy(),
    protocol_version,
    tool_schemas: Map([]),
    authorization,
    credential_cache: @auth.CredentialCache(),
    token_cache: @auth.TokenCache(),
    retry_policy,
    authorization_issuer: None,
    authorization_resource,
    authorization_resource_exact,
    max_response_body_bytes,
    max_sse_event_bytes,
  }
}

///|
pub fn Transport::headers(
  self : Transport,
  request : Json,
  input_schema? : Json,
) -> Map[@async_http.CaseInsensitiveString, String] raise HttpHeaderError {
  let headers : Map[@async_http.CaseInsensitiveString, String] = {
    "Accept": "application/json, text/event-stream",
    "Content-Type": "application/json",
  }
  for name, value in standard_request_headers(request, self.protocol_version) {
    headers[name] = value
  }
  if self.authorization_issuer is Some(issuer) &&
    self.token_cache.get(issuer~, resource=self.authorization_resource)
    is Some(tokens) {
    // Bearer credentials are header-only. They are never appended to the MCP
    // endpoint, discovery URLs, or authorization URL query parameters.
    headers["Authorization"] = tokens.authorization_header()
  }
  let schema = match input_schema {
    Some(s) => Some(s)
    None =>
      match request {
        Object({ "method": String("tools/call"), "params": Object(p), .. }) =>
          match p.get("name") {
            Some(String(tool_name)) => self.tool_schemas.get(tool_name)
            _ => None
          }
        _ => None
      }
  }
  if schema is Some(schema) &&
    request
    is Object(
      {
        "method": String("tools/call"),
        "params": Object({ "arguments": arguments, .. }),
        ..
      }
    ) {
    for name, value in tool_argument_headers(schema, arguments) {
      headers[name] = value
    }
  }
  headers
}

///|
fn request_operation(request : Json) -> String {
  match request {
    Object({ "method": String(operation), .. }) => operation
    _ => "unknown"
  }
}

///|
pub fn response_requires_authorization(response : @async_http.Response) -> Bool {
  if response.code == 401 {
    return true
  }
  if response.code != 403 {
    return false
  }
  match header(response.headers, "WWW-Authenticate") {
    Some(value) => {
      let parsed = try @auth.BearerChallenge::parse(value) catch {
        _ => None
      } noraise {
        challenge => Some(challenge)
      }
      match parsed {
        Some(challenge) => challenge.error() == Some("insufficient_scope")
        None => false
      }
    }
    None => false
  }
}

///|
async fn Transport::read_response_text(
  self : Transport,
  stream : @async_http.Client,
  response : @async_http.Response,
  subject? : String = "MCP HTTP response body",
) -> String raise @mcp.McpError {
  if header(response.headers, "Content-Length") is Some(content_length) &&
    decimal_header_exceeds(content_length, self.max_response_body_bytes) {
    raise @mcp.InvalidRequest(
      "\{subject} exceeds the configured limit of \{self.max_response_body_bytes} bytes",
    )
  }
  read_bounded_text(stream, self.max_response_body_bytes, subject) catch {
    error => raise body_read_error_to_mcp(error)
  }
}

///|
fn auth_error_to_mcp(error : @auth.AuthError) -> @mcp.McpError {
  let message = match error {
    @auth.InvalidUri(value) => "invalid authorization URI: " + value
    @auth.InvalidChallenge(value) => "invalid authorization challenge: " + value
    @auth.InvalidMetadata(value) => "invalid authorization metadata: " + value
    @auth.InvalidAuthorizationResponse(value) =>
      "invalid authorization response: " + value
    @auth.UnsupportedRegistration(value) =>
      "unsupported client registration: " + value
    @auth.TransportFailure(value) => "authorization transport failed: " + value
    @auth.AuthorizationFailed(value) => "authorization failed: " + value
    @auth.RetryLimitExceeded(value) => value
  }
  @mcp.InvalidRequest(message)
}

///|
pub async fn Transport::authorize_challenge(
  self : Transport,
  response : @async_http.Response,
  operation : String,
) -> Unit raise @mcp.McpError {
  guard self.authorization is Some(options) else {
    raise @mcp.InvalidRequest("HTTP authorization is required")
  }
  let challenge = match header(response.headers, "WWW-Authenticate") {
    Some(value) =>
      Some(
        @auth.BearerChallenge::parse(value) catch {
          error => raise auth_error_to_mcp(error)
        },
      )
    None => None
  }
  self.retry_policy.record_attempt(self.authorization_resource, operation) catch {
    error => raise auth_error_to_mcp(error)
  }
  let resource_metadata = @auth.discover_protected_resource_metadata(
    options.provider,
    self.authorization_resource,
    challenge?,
    exact_resource=self.authorization_resource_exact,
  ) catch {
    error => raise auth_error_to_mcp(error)
  }
  guard resource_metadata.authorization_servers is [issuer, ..] else {
    raise @mcp.InvalidRequest(
      "protected resource metadata has no authorization server",
    )
  }
  let metadata = @auth.discover_authorization_server_metadata(
    options.provider,
    issuer,
  ) catch {
    error => raise auth_error_to_mcp(error)
  }
  let credentials = match self.credential_cache.get(issuer) {
    Some(credentials) => credentials
    None => {
      let pre_registered = options.pre_registered.get(issuer)
      if pre_registered is None && options.client_id_metadata_url is Some(url) {
        options.provider.check_destination(url) catch {
          error => raise auth_error_to_mcp(error)
        }
      }
      let choice = @auth.choose_registration(
        metadata,
        client_id_metadata_url?=options.client_id_metadata_url,
        pre_registered?,
        allow_insecure_loopback=options.provider.allow_insecure_loopback,
      ) catch {
        error => raise auth_error_to_mcp(error)
      }
      let credentials = match choice {
        @auth.ClientIdMetadataDocument(client_id) =>
          @auth.ClientCredentials(client_id~, token_endpoint_auth_method=None) catch {
            error => raise auth_error_to_mcp(error)
          }
        @auth.PreRegistered(credentials) => credentials
        @auth.Dynamic(_) => {
          let registration_request = @auth.dynamic_registration_request(
            metadata,
            client_name=options.client_name,
            redirect_uris=[options.redirect_uri],
            wants_refresh_token=options.wants_refresh_token,
          ) catch {
            error => raise auth_error_to_mcp(error)
          }
          let registration_response = options.provider.send(
            registration_request,
          ) catch {
            error => raise auth_error_to_mcp(error)
          }
          if !(registration_response.status is (200..<300)) {
            raise @mcp.InvalidRequest("dynamic registration was rejected")
          }
          let registration_json = @json.parse(registration_response.body) catch {
            _ =>
              raise @mcp.InvalidRequest(
                "dynamic registration returned invalid JSON",
              )
          }
          @auth.ClientCredentials::from_registration_json(
            registration_json,
            requested_token_endpoint_auth_method=None,
          ) catch {
            error => raise auth_error_to_mcp(error)
          }
        }
      }
      self.credential_cache.put(issuer~, credentials)
      credentials
    }
  }
  let previous_tokens = self.token_cache.get(
    issuer~,
    resource=self.authorization_resource,
  )
  let challenge_error = match challenge {
    Some(value) => value.error()
    None => None
  }
  let challenge_scope = match challenge {
    Some(value) => value.scope()
    None => None
  }
  if challenge_error == Some("invalid_token") &&
    previous_tokens is Some(tokens) &&
    tokens.refresh_token is Some(refresh_token) {
    let refreshed = try
      @auth.AuthorizationEngine(options.provider).refresh(
        metadata,
        credentials,
        refresh_token~,
        resource=self.authorization_resource,
        scopes=tokens.scope,
        exact_resource=self.authorization_resource_exact,
      )
    catch {
      _ => None
    } noraise {
      value => Some(value)
    }
    if refreshed is Some(tokens) {
      self.token_cache.put(
        issuer~,
        resource=self.authorization_resource,
        tokens,
      )
      self.authorization_issuer = Some(issuer)
      return
    }
  }
  let previous_scopes = previous_tokens.map(tokens => tokens.scope)
  let scopes = match (challenge_error, challenge_scope, previous_scopes) {
    (Some("insufficient_scope"), Some(required), Some(previous)) =>
      @auth.step_up_scopes(previous, required)
    _ =>
      @auth.initial_scopes(
        challenge_scope?,
        resource_scopes?=resource_metadata.scopes_supported,
        authorization_server_scopes?=metadata.scopes_supported,
        wants_refresh_token=options.wants_refresh_token,
      )
  }
  let tokens = @auth.AuthorizationEngine(options.provider).authorize(
    metadata,
    credentials,
    redirect_uri=options.redirect_uri,
    resource=self.authorization_resource,
    scopes~,
    exact_resource=self.authorization_resource_exact,
  ) catch {
    error => raise auth_error_to_mcp(error)
  }
  self.token_cache.put(issuer~, resource=self.authorization_resource, tokens)
  self.authorization_issuer = Some(issuer)
}

///|
fn request_with_protocol_version(
  request : Json,
  protocol_version : String,
  fresh_id : Bool,
) -> Json raise @mcp.McpError {
  guard request is Object(request_fields) else {
    raise @mcp.InvalidRequest("HTTP request must be a JSON object")
  }
  guard request_fields.get("id") is Some(original_id) else {
    raise @mcp.InvalidRequest("HTTP request is missing its JSON-RPC id")
  }
  guard request_fields.get("params") is Some(Object(param_fields)) else {
    raise @mcp.InvalidRequest("HTTP request params must be an object")
  }
  guard param_fields.get("_meta") is Some(Object(meta_fields)) else {
    raise @mcp.InvalidRequest("HTTP request params._meta must be an object")
  }
  let rewritten_request = request_fields.copy()
  let rewritten_params = param_fields.copy()
  let rewritten_meta = meta_fields.copy()
  rewritten_meta["io.modelcontextprotocol/protocolVersion"] = Json::string(
    protocol_version,
  )
  rewritten_params["_meta"] = Json::object(rewritten_meta)
  rewritten_request["params"] = Json::object(rewritten_params)
  if fresh_id {
    rewritten_request["id"] = Json::string(
      "mcp-version-retry:" + original_id.stringify(),
    )
  }
  Json::object(rewritten_request)
}

///|
fn notification_with_protocol_version(
  notification : Json,
  protocol_version : String,
) -> Json raise @mcp.McpError {
  guard is_jsonrpc_notification(notification) else {
    raise @mcp.InvalidRequest(
      "HTTP notification must be a JSON-RPC notification",
    )
  }
  guard notification is Object(notification_fields) else {
    raise @mcp.InvalidRequest("HTTP notification must be a JSON object")
  }
  let rewritten_notification = notification_fields.copy()
  if notification_fields.get("params") is Some(Object(param_fields)) &&
    param_fields.get("_meta") is Some(Object(meta_fields)) {
    let rewritten_params = param_fields.copy()
    let rewritten_meta = meta_fields.copy()
    rewritten_meta["io.modelcontextprotocol/protocolVersion"] = Json::string(
      protocol_version,
    )
    rewritten_params["_meta"] = Json::object(rewritten_meta)
    rewritten_notification["params"] = Json::object(rewritten_params)
  }
  Json::object(rewritten_notification)
}

///|
fn Transport::mutually_supported_protocol_version(
  self : Transport,
  server_versions : Array[String],
) -> String? {
  for client_version in self.supported_protocol_versions {
    for server_version in server_versions {
      if client_version == server_version {
        return Some(client_version)
      }
    }
  }
  None
}

///|
fn http_error_to_mcp(
  response : @async_http.Response,
  body : String,
) -> @mcp.McpError {
  let fallback = @mcp.InvalidRequest("HTTP \{response.code} \{response.reason}")
  let parsed = @json.parse(body) catch { _ => return fallback }
  let decoded = @jsonrpc.decode(parsed) catch { _ => return fallback }
  match decoded {
    @jsonrpc.Message::Response(@jsonrpc.Response::Failure(error~, ..)) =>
      @mcp.McpError::from_error_object(error) catch {
        error => error
      }
    _ => fallback
  }
}

///|
fn parse_event_stream_messages(
  body : String,
) -> Array[Json] raise @mcp.McpError {
  let messages : Array[Json] = []
  let mut data_lines : Array[String] = []
  for raw_line in body.split("\n") {
    let line = raw_line.trim_end(chars="\r")
    if line == "" {
      if !data_lines.is_empty() {
        let data = data_lines.join("\n")
        data_lines = []
        if data != "" {
          messages.push(
            @json.parse(data) catch {
              error => raise @mcp.ParseError(error.to_string())
            },
          )
        }
      }
      continue
    }
    if line.has_prefix("data:"[:]) {
      let value = line[5:]
      let value = if value.has_prefix(" "[:]) { value[1:] } else { value }
      data_lines.push(value.to_owned())
    }
  }
  if !data_lines.is_empty() {
    let data = data_lines.join("\n")
    if data != "" {
      messages.push(
        @json.parse(data) catch {
          error => raise @mcp.ParseError(error.to_string())
        },
      )
    }
  }
  if messages.is_empty() {
    raise @mcp.InvalidRequest("HTTP event stream contained no data event")
  }
  messages
}

///|
fn parse_http_messages(
  response : @async_http.Response,
  body : String,
) -> Array[Json] raise @mcp.McpError {
  match header(response.headers, "Content-Type") {
    Some(content_type) if has_media_type(content_type, "text/event-stream") =>
      parse_event_stream_messages(body)
    Some(content_type) if has_media_type(content_type, "application/json") => {
      let message : Json = @json.parse(body) catch {
        error => raise @mcp.ParseError(error.to_string())
      }
      [message]
    }
    Some(content_type) =>
      raise @mcp.InvalidRequest(
        "unsupported MCP HTTP response Content-Type: \{content_type}",
      )
    None => raise @mcp.InvalidRequest("MCP HTTP response omitted Content-Type")
  }
}

///|
fn validate_response_id(
  message : Json,
  expected_id : Json,
  context : String,
) -> Unit raise @mcp.McpError {
  if request_id(message) != Some(expected_id) {
    raise @mcp.InvalidRequest(
      "\{context} response id does not match request id",
    )
  }
}

///|
async fn Transport::send_response_once_with_notifications(
  self : Transport,
  request : Json,
  input_schema? : Json,
  on_notification~ : (Json) -> Unit,
) -> Json raise @mcp.McpError {
  guard request_id(request) is Some(expected_id) else {
    raise @mcp.InvalidRequest("HTTP request is missing its JSON-RPC id")
  }
  let headers = self.headers(request, input_schema?) catch {
    InvalidHeaderSchema(message)
    | InvalidHeaderValue(message)
    | HeaderMismatch(message) => raise @mcp.InvalidRequest(message)
  }
  let request_bytes = @utf8.encode(request.stringify())
  headers["Content-Length"] = request_bytes.length().to_string()
  let stream = @async_http.post_stream(self.endpoint, headers~) catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  defer stream.close()
  stream.write(request_bytes) catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  let response = stream.end_request() catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  if response_requires_authorization(response) && self.authorization is Some(_) {
    ignore(self.read_response_text(stream, response))
    self.authorize_challenge(response, request_operation(request))
    return self.send_response_once_with_notifications(
      request,
      input_schema?,
      on_notification~,
    )
  }
  guard response.code is (200..<300) else {
    let body = self.read_response_text(stream, response)
    raise http_error_to_mcp(response, body)
  }
  self.retry_policy.clear(
    self.authorization_resource,
    request_operation(request),
  )
  let content_type = match header(response.headers, "Content-Type") {
    Some(value) => value
    None => raise @mcp.InvalidRequest("MCP HTTP response omitted Content-Type")
  }
  if has_media_type(content_type, "application/json") {
    let body = self.read_response_text(stream, response)
    guard parse_http_messages(response, body) is [message] else {
      raise @mcp.InvalidRequest("HTTP JSON response must contain one message")
    }
    validate_response_id(message, expected_id, "HTTP")
    return message
  }
  guard has_media_type(content_type, "text/event-stream") else {
    raise @mcp.InvalidRequest("unsupported MCP HTTP response Content-Type")
  }
  let sse = SseReadState::new()
  while true {
    let data = read_sse_data(stream, sse, self.max_sse_event_bytes) catch {
      error => raise body_read_error_to_mcp(error)
    }
    guard data is Some(data) else { break }
    let message : Json = @json.parse(data) catch {
      error => raise @mcp.ParseError(error.to_string())
    }
    if is_jsonrpc_response(message) {
      validate_response_id(message, expected_id, "HTTP")
      return message
    }
    if is_jsonrpc_notification(message) {
      on_notification(message)
    }
  }
  raise @mcp.InvalidRequest("HTTP request did not return a JSON-RPC response")
}

///|
async fn Transport::send_response_with_notifications(
  self : Transport,
  request : Json,
  input_schema? : Json,
  on_notification~ : (Json) -> Unit,
) -> Json raise @mcp.McpError {
  let initial = request_with_protocol_version(
    request,
    self.protocol_version,
    false,
  )
  self.send_response_once_with_notifications(
    initial,
    input_schema?,
    on_notification~,
  ) catch {
    @mcp.UnsupportedProtocolVersion(supported~, ..) as version_error => {
      guard self.mutually_supported_protocol_version(supported)
        is Some(protocol_version) else {
        raise version_error
      }
      self.protocol_version = protocol_version
      let retry = request_with_protocol_version(request, protocol_version, true)
      self.send_response_once_with_notifications(
        retry,
        input_schema?,
        on_notification~,
      )
    }
    error => raise error
  }
}

///|
fn validate_notification_response(
  response : @async_http.Response,
  body : String,
) -> Unit raise @mcp.McpError {
  if response.code != 202 {
    if response.code is (200..<300) {
      raise @mcp.InvalidRequest(
        "HTTP notification response must use status 202",
      )
    }
    raise http_error_to_mcp(response, body)
  }
  if !body.is_empty() {
    raise @mcp.InvalidRequest(
      "HTTP notification response must have an empty body",
    )
  }
}

///|
async fn Transport::send_notification_once(
  self : Transport,
  notification : Json,
) -> Unit raise @mcp.McpError {
  let headers = self.headers(notification) catch {
    InvalidHeaderSchema(message)
    | InvalidHeaderValue(message)
    | HeaderMismatch(message) => raise @mcp.InvalidRequest(message)
  }
  let request_bytes = @utf8.encode(notification.stringify())
  headers["Content-Length"] = request_bytes.length().to_string()
  let stream = @async_http.post_stream(self.endpoint, headers~) catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  defer stream.close()
  stream.write(request_bytes) catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  let response = stream.end_request() catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  let body = self.read_response_text(stream, response)
  if response_requires_authorization(response) && self.authorization is Some(_) {
    self.authorize_challenge(response, request_operation(notification))
    return self.send_notification_once(notification)
  }
  validate_notification_response(response, body)
  self.retry_policy.clear(
    self.authorization_resource,
    request_operation(notification),
  )
}

///|
/// Send one JSON-RPC notification over Streamable HTTP. A conforming server
/// acknowledges it with HTTP 202 and no response body.
pub impl @client.ClientTransport for Transport with fn notify(
  self : Transport,
  notification : Json,
) -> Unit raise @mcp.McpError {
  let initial = notification_with_protocol_version(
    notification,
    self.protocol_version,
  )
  self.send_notification_once(initial) catch {
    @mcp.UnsupportedProtocolVersion(supported~, ..) as version_error => {
      guard self.mutually_supported_protocol_version(supported)
        is Some(protocol_version) else {
        raise version_error
      }
      self.protocol_version = protocol_version
      self.send_notification_once(
        notification_with_protocol_version(notification, protocol_version),
      )
    }
    error => raise error
  }
}

///|
fn Transport::filter_and_remember_tools(
  self : Transport,
  result : Json,
) -> Json {
  guard result is Object(fields) && fields.get("tools") is Some(Array(tools)) else {
    return result
  }
  let accepted : Array[Json] = []
  for tool in tools {
    match tool {
      Object({ "name": String(name), "inputSchema": input_schema, .. }) => {
        let valid = try validate_tool_header_schema(input_schema) catch {
          _ => false
        } noraise {
          _ => true
        }
        if valid {
          self.tool_schemas[name] = input_schema
          accepted.push(tool)
        }
      }
      _ => accepted.push(tool)
    }
  }
  fields["tools"] = Json::array(accepted)
  Json::object(fields)
}

///|
fn decode_raw_response(
  message : Json,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  @mcp.HandlerOutcome::decode_response(message)
}

///|
pub impl @client.ClientTransport for Transport with fn request_with_notifications(
  self : Transport,
  request : Json,
  on_notification~ : (Json) -> Unit,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  let response_json = self.send_response_with_notifications(
    request,
    on_notification~,
  )
  let outcome = decode_raw_response(response_json)
  match (request, outcome) {
    (Object({ "method": String("tools/list"), .. }), @mcp.Complete(result)) =>
      @mcp.Complete(self.filter_and_remember_tools(result))
    _ => outcome
  }
}

///|
pub impl @client.ClientTransport for Transport with fn close(self : Transport) -> Unit {
  ignore(self)
}
