///|
/// MCP's wire layer is an adapter around the canonical JSON-RPC package.
///
/// JSON-RPC framing, ids, and envelope validation live in `jsonrpc`. This
/// file only translates that package's result into MCP errors and applies
/// MCP-specific result rules. There is deliberately no second JSON-RPC
/// implementation in the MCP package.
priv struct RpcRequest {
  id : @jsonrpc.RequestId
  method_name : String
  params : Map[String, Json]
}

///|
fn jsonrpc_error(error : @jsonrpc.JsonRpcDecodeError) -> McpError {
  match error {
    @jsonrpc.JsonRpcDecodeError::InvalidMessage(message) =>
      InvalidRequest(message)
  }
}

///|
fn parse_rpc_request(message : Json) -> RpcRequest raise McpError {
  let decoded = @jsonrpc.decode(message) catch {
    error => raise jsonrpc_error(error)
  }
  match decoded {
    @jsonrpc.Message::Request(request) => {
      let id = request.id
      let method_name = request.method_name
      let params = match request.params {
        Object(fields) => fields
        _ => raise InvalidParams("request params must be an object")
      }
      { id, method_name, params }
    }
    @jsonrpc.Message::Notification(_) =>
      raise InvalidRequest("MCP server methods must be requests")
    @jsonrpc.Message::Response(_) =>
      raise InvalidRequest("MCP server expected a request")
  }
}

///|
fn rpc_request(id : Json, method_name : String, params : Json) -> Json {
  let request_id : @jsonrpc.RequestId = @json.from_json(id) catch {
    _ => return Json::null()
  }
  @jsonrpc.Request(id=request_id, method_name~, params~).to_json() catch {
    _ => Json::null()
  }
}

///|
fn rpc_notification(method_name : String, params : Json) -> Json {
  @jsonrpc.Notification(method_name~, params~).to_json() catch {
    _ => Json::null()
  }
}

///|
fn jsonrpc_notification(method_name : String, params? : Json) -> Json {
  rpc_notification(method_name, params.unwrap_or(Json::object({})))
}

///|
fn rpc_result_response(id : Json, result : Json) -> Json {
  let request_id : @jsonrpc.RequestId = @json.from_json(id) catch {
    _ => return Json::null()
  }
  @jsonrpc.response_success(id=request_id, result~).to_json()
}

///|
fn rpc_error_response(id : @jsonrpc.RequestId?, error : McpError) -> Json {
  let error_object = error.to_error_object()
  match id {
    Some(id) => {
      let response : @jsonrpc.Response[Json] = @jsonrpc.response_failure(
        id~,
        error=error_object,
      )
      response.to_json()
    }
    None =>
      Json::object({
        "jsonrpc": Json::string(@jsonrpc.JSON_RPC_VERSION),
        "id": Json::null(),
        "error": error_object.to_json(),
      })
  }
}

///|
fn rpc_response_result(message : Json) -> Json raise McpError {
  let decoded = @jsonrpc.decode(message) catch {
    error => raise jsonrpc_error(error)
  }
  match decoded {
    @jsonrpc.Message::Response(@jsonrpc.Response::Success(result~, ..)) =>
      result
    @jsonrpc.Message::Response(@jsonrpc.Response::Failure(error~, ..)) =>
      raise McpError::from_error_object(error)
    _ => raise InvalidRequest("JSON-RPC response expected")
  }
}

///|
fn require_result_type(result : Json) -> String raise McpError {
  let fields = expect_object(result, "MCP result")
  match fields.get("resultType") {
    Some(String("complete")) => "complete"
    Some(String("input_required")) => "input_required"
    Some(String(value)) => value
    Some(_) => raise InvalidRequest("resultType must be a string")
    None => "complete"
  }
}

///|
fn is_rpc_notification(message : Json) -> Bool {
  let decoded = @jsonrpc.decode(message) catch { _ => return false }
  match decoded {
    @jsonrpc.Message::Notification(_) => true
    _ => false
  }
}
