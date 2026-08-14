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
  let body = Json::stringify(request)
  let frame = @transport.OutboundFrame::OutboundFrame(body~)
  let response = transport.exchange(frame) catch {
    @transport.TransportError::Closed =>
      raise InternalError("transport closed before an MCP response")
    @transport.TransportError::MessageTooLarge(limit~) =>
      raise InternalError("transport response exceeded limit \{limit}")
    @transport.TransportError::InvalidFrame(message)
    | @transport.TransportError::Io(message) => raise InternalError(message)
  }
  if response.status() < 200 || response.status() >= 300 {
    raise InternalError("transport returned HTTP/status {response.status()}")
  }
  let decoded = @json.parse(response.body()) catch {
    error => raise ParseError(error.to_string())
  }
  ignore(self.decode_response(decoded))
  decoded
}
