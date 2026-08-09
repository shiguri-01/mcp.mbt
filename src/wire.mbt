///|
/// A validated inbound JSON-RPC request. MCP does not support JSON-RPC batches.
priv struct RpcRequest {
  id : Json
  method_name : String
  params : Json
}

///|
fn parse_rpc_request(message : Json) -> RpcRequest raise McpError {
  guard message is Object(fields) else {
    raise InvalidRequest("MCP messages must be single JSON-RPC objects")
  }
  guard fields.get("jsonrpc") == Some(Json::string("2.0")) else {
    raise InvalidRequest("jsonrpc must be \"2.0\"")
  }
  let id = match fields.get("id") {
    Some(String(_) as id) | Some(Number(_) as id) => id
    Some(_) => raise InvalidRequest("request id must be a string or number")
    None => raise InvalidRequest("MCP server methods must be requests")
  }
  let method_name = match fields.get("method") {
    Some(String(value)) => value
    _ => raise InvalidRequest("request method must be a string")
  }
  let params = match fields.get("params") {
    Some(Object(_) as value) => value
    Some(_) => raise InvalidParams("request params must be an object")
    None => raise InvalidParams("request params are required")
  }
  { id, method_name, params }
}

///|
fn rpc_request(id : Json, method_name : String, params : Json) -> Json {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id,
    "method": Json::string(method_name),
    "params": params,
  })
}

///|
fn rpc_notification(method_name : String, params : Json) -> Json {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string(method_name),
    "params": params,
  })
}

///|
fn jsonrpc_notification(method_name : String, params? : Json) -> Json {
  rpc_notification(method_name, params.unwrap_or(Json::object({})))
}

///|
fn rpc_result_response(id : Json, result : Json) -> Json {
  Json::object({ "jsonrpc": Json::string("2.0"), "id": id, "result": result })
}

///|
fn rpc_error_response(id : Json?, error : McpError) -> Json {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id.unwrap_or(Json::null()),
    "error": error.to_json(),
  })
}

///|
fn rpc_response_id(message : Json) -> Json raise McpError {
  let fields = expect_object(message, "JSON-RPC response")
  guard fields.get("jsonrpc") == Some(Json::string("2.0")) else {
    raise InvalidRequest("response jsonrpc must be \"2.0\"")
  }
  match fields.get("id") {
    Some(String(_) as id) | Some(Number(_) as id) => id
    _ => raise InvalidRequest("response id must be a string or number")
  }
}

///|
fn rpc_response_result(message : Json) -> Json raise McpError {
  ignore(rpc_response_id(message))
  let fields = expect_object(message, "JSON-RPC response")
  match (fields.get("result"), fields.get("error")) {
    (Some(result), None) => result
    (None, Some(Object(error))) => {
      let code_value = match error.get("code") {
        Some(Number(value, ..)) => value
        _ => raise InvalidRequest("response error.code must be a number")
      }
      let code = code_value.to_int()
      if code.to_double() != code_value {
        raise InvalidRequest("response error.code must be an integer")
      }
      let message = get_string(error, "message", "response error")
      raise McpError::from_rpc_parts(code, message, data?=error.get("data"))
    }
    _ =>
      raise InvalidRequest(
        "response must contain exactly one of result or error",
      )
  }
}

///|
fn require_result_type(result : Json) -> String raise McpError {
  let fields = expect_object(result, "MCP result")
  match fields.get("resultType") {
    Some(String("complete")) => "complete"
    Some(String("input_required")) => "input_required"
    Some(String(value)) => raise InvalidRequest("unknown resultType: \{value}")
    Some(_) => raise InvalidRequest("resultType must be a string")
    None => raise InvalidRequest("resultType is required by MCP 2026-07-28")
  }
}
