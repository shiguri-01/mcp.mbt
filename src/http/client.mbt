///|
/// Stateless Streamable HTTP client for a single MCP endpoint.
pub struct Client {
  priv core : @mcp.Client
  priv endpoint : String
  priv supported_protocol_versions : Array[String]
  priv mut protocol_version : String
  priv tool_schemas : Map[String, Json]
  priv authorization : AuthorizationOptions?
  priv credential_cache : @auth.CredentialCache
  priv token_cache : @auth.TokenCache
  priv retry_policy : @auth.RetryPolicy
  priv mut authorization_issuer : String?
  priv authorization_resource : String
  priv authorization_resource_exact : Bool
  priv max_response_body_bytes : Int
  priv max_sse_event_bytes : Int
}

///|
/// Optional MCP Authorization configuration. HTTP delivery, user interaction,
/// and secure random generation remain explicit host responsibilities through
/// `AuthorizationProvider`.
pub struct AuthorizationOptions {
  priv provider : @auth.AuthorizationProvider
  priv redirect_uri : String
  priv client_name : String
  priv client_id_metadata_url : String?
  priv pre_registered : Map[String, @auth.ClientCredentials]
  priv wants_refresh_token : Bool
  priv resource_uri : String?
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
      allow_loopback_http=provider.allows_insecure_loopback(),
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
/// Create a modern MCP HTTP client. Every request carries a fresh copy of the
/// protocol version, client information, and client capabilities. Protocol
/// versions are listed in client preference order; an unsupported-version
/// response is retried once with the first version also supported by the
/// server.
pub fn Client::Client(
  endpoint : String,
  name? : String = "moonbit-http-client",
  version? : String = "0.2.0",
  capabilities? : @mcp.ClientCapabilities = @mcp.ClientCapabilities::empty(),
  extension_result_types? : Map[String, String] = Map([]),
  supported_protocol_versions? : Array[String] = [@mcp.latest_protocol_version],
  authorization? : AuthorizationOptions,
  max_response_body_bytes? : Int = default_max_response_body_bytes,
  max_sse_event_bytes? : Int = default_max_sse_event_bytes,
) -> Client raise @mcp.McpError {
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
      ignore(@auth.parse_absolute_uri(resource_uri)) catch {
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
    core: @mcp.Client(
      name~,
      version~,
      capabilities~,
      extension_result_types~,
      protocol_version~,
    ),
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
fn Client::headers(
  self : Client,
  request : Json,
  input_schema? : Json,
) -> Map[String, String] raise HttpHeaderError {
  let headers : Map[String, String] = {
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
  if input_schema is Some(schema) &&
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
fn response_requires_authorization(response : @async_http.Response) -> Bool {
  if response.code == 401 {
    return true
  }
  if response.code != 403 {
    return false
  }
  match header(response.headers, "WWW-Authenticate") {
    Some(value) => {
      let parsed = try @auth.parse_bearer_challenge(value) catch {
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
async fn Client::read_response_text(
  self : Client,
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
async fn Client::authorize_challenge(
  self : Client,
  response : @async_http.Response,
  operation : String,
) -> Unit raise @mcp.McpError {
  guard self.authorization is Some(options) else {
    raise @mcp.InvalidRequest("HTTP authorization is required")
  }
  let challenge = match header(response.headers, "WWW-Authenticate") {
    Some(value) =>
      Some(
        @auth.parse_bearer_challenge(value) catch {
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
  guard resource_metadata.authorization_servers() is [issuer, ..] else {
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
        allow_insecure_loopback=options.provider.allows_insecure_loopback(),
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
          if !(registration_response.status() is (200..<300)) {
            raise @mcp.InvalidRequest("dynamic registration was rejected")
          }
          let registration_json = @json.parse(registration_response.body()) catch {
            _ =>
              raise @mcp.InvalidRequest(
                "dynamic registration returned invalid JSON",
              )
          }
          @auth.parse_dynamic_registration_response(
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
    tokens.refresh_token() is Some(refresh_token) {
    let refreshed = try
      @auth.AuthorizationEngine(options.provider).refresh(
        metadata,
        credentials,
        refresh_token~,
        resource=self.authorization_resource,
        scopes=tokens.scope(),
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
  let previous_scopes = previous_tokens.map(tokens => tokens.scope())
  let scopes = match (challenge_error, challenge_scope, previous_scopes) {
    (Some("insufficient_scope"), Some(required), Some(previous)) =>
      @auth.step_up_scopes(previous, required)
    _ =>
      @auth.initial_scopes(
        challenge_scope?,
        resource_scopes?=resource_metadata.scopes_supported(),
        authorization_server_scopes?=metadata.scopes_supported(),
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
fn Client::mutually_supported_protocol_version(
  self : Client,
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
  match parsed {
    Object({ "error": Object(error_fields), .. }) =>
      match error_fields {
        { "code": Number(code, ..), "message": String(message), .. } => {
          let data = error_fields.get("data")
          @mcp.McpError::from_rpc_parts(code.to_int(), message, data?) catch {
            error => error
          }
        }
        _ => fallback
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
    // SSE comments, event names, retry values, and IDs do not carry MCP data.
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
priv enum SubscriptionStreamEvent {
  Acknowledged
  Notification(Json)
  Final(Json)
}

///|
priv struct SubscriptionStreamState {
  expected_id : Json
  requested : @mcp.SubscriptionFilter
  mut acknowledged : Bool
  mut subscription_id : Json
  mut honored : @mcp.SubscriptionFilter
}

///|
fn SubscriptionStreamState::new(
  expected_id : Json,
  requested : @mcp.SubscriptionFilter,
) -> SubscriptionStreamState {
  {
    expected_id,
    requested,
    acknowledged: false,
    subscription_id: Json::null(),
    honored: @mcp.SubscriptionFilter(),
  }
}

///|
fn subscription_filter_is_subset(
  honored : @mcp.SubscriptionFilter,
  requested : @mcp.SubscriptionFilter,
) -> Bool {
  (!honored.tools_list_changed || requested.tools_list_changed) &&
  (!honored.prompts_list_changed || requested.prompts_list_changed) &&
  (!honored.resources_list_changed || requested.resources_list_changed) &&
  honored.resource_subscriptions.all(uri => {
    requested.resource_subscriptions.contains(uri)
  })
}

///|
fn subscription_notification_allowed(
  subscription_id : Json,
  filter : @mcp.SubscriptionFilter,
  message : Json,
) -> Bool {
  guard message
    is Object(
      {
        "jsonrpc": String("2.0"),
        "method": String(method_name),
        "params": Object(params),
        "id"? : None,
        ..
      }
    ) &&
    params
    is {
      "_meta": Object(
        { "io.modelcontextprotocol/subscriptionId": event_id, .. }
      ),
      ..
    } &&
    event_id == subscription_id else {
    return false
  }
  match method_name {
    "notifications/tools/list_changed" => filter.tools_list_changed
    "notifications/prompts/list_changed" => filter.prompts_list_changed
    "notifications/resources/list_changed" => filter.resources_list_changed
    "notifications/resources/updated" =>
      match params.get("uri") {
        Some(String(uri)) => filter.resource_subscriptions.contains(uri)
        _ => false
      }
    _ => false
  }
}

///|
fn SubscriptionStreamState::consume(
  self : SubscriptionStreamState,
  message : Json,
) -> SubscriptionStreamEvent raise @mcp.McpError {
  if !self.acknowledged {
    guard message
      is Object(
        {
          "jsonrpc": String("2.0"),
          "method": String("notifications/subscriptions/acknowledged"),
          "params": Object(
            {
              "_meta": Object(
                {
                  "io.modelcontextprotocol/subscriptionId": subscription_id,
                  ..
                }
              ),
              "notifications": notifications,
              ..
            }
          ),
          "id"? : None,
          ..
        }
      ) else {
      raise @mcp.InvalidRequest(
        "subscription stream must start with an acknowledgement",
      )
    }
    let honored = @mcp.SubscriptionFilter::from_json(notifications)
    if subscription_id != self.expected_id {
      raise @mcp.InvalidRequest(
        "subscription acknowledgement id does not match request id",
      )
    }
    if !subscription_filter_is_subset(honored, self.requested) {
      raise @mcp.InvalidRequest(
        "subscription acknowledgement honors an unrequested filter",
      )
    }
    self.acknowledged = true
    self.subscription_id = subscription_id
    self.honored = honored
    return Acknowledged
  }
  if is_jsonrpc_notification(message) {
    if !subscription_notification_allowed(
        self.subscription_id,
        self.honored,
        message,
      ) {
      raise @mcp.InvalidRequest(
        "subscription notification does not match the acknowledged subscription",
      )
    }
    return Notification(message)
  }
  if message
    is Object(
      { "jsonrpc": String("2.0"), "id": response_id, "error": Object(_), .. }
    ) {
    if response_id != self.expected_id {
      raise @mcp.InvalidRequest(
        "subscription error response id does not match request id",
      )
    }
    return Final(message)
  }
  guard message
    is Object(
      {
        "jsonrpc": String("2.0"),
        "id": response_id,
        "result": Object(
          {
            "_meta": Object(
              { "io.modelcontextprotocol/subscriptionId": subscription_id, .. }
            ),
            ..
          }
        ),
        ..
      }
    ) &&
    response_id == self.expected_id &&
    subscription_id == self.subscription_id else {
    raise @mcp.InvalidRequest(
      "subscription final response does not match the active subscription",
    )
  }
  Final(message)
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
async fn Client::send_response_once_with_notifications(
  self : Client,
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
async fn Client::send_response_with_notifications(
  self : Client,
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
async fn Client::send_response(
  self : Client,
  request : Json,
  input_schema? : Json,
) -> Json raise @mcp.McpError {
  self.send_response_with_notifications(request, input_schema?, on_notification=fn(
    _,
  ) {

  })
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
async fn Client::send_notification_once(
  self : Client,
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
pub async fn Client::notify(
  self : Client,
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
/// Send one self-contained JSON-RPC request over Streamable HTTP.
pub async fn Client::request(
  self : Client,
  request : Json,
  input_schema? : Json,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.core.decode_response(self.send_response(request, input_schema?))
}

///|
/// Send a request while consuming request-scoped progress and logging
/// notifications as they arrive on an SSE response.
pub async fn Client::request_with_notifications(
  self : Client,
  request : Json,
  input_schema? : Json,
  on_notification~ : (Json) -> Unit,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.core.decode_response(
    self.send_response_with_notifications(
      request,
      input_schema?,
      on_notification~,
    ),
  )
}

///|
/// Discover server capabilities and supported protocol versions.
pub async fn Client::discover(
  self : Client,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.DiscoverResult raise @mcp.McpError {
  self.core.decode_discover(
    self.send_response(self.core.discover_request(options~)),
  )
}

///|
fn Client::filter_and_remember_tools(self : Client, result : Json) -> Json {
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
fn require_complete(
  outcome : @mcp.HandlerOutcome[Json],
  method_name : String,
) -> Json raise @mcp.McpError {
  match outcome {
    @mcp.Complete(result) => result
    @mcp.InputRequired(_) =>
      raise @mcp.InvalidRequest("\{method_name} cannot require MRTR input")
    @mcp.ExtensionResult(result_type, _) =>
      raise @mcp.InvalidRequest(
        "\{method_name} cannot return extension result type \{result_type}",
      )
  }
}

///|
/// List tools, excluding invalid `x-mcp-header` definitions and remembering
/// valid schemas for subsequent `call_tool` requests.
pub async fn Client::list_tools_raw(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  let result = require_complete(
    self.request(self.core.list_tools_request(cursor?, options~)),
    "tools/list",
  )
  self.filter_and_remember_tools(result)
}

///|
/// List tools as the canonical domain result. Use `list_tools_raw` to inspect
/// extension fields that are not represented by the core specification.
pub async fn Client::list_tools(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.ListToolsResult raise @mcp.McpError {
  @mcp.decode_list_tools_result(self.list_tools_raw(cursor?, options~))
}

///|
/// Call a tool. Pass `input_schema` to call directly, or call `list_tools`
/// first so the client can use its validated schema cache.
pub async fn Client::call_tool_raw(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  input_schema? : Json,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  let schema = match input_schema {
    Some(schema) => Some(schema)
    None => self.tool_schemas.get(name)
  }
  self.request(
    self.core.call_tool_request(name~, arguments~, options~),
    input_schema?=schema,
  )
}

///|
/// Call a tool and decode every complete response into `CallToolResult`.
pub async fn Client::call_tool(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  input_schema? : Json,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[@mcp.CallToolResult] raise @mcp.McpError {
  match self.call_tool_raw(name~, arguments~, input_schema?, options~) {
    Complete(result) => Complete(@mcp.decode_call_tool_result(result))
    InputRequired(value) => InputRequired(value)
    ExtensionResult(result_type, value) => ExtensionResult(result_type, value)
  }
}

///|
/// Call a tool and decode its `structuredContent` as `T`.
pub async fn[T : FromJson] Client::call_tool_as(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  input_schema? : Json,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[T] raise @mcp.McpError {
  match self.call_tool_raw(name~, arguments~, input_schema?, options~) {
    Complete(result) => Complete(@mcp.decode_structured_content(result))
    InputRequired(value) => InputRequired(value)
    ExtensionResult(result_type, value) => ExtensionResult(result_type, value)
  }
}

///|
pub async fn Client::list_resources_raw(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  require_complete(
    self.request(self.core.list_resources_request(cursor?, options~)),
    "resources/list",
  )
}

///|
pub async fn Client::list_resources(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.ListResourcesResult raise @mcp.McpError {
  @mcp.decode_list_resources_result(self.list_resources_raw(cursor?, options~))
}

///|
pub async fn Client::list_resource_templates_raw(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  require_complete(
    self.request(self.core.list_resource_templates_request(cursor?, options~)),
    "resources/templates/list",
  )
}

///|
pub async fn Client::list_resource_templates(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.ListResourceTemplatesResult raise @mcp.McpError {
  @mcp.decode_list_resource_templates_result(
    self.list_resource_templates_raw(cursor?, options~),
  )
}

///|
pub async fn Client::read_resource_raw(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.request(self.core.read_resource_request(uri~, options~))
}

///|
pub async fn Client::read_resource(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[@mcp.ReadResourceResult] raise @mcp.McpError {
  match self.read_resource_raw(uri~, options~) {
    Complete(result) => Complete(@mcp.decode_read_resource_result(result))
    InputRequired(value) => InputRequired(value)
    ExtensionResult(result_type, value) => ExtensionResult(result_type, value)
  }
}

///|
pub async fn Client::list_prompts_raw(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  require_complete(
    self.request(self.core.list_prompts_request(cursor?, options~)),
    "prompts/list",
  )
}

///|
pub async fn Client::list_prompts(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.ListPromptsResult raise @mcp.McpError {
  @mcp.decode_list_prompts_result(self.list_prompts_raw(cursor?, options~))
}

///|
pub async fn Client::get_prompt_raw(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.request(self.core.get_prompt_request(name~, arguments~, options~))
}

///|
pub async fn Client::get_prompt(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[@mcp.GetPromptResult] raise @mcp.McpError {
  match self.get_prompt_raw(name~, arguments~, options~) {
    Complete(result) => Complete(@mcp.decode_get_prompt_result(result))
    InputRequired(value) => InputRequired(value)
    ExtensionResult(result_type, value) => ExtensionResult(result_type, value)
  }
}

///|
pub async fn Client::complete_raw(
  self : Client,
  reference~ : @mcp.CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  require_complete(
    self.request(
      self.core.complete_request(
        reference~,
        argument_name~,
        argument_value~,
        context_arguments?,
        options~,
      ),
    ),
    "completion/complete",
  )
}

///|
pub async fn Client::complete(
  self : Client,
  reference~ : @mcp.CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.CompleteResult raise @mcp.McpError {
  @mcp.decode_complete_result(
    self.complete_raw(
      reference~,
      argument_name~,
      argument_value~,
      context_arguments?,
      options~,
    ),
  )
}

///|
async fn Client::listen_once(
  self : Client,
  request : Json,
  notifications~ : @mcp.SubscriptionFilter,
  on_notification~ : (Json) -> Unit,
) -> Json raise @mcp.McpError {
  guard request_id(request) is Some(expected_id) else {
    raise @mcp.InvalidRequest("subscriptions/listen request is missing its id")
  }
  let headers = self.headers(request) catch {
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
    return self.listen_once(request, notifications~, on_notification~)
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
    let message : Json = @json.parse(body) catch {
      error => raise @mcp.ParseError(error.to_string())
    }
    validate_response_id(message, expected_id, "subscription")
    return require_complete(
      self.core.decode_response(message),
      "subscriptions/listen",
    )
  }
  guard has_media_type(content_type, "text/event-stream") else {
    raise @mcp.InvalidRequest(
      "subscriptions/listen requires a text/event-stream response",
    )
  }
  let state = SubscriptionStreamState::new(expected_id, notifications)
  let sse = SseReadState::new()
  while true {
    let data = read_sse_data(stream, sse, self.max_sse_event_bytes) catch {
      error => raise body_read_error_to_mcp(error)
    }
    guard data is Some(data) else { break }
    let message : Json = @json.parse(data) catch {
      error => raise @mcp.ParseError(error.to_string())
    }
    match state.consume(message) {
      Acknowledged => ()
      Notification(notification) => on_notification(notification)
      Final(response) =>
        return require_complete(
          self.core.decode_response(response),
          "subscriptions/listen",
        )
    }
  }
  raise @mcp.InvalidRequest(
    "subscription stream ended without a final JSON-RPC response",
  )
}

///|
/// Listen for subscribed notifications and invoke `on_notification` as each
/// complete SSE data event arrives. Closing the underlying stream cancels the
/// request at the transport layer.
pub async fn Client::listen(
  self : Client,
  notifications~ : @mcp.SubscriptionFilter,
  on_notification~ : (Json) -> Unit,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> Json raise @mcp.McpError {
  let request = self.core.listen_request(notifications~, options~)
  let initial = request_with_protocol_version(
    request,
    self.protocol_version,
    false,
  )
  self.listen_once(initial, notifications~, on_notification~) catch {
    @mcp.UnsupportedProtocolVersion(supported~, ..) as version_error => {
      guard self.mutually_supported_protocol_version(supported)
        is Some(protocol_version) else {
        raise version_error
      }
      self.protocol_version = protocol_version
      self.listen_once(
        request_with_protocol_version(request, protocol_version, true),
        notifications~,
        on_notification~,
      )
    }
    error => raise error
  }
}

///|
/// Resolve bounded multi-round-trip tool input requests. Each retry gets a
/// fresh JSON-RPC ID while `retry_options` preserves opaque request state.
pub async fn Client::call_tool_resolving_raw(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  input_schema? : Json,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> Json raise @mcp.McpError {
  if max_rounds <= 0 {
    raise @mcp.InvalidParams("max_rounds must be positive")
  }
  let mut retry_options = options
  for _ in 0..<max_rounds {
    match
      self.call_tool_raw(
        name~,
        arguments~,
        input_schema?,
        options=retry_options,
      ) {
      @mcp.Complete(result) => return result
      @mcp.InputRequired(required) => {
        let requests = required.input_requests().unwrap_or(Map([]))
        retry_options = required.retry_options(
          resolve(requests),
          base=retry_options,
        )
      }
      @mcp.ExtensionResult(_, result) => return result
    }
  }
  raise @mcp.InvalidRequest("MRTR exceeded max_rounds")
}

///|
/// Resolve bounded MRTR input and decode the final tool result.
pub async fn Client::call_tool_resolving(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  input_schema? : Json,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> @mcp.CallToolResult raise @mcp.McpError {
  @mcp.decode_call_tool_result(
    self.call_tool_resolving_raw(
      name~,
      arguments~,
      input_schema?,
      options~,
      max_rounds~,
      resolve~,
    ),
  )
}

///|
pub async fn Client::read_resource_resolving_raw(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> Json raise @mcp.McpError {
  if max_rounds <= 0 {
    raise @mcp.InvalidParams("max_rounds must be positive")
  }
  let mut retry_options = options
  for _ in 0..<max_rounds {
    match self.read_resource_raw(uri~, options=retry_options) {
      @mcp.Complete(result) => return result
      @mcp.InputRequired(required) => {
        let requests = required.input_requests().unwrap_or(Map([]))
        retry_options = required.retry_options(
          resolve(requests),
          base=retry_options,
        )
      }
      @mcp.ExtensionResult(_, result) => return result
    }
  }
  raise @mcp.InvalidRequest("MRTR exceeded max_rounds")
}

///|
pub async fn Client::read_resource_resolving(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> @mcp.ReadResourceResult raise @mcp.McpError {
  @mcp.decode_read_resource_result(
    self.read_resource_resolving_raw(uri~, options~, max_rounds~, resolve~),
  )
}

///|
pub async fn Client::get_prompt_resolving_raw(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> Json raise @mcp.McpError {
  if max_rounds <= 0 {
    raise @mcp.InvalidParams("max_rounds must be positive")
  }
  let mut retry_options = options
  for _ in 0..<max_rounds {
    match self.get_prompt_raw(name~, arguments~, options=retry_options) {
      @mcp.Complete(result) => return result
      @mcp.InputRequired(required) => {
        let requests = required.input_requests().unwrap_or(Map([]))
        retry_options = required.retry_options(
          resolve(requests),
          base=retry_options,
        )
      }
      @mcp.ExtensionResult(_, result) => return result
    }
  }
  raise @mcp.InvalidRequest("MRTR exceeded max_rounds")
}

///|
pub async fn Client::get_prompt_resolving(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> @mcp.GetPromptResult raise @mcp.McpError {
  @mcp.decode_get_prompt_result(
    self.get_prompt_resolving_raw(
      name~,
      arguments~,
      options~,
      max_rounds~,
      resolve~,
    ),
  )
}
