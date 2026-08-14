///|
/// Send one MCP request through any frame transport.
///
/// The adapter owns bytes, sockets, framing, retries, and connection
/// lifetime.  This method owns JSON-RPC/MCP encoding and decoding.  HTTP and
/// stdio clients are convenience adapters built on the same boundary.
pub async fn[T : @transport.FrameTransport] Client::exchange(
  self : Client,
  transport : T,
  request : Json,
) -> Json raise McpError {
  self.exchange_with_headers(transport, request, Map([]))
}

///|
/// Send one protocol request through an adapter with caller-supplied
/// transport metadata.  The metadata is intentionally opaque here: HTTP
/// `Mcp-*` rules and stdio framing belong to their adapters.
pub async fn[T : @transport.FrameTransport] Client::exchange_with_headers(
  self : Client,
  transport : T,
  request : Json,
  headers : Map[String, String],
) -> Json raise McpError {
  let body = Json::stringify(request)
  let (status, _response_headers, response_body) = transport.exchange(
    body, headers,
  ) catch {
    @transport.TransportError::Closed =>
      raise InternalError("transport closed before an MCP response")
    @transport.TransportError::MessageTooLarge(limit~) =>
      raise InternalError("transport response exceeded limit \{limit}")
    @transport.TransportError::InvalidFrame(message)
    | @transport.TransportError::Io(message) => raise InternalError(message)
  }
  if status < 200 || status >= 300 {
    raise InternalError("transport returned HTTP/status {status}")
  }
  let decoded = @json.parse(response_body) catch {
    error => raise ParseError(error.to_string())
  }
  ignore(self.decode_response(decoded))
  decoded
}
