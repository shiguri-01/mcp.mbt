///|
/// Errors at the transport boundary. These are not JSON-RPC or MCP errors.
pub(all) suberror TransportError {
  Closed
  InvalidFrame(String)
  MessageTooLarge(limit~ : Int)
  Io(String)
} derive(Debug, Eq)

///|
/// A received frame and transport metadata. Metadata is deliberately generic:
/// an HTTP adapter may include status and headers, while another adapter can
/// use its own keys without forcing protocol knowledge into this package.
pub struct FrameResponse {
  body : String
  metadata : Map[String, String]
} derive(Debug, Eq)

///|
/// Construct a received frame from an opaque body and adapter metadata.
pub fn FrameResponse::FrameResponse(
  body~ : String,
  metadata? : Map[String, String] = Map([]),
) -> FrameResponse {
  { body, metadata: metadata.copy() }
}

///|
/// A transport exchanges opaque bytes/text and transport metadata. It never
/// receives an MCP or JSON-RPC value, so custom transports do not need to know
/// either protocol.
pub(open) trait FrameTransport {
  async fn exchange(self : Self, body : String, metadata : Map[String, String]) -> FrameResponse raise TransportError
}

///|
/// A long-lived stream used by subscriptions or request-scoped events.
pub(open) trait FrameStream {
  async fn next(self : Self) -> String? raise TransportError
  fn close(self : Self) -> Unit
}
