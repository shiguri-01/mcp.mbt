///|
pub struct Client {
  priv mut next_id : Int
}

///|
pub fn Client::Client() -> Client {
  { next_id: 1 }
}

///|
fn Client::next_request_id(self : Client) -> Json {
  let id = self.next_id
  self.next_id = self.next_id + 1
  Json::number(id.to_double(), repr="\{id}")
}

///|
fn jsonrpc_request(id : Json, method_name : String, params? : Json) -> Json {
  let fields : Map[String, Json] = {
    "jsonrpc": Json::string("2.0"),
    "id": id,
    "method": Json::string(method_name),
  }
  put_optional_json(fields, "params", params)
  Json::object(fields)
}

///|
fn jsonrpc_notification(method_name : String, params? : Json) -> Json {
  let fields : Map[String, Json] = {
    "jsonrpc": Json::string("2.0"),
    "method": Json::string(method_name),
  }
  put_optional_json(fields, "params", params)
  Json::object(fields)
}

///|
pub fn structured_content(result : Json) -> Json raise McpError {
  let fields = expect_object(result, "tools/call result")
  match fields.get("structuredContent") {
    Some(value) => value
    None => raise InvalidRequest("tools/call result has no structuredContent")
  }
}

///|
pub fn[T : FromJson] decode_structured_content(
  result : Json,
) -> T raise McpError {
  @json.from_json(structured_content(result)) catch {
    error => raise InvalidParams(error.to_string())
  }
}

///|
pub fn Client::initialize_request(
  self : Client,
  client_name~ : String,
  client_version~ : String,
  capabilities? : Json = Json::object({}),
) -> Json {
  jsonrpc_request(
    self.next_request_id(),
    "initialize",
    params=Json::object({
      "protocolVersion": Json::string(latest_protocol_version),
      "capabilities": capabilities,
      "clientInfo": Json::object({
        "name": Json::string(client_name),
        "version": Json::string(client_version),
      }),
    }),
  )
}

///|
pub fn Client::initialized_notification(_self : Client) -> Json {
  jsonrpc_notification("notifications/initialized")
}

///|
pub fn Client::list_tools_request(self : Client) -> Json {
  jsonrpc_request(self.next_request_id(), "tools/list")
}

///|
pub fn Client::call_tool_request(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
) -> Json {
  jsonrpc_request(
    self.next_request_id(),
    "tools/call",
    params=Json::object({ "name": Json::string(name), "arguments": arguments }),
  )
}

///|
pub fn Client::list_resources_request(self : Client) -> Json {
  jsonrpc_request(self.next_request_id(), "resources/list")
}

///|
pub fn Client::read_resource_request(self : Client, uri~ : String) -> Json {
  jsonrpc_request(
    self.next_request_id(),
    "resources/read",
    params=Json::object({ "uri": Json::string(uri) }),
  )
}

///|
pub fn Client::list_prompts_request(self : Client) -> Json {
  jsonrpc_request(self.next_request_id(), "prompts/list")
}

///|
pub fn Client::get_prompt_request(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
) -> Json {
  jsonrpc_request(
    self.next_request_id(),
    "prompts/get",
    params=Json::object({ "name": Json::string(name), "arguments": arguments }),
  )
}
