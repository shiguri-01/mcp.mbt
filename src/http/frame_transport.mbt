///|
/// Buffered Streamable HTTP adapter for the transport-neutral frame contract.
///
/// This type deliberately does not parse JSON-RPC.  It sends the supplied
/// opaque body and returns the complete response body, including an SSE body
/// when the server selected `text/event-stream`.  The high-level HTTP client
/// uses its streaming path when progress timing matters; this adapter is the
/// reusable boundary for custom protocol clients.
pub struct FrameTransport {
  endpoint : String
  max_response_body_bytes : Int
}

///|
pub fn FrameTransport::FrameTransport(
  endpoint~ : String,
  max_response_body_bytes? : Int = default_max_response_body_bytes,
) -> FrameTransport raise @transport.TransportError {
  if endpoint.is_empty() {
    raise @transport.TransportError::InvalidFrame("HTTP endpoint is empty")
  }
  if max_response_body_bytes <= 0 {
    raise @transport.TransportError::InvalidFrame(
      "max_response_body_bytes must be positive",
    )
  }
  { endpoint, max_response_body_bytes }
}

///|
pub impl @transport.FrameTransport for FrameTransport with fn exchange(
  self : FrameTransport,
  body_text : String,
  headers : Map[String, String],
) -> (Int, Map[String, String], String) raise @transport.TransportError {
  let body = @utf8.encode(body_text)
  let stream = @async_http.post_stream(self.endpoint, headers~) catch {
    error => raise @transport.TransportError::Io(error.to_string())
  }
  defer stream.close()
  stream.write(body) catch {
    error => raise @transport.TransportError::Io(error.to_string())
  }
  let response = stream.end_request() catch {
    error => raise @transport.TransportError::Io(error.to_string())
  }
  let response_body = read_bounded_text(
    stream,
    self.max_response_body_bytes,
    "HTTP response body",
  ) catch {
    BodyTooLarge(limit~, ..) =>
      raise @transport.TransportError::MessageTooLarge(limit~)
    BodyInvalidUtf8(subject~) =>
      raise @transport.TransportError::InvalidFrame(subject)
    BodyReadFailed(message~, ..) => raise @transport.TransportError::Io(message)
  }
  (response.code, response.headers, response_body)
}

///|
/// Obtain the opaque frame adapter used by custom protocol clients.
pub fn Client::frame_transport(
  self : Client,
) -> FrameTransport raise @mcp.McpError {
  FrameTransport(
    endpoint=self.endpoint,
    max_response_body_bytes=self.max_response_body_bytes,
  ) catch {
    @transport.TransportError::Closed =>
      raise @mcp.InternalError("HTTP frame transport is closed")
    @transport.TransportError::InvalidFrame(message)
    | @transport.TransportError::Io(message) =>
      raise @mcp.InternalError(message)
    @transport.TransportError::MessageTooLarge(..) =>
      raise @mcp.InternalError("HTTP response exceeded configured limit")
  }
}

///|
/// Send a buffered request through the common opaque-frame boundary.
///
/// This is the escape hatch for applications that want the shared transport
/// contract while retaining the HTTP client's header construction. Streaming
/// progress callers should use `request_with_notifications` instead.
pub async fn Client::request_via_transport(
  self : Client,
  request : Json,
  input_schema? : Json,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  let headers = self.headers(request, input_schema?) catch {
    InvalidHeaderSchema(message)
    | InvalidHeaderValue(message)
    | HeaderMismatch(message) => raise @mcp.InvalidRequest(message)
  }
  let transport = self.frame_transport()
  let response = self.core.exchange_with_headers(transport, request, headers)
  self.core.decode_response(response)
}
