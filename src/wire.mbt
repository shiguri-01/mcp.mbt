///|
/// MCP's wire layer bridges the transport layer and the canonical `jsonrpc` package.
///
/// It translates JSON-RPC envelopes into MCP semantics and errors without
/// re-implementing JSON-RPC wire parsing.
pub fn jsonrpc_error(error : @jsonrpc.JsonRpcDecodeError) -> McpError {
  match error {
    @jsonrpc.JsonRpcDecodeError::InvalidMessage(message) =>
      InvalidRequest(message)
  }
}

///|
pub fn decode_message(message : Json) -> @jsonrpc.Message raise McpError {
  @jsonrpc.decode(message) catch {
    error => raise jsonrpc_error(error)
  }
}

///|
pub fn decode_message_opt(message : Json) -> @jsonrpc.Message? {
  Some(@jsonrpc.decode(message)) catch {
    _ => None
  }
}

///|
pub fn error_response(id? : @jsonrpc.RequestId, error : McpError) -> Json {
  let response : @jsonrpc.Response[Json] = @jsonrpc.response_failure(
    id?,
    error=error.to_error_object(),
  )
  response.to_json()
}

///|
pub fn error_response_from_json_id(id? : Json, error : McpError) -> Json {
  let request_id : @jsonrpc.RequestId? = match id {
    Some(Json::Null) | None => None
    Some(id_val) => Some(@json.from_json(id_val)) catch { _ => None }
  }
  error_response(id?=request_id, error)
}

///|
pub fn success_response(id : @jsonrpc.RequestId, result : Json) -> Json {
  @jsonrpc.response_success(id~, result~).to_json()
}

///|
pub fn success_response_from_json_id(
  id : Json,
  result : Json,
) -> Json raise McpError {
  let request_id : @jsonrpc.RequestId = @json.from_json(id) catch {
    _ => raise InvalidRequest("invalid JSON-RPC id")
  }
  success_response(request_id, result)
}

///|
fn rpc_response_result(message : Json) -> Json raise McpError {
  let decoded = decode_message(message)
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
