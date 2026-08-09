///|
/// Stateless Streamable HTTP client for a single MCP endpoint.
pub struct Client {
  priv core : @mcp.Client
  priv endpoint : String
  priv tool_schemas : Map[String, Json]
}

///|
/// Create a modern MCP HTTP client. Every request carries a fresh copy of the
/// protocol version, client information, and client capabilities.
pub fn Client::Client(
  endpoint : String,
  name? : String = "moonbit-http-client",
  version? : String = "0.2.0",
  capabilities? : @mcp.ClientCapabilities = @mcp.ClientCapabilities::empty(),
) -> Client {
  {
    core: @mcp.Client(name~, version~, capabilities~),
    endpoint,
    tool_schemas: Map([]),
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
  for
    name, value in standard_request_headers(
      request,
      self.core.protocol_version(),
    ) {
    headers[name] = value
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
async fn Client::send_messages(
  self : Client,
  request : Json,
  input_schema? : Json,
) -> Array[Json] raise @mcp.McpError {
  let headers = self.headers(request, input_schema?) catch {
    InvalidHeaderSchema(message)
    | InvalidHeaderValue(message)
    | HeaderMismatch(message) => raise @mcp.InvalidRequest(message)
  }
  let (response, data) = @async_http.post(
    self.endpoint,
    @utf8.encode(request.stringify()),
    headers~,
  ) catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  let body = data.text() catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  guard response.code is (200..<300) else {
    raise http_error_to_mcp(response, body)
  }
  parse_http_messages(response, body)
}

///|
async fn Client::send_response(
  self : Client,
  request : Json,
  input_schema? : Json,
) -> Json raise @mcp.McpError {
  guard request_id(request) is Some(expected_id) else {
    raise @mcp.InvalidRequest("HTTP request is missing its JSON-RPC id")
  }
  for message in self.send_messages(request, input_schema?) {
    if is_jsonrpc_response(message) {
      validate_response_id(message, expected_id, "HTTP")
      return message
    }
  }
  raise @mcp.InvalidRequest("HTTP request did not return a JSON-RPC response")
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
  }
}

///|
/// List tools, excluding invalid `x-mcp-header` definitions and remembering
/// valid schemas for subsequent `call_tool` requests.
pub async fn Client::list_tools(
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
/// Call a tool. Pass `input_schema` to call directly, or call `list_tools`
/// first so the client can use its validated schema cache.
pub async fn Client::call_tool(
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
pub async fn Client::list_resources(
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
pub async fn Client::list_resource_templates(
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
pub async fn Client::read_resource(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.request(self.core.read_resource_request(uri~, options~))
}

///|
pub async fn Client::list_prompts(
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
pub async fn Client::get_prompt(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = @mcp.RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.request(self.core.get_prompt_request(name~, arguments~, options~))
}

///|
pub async fn Client::complete(
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
  guard response.code is (200..<300) else {
    let body = stream.read_all().text() catch {
        error => raise @mcp.InternalError(error.to_string())
      }
    raise http_error_to_mcp(response, body)
  }
  let content_type = match header(response.headers, "Content-Type") {
    Some(value) => value
    None => raise @mcp.InvalidRequest("MCP HTTP response omitted Content-Type")
  }
  if has_media_type(content_type, "application/json") {
    let body = stream.read_all().text() catch {
        error => raise @mcp.InternalError(error.to_string())
      }
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
  let mut data_lines : Array[String] = []
  while true {
    let next_line = stream.read_until("\n") catch {
      error => raise @mcp.InternalError(error.to_string())
    }
    guard next_line is Some(raw_line) else { break }
    let line = raw_line.trim_end(chars="\r")
    if line == "" {
      if !data_lines.is_empty() {
        let data = data_lines.join("\n")
        data_lines = []
        if data != "" {
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
      }
    } else if line.has_prefix("data:"[:]) {
      let value = line[5:]
      data_lines.push(
        if value.has_prefix(" "[:]) {
          value[1:].to_owned()
        } else {
          value.to_owned()
        },
      )
    }
  }
  if !data_lines.is_empty() {
    let data = data_lines.join("\n")
    if data != "" {
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
  }
  raise @mcp.InvalidRequest(
    "subscription stream ended without a final JSON-RPC response",
  )
}

///|
/// Resolve bounded multi-round-trip tool input requests. Each retry gets a
/// fresh JSON-RPC ID while `retry_options` preserves opaque request state.
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
) -> Json raise @mcp.McpError {
  if max_rounds <= 0 {
    raise @mcp.InvalidParams("max_rounds must be positive")
  }
  let mut retry_options = options
  for _ in 0..<max_rounds {
    match
      self.call_tool(name~, arguments~, input_schema?, options=retry_options) {
      @mcp.Complete(result) => return result
      @mcp.InputRequired(required) => {
        let requests = required.input_requests().unwrap_or(Map([]))
        retry_options = required.retry_options(resolve(requests))
      }
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
) -> Json raise @mcp.McpError {
  if max_rounds <= 0 {
    raise @mcp.InvalidParams("max_rounds must be positive")
  }
  let mut retry_options = options
  for _ in 0..<max_rounds {
    match self.read_resource(uri~, options=retry_options) {
      @mcp.Complete(result) => return result
      @mcp.InputRequired(required) => {
        let requests = required.input_requests().unwrap_or(Map([]))
        retry_options = required.retry_options(resolve(requests))
      }
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
) -> Json raise @mcp.McpError {
  if max_rounds <= 0 {
    raise @mcp.InvalidParams("max_rounds must be positive")
  }
  let mut retry_options = options
  for _ in 0..<max_rounds {
    match self.get_prompt(name~, arguments~, options=retry_options) {
      @mcp.Complete(result) => return result
      @mcp.InputRequired(required) => {
        let requests = required.input_requests().unwrap_or(Map([]))
        retry_options = required.retry_options(resolve(requests))
      }
    }
  }
  raise @mcp.InvalidRequest("MRTR exceeded max_rounds")
}
