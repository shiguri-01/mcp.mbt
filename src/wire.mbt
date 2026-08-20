///|
/// MCP's wire layer bridges the transport layer and the canonical `jsonrpc` package.
///
/// It translates JSON-RPC envelopes into MCP semantics and errors without
/// re-implementing JSON-RPC wire parsing.
pub fn McpError::from_jsonrpc_decode_error(
  error : @jsonrpc.JsonRpcDecodeError,
) -> McpError {
  match error {
    InvalidMessage(message) => InvalidRequest(message)
  }
}

///|
pub fn decode_message(message : Json) -> @jsonrpc.Message raise McpError {
  @jsonrpc.decode(message) catch {
    error => raise McpError::from_jsonrpc_decode_error(error)
  }
}

///|
pub fn McpError::to_response(
  self : McpError,
  id? : @jsonrpc.RequestId,
) -> @jsonrpc.Response[Json] {
  Failure(id~, error=self.to_error_object())
}
