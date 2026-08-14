///|
/// MCP's wire layer bridges the transport layer and the canonical `jsonrpc` package.
///
/// It translates JSON-RPC envelopes into MCP semantics and errors without
/// re-implementing JSON-RPC wire parsing.
fn jsonrpc_error(error : @jsonrpc.JsonRpcDecodeError) -> McpError {
  match error {
    @jsonrpc.JsonRpcDecodeError::InvalidMessage(message) =>
      InvalidRequest(message)
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
