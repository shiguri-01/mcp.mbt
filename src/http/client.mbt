///|
pub struct Client {
  priv core : @mcp.Client
  priv endpoint : String
  priv mut session_id : String?
  priv mut protocol_version : String?
}

///|
pub fn Client::Client(endpoint : String) -> Client {
  { core: @mcp.Client(), endpoint, session_id: None, protocol_version: None }
}

///|
pub fn Client::session_id(self : Client) -> String? {
  self.session_id
}

///|
fn Client::headers(self : Client, request : Json) -> Map[String, String] {
  let headers : Map[String, String] = {
    "Accept": "application/json, text/event-stream",
    "Content-Type": "application/json",
    "MCP-Protocol-Version": self.protocol_version.unwrap_or(
      @mcp.latest_protocol_version,
    ),
  }
  if self.session_id is Some(session_id) {
    headers["MCP-Session-Id"] = session_id
  }
  if request_method_name(request) is Some(method_name) {
    headers["Mcp-Method"] = method_name
  }
  if named_request_value(request) is Some(name) {
    headers["Mcp-Name"] = name
  }
  headers
}

///|
fn http_error_to_mcp(
  response : @async_http.Response,
  body : String,
) -> @mcp.McpError {
  let parsed = @json.parse(body) catch {
    _ => return @mcp.InvalidRequest("HTTP \{response.code} \{response.reason}")
  }
  match parsed {
    Object({ "error": Object({ "message": String(message), .. }), .. }) =>
      @mcp.InvalidRequest(message)
    _ => @mcp.InvalidRequest("HTTP \{response.code} \{response.reason}")
  }
}

///|
fn split_endpoint(endpoint : String) -> (String, String) raise @mcp.McpError {
  match endpoint.find("://") {
    Some(protocol_end) =>
      match endpoint[protocol_end + 3:].find("/") {
        Some(path_start) => {
          let split = protocol_end + 3 + path_start
          (endpoint[:split].to_owned(), endpoint[split:].to_owned())
        }
        None => (endpoint, "/")
      }
    None => raise @mcp.InvalidParams("HTTP endpoint must include a protocol")
  }
}

///|
pub async fn Client::request(
  self : Client,
  request : Json,
) -> Json raise @mcp.McpError {
  let (response, data) = @async_http.post(
    self.endpoint,
    @utf8.encode(request.stringify()),
    headers=self.headers(request),
  ) catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  let body = data.text() catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  guard response.code is (200..<300) else {
    raise http_error_to_mcp(response, body)
  }
  if response.headers.get("mcp-session-id") is Some(session_id) {
    self.session_id = Some(session_id)
  }
  let message = @json.parse(body) catch {
    error => raise @mcp.ParseError(error.to_string())
  }
  match self.core.receive_jsonrpc(message) {
    Some(result) => result
    None =>
      raise @mcp.InvalidRequest(
        "HTTP request did not return a JSON-RPC response",
      )
  }
}

///|
pub async fn Client::notify(
  self : Client,
  notification : Json,
) -> Unit raise @mcp.McpError {
  let (response, data) = @async_http.post(
    self.endpoint,
    @utf8.encode(notification.stringify()),
    headers=self.headers(notification),
  ) catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  guard response.code is (200..<300) else {
    let body = data.text() catch {
      error => raise @mcp.InternalError(error.to_string())
    }
    raise http_error_to_mcp(response, body)
  }
}

///|
pub async fn Client::initialize(
  self : Client,
  client_name~ : String,
  client_version~ : String,
  capabilities? : @mcp.ClientCapabilities = @mcp.ClientCapabilities::empty(),
) -> Json raise @mcp.McpError {
  let response = self.request(
    self.core.initialize_request(client_name~, client_version~, capabilities~),
  )
  self.protocol_version = Some(@mcp.latest_protocol_version)
  self.notify(self.core.initialized_notification())
  response
}

///|
pub async fn Client::close_session(self : Client) -> Unit raise @mcp.McpError {
  let session_id = match self.session_id {
    Some(session_id) => session_id
    None => return
  }
  let headers : Map[String, String] = { "MCP-Session-Id": session_id }
  let (base, path) = split_endpoint(self.endpoint)
  let client = @async_http.Client(base) catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  defer client.close()
  client.request(Delete, path, extra_headers=headers) catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  let response = client.end_request() catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  guard response.code is (200..<300) || response.code == 404 else {
    raise @mcp.InvalidRequest("HTTP \{response.code} \{response.reason}")
  }
  self.session_id = None
}

///|
pub async fn Client::list_tools(
  self : Client,
  cursor? : String,
) -> Json raise @mcp.McpError {
  self.request(self.core.list_tools_request(cursor?))
}

///|
pub async fn Client::call_tool(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
) -> Json raise @mcp.McpError {
  self.request(self.core.call_tool_request(name~, arguments~))
}
