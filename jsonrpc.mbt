///|
pub(all) enum RequestId {
  StringId(String)
  NumberId(Int)
} derive(Debug, Eq)

///|
pub fn RequestId::to_json(self : RequestId) -> Json {
  match self {
    StringId(value) => Json::string(value)
    NumberId(value) => Json::number(value.to_double(), repr="\{value}")
  }
}

///|
fn parse_request_id(value : Json) -> RequestId raise McpError {
  match value {
    String(value) => StringId(value)
    Number(value, repr=_) => NumberId(value.to_int())
    Null => raise InvalidRequest("JSON-RPC id must not be null")
    _ => raise InvalidRequest("JSON-RPC id must be a string or number")
  }
}

///|
pub(all) struct JsonRpcRequest {
  id : RequestId?
  method_name : String
  params : Json?
} derive(Debug, Eq)

///|
pub fn JsonRpcRequest::from_json(value : Json) -> JsonRpcRequest raise McpError {
  let fields = match value {
    Object(fields) => fields
    _ => raise InvalidRequest("JSON-RPC message must be an object")
  }
  match fields.get("jsonrpc") {
    Some(String("2.0")) => ()
    _ => raise InvalidRequest("jsonrpc must be \"2.0\"")
  }
  let method_name = get_string(fields, "method", "JSON-RPC request")
  let id = match fields.get("id") {
    Some(value) => Some(parse_request_id(value))
    None => None
  }
  { id, method_name, params: fields.get("params") }
}

///|
pub fn jsonrpc_success(id : RequestId, result : Json) -> Json {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id.to_json(),
    "result": result,
  })
}

///|
pub fn jsonrpc_error(id : RequestId?, error : McpError) -> Json {
  let fields : Map[String, Json] = {
    "jsonrpc": Json::string("2.0"),
    "error": error.to_json(),
  }
  match id {
    Some(id) => fields["id"] = id.to_json()
    None => fields["id"] = Json::null()
  }
  Json::object(fields)
}

///|
pub fn Server::handle_jsonrpc(self : Server, message : Json) -> Json? {
  let request = JsonRpcRequest::from_json(message) catch {
    error => return Some(jsonrpc_error(None, error))
  }
  try self.handle(request.method_name, request.params) catch {
    error =>
      match request.id {
        Some(id) => return Some(jsonrpc_error(Some(id), error))
        None => return None
      }
  } noraise {
    result =>
      match request.id {
        Some(id) =>
          match result {
            Some(result) => Some(jsonrpc_success(id, result))
            None =>
              Some(
                jsonrpc_error(
                  Some(id),
                  InvalidRequest("request method returned no result"),
                ),
              )
          }
        None => None
      }
  }
}
