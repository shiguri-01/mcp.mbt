///|

///|
fn parse_request_id(value : Json) -> Json raise McpError {
  match value {
    String(_) | Number(_) => value
    Null => raise InvalidRequest("JSON-RPC id must not be null")
    _ => raise InvalidRequest("JSON-RPC id must be a string or number")
  }
}

///|
fn parse_jsonrpc_message(value : Json) -> (Json?, String, Json?) raise McpError {
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
  (id, method_name, fields.get("params"))
}

///|
fn jsonrpc_success(id : Json, result : Json) -> Json {
  Json::object({ "jsonrpc": Json::string("2.0"), "id": id, "result": result })
}

///|
fn jsonrpc_error(id : Json?, error : McpError) -> Json {
  let fields : Map[String, Json] = {
    "jsonrpc": Json::string("2.0"),
    "error": error.to_json(),
  }
  match id {
    Some(id) => fields["id"] = id
    None => fields["id"] = Json::null()
  }
  Json::object(fields)
}

///|
/// Handle one JSON-RPC message for transport implementations.
pub fn Server::handle_jsonrpc(self : Server, message : Json) -> Json? {
  let (id, method_name, params) = parse_jsonrpc_message(message) catch {
    error => return Some(jsonrpc_error(None, error))
  }
  try self.dispatch(method_name, params) catch {
    error =>
      match id {
        Some(id) => return Some(jsonrpc_error(Some(id), error))
        None => return None
      }
  } noraise {
    result =>
      match id {
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
