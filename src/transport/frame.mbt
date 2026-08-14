///|
/// Transport errors are deliberately independent of JSON-RPC and MCP errors.
pub(all) suberror TransportError {
  Closed
  InvalidFrame(String)
  MessageTooLarge(limit~ : Int)
  Io(String)
} derive(Debug, Eq)

///|
/// One outbound exchange.  The body is an opaque protocol frame; transports
/// must not parse it or interpret its method.  Headers are transport metadata
/// and are not an authenticated principal.
pub struct OutboundFrame {
  body : String
  headers : Map[String, String]
}

///|
pub fn OutboundFrame::OutboundFrame(
  body~ : String,
  headers? : Map[String, String] = Map([]),
) -> OutboundFrame {
  { body, headers: headers.copy() }
}

///|
pub fn OutboundFrame::body(self : OutboundFrame) -> String {
  self.body
}

///|
pub fn OutboundFrame::headers(self : OutboundFrame) -> Map[String, String] {
  self.headers.copy()
}

///|
/// One inbound exchange.  A transport may return JSON or an event-stream body;
/// the protocol layer decides how to decode the body.
pub struct InboundFrame {
  status : Int
  headers : Map[String, String]
  body : String
}

///|
pub fn InboundFrame::InboundFrame(
  status~ : Int,
  headers? : Map[String, String] = Map([]),
  body? : String = "",
) -> InboundFrame {
  { status, headers: headers.copy(), body }
}

///|
pub fn InboundFrame::status(self : InboundFrame) -> Int {
  self.status
}

///|
pub fn InboundFrame::headers(self : InboundFrame) -> Map[String, String] {
  self.headers.copy()
}

///|
pub fn InboundFrame::body(self : InboundFrame) -> String {
  self.body
}

///|
/// A request/response frame exchange implemented by an adapter.
pub(open) trait FrameTransport {
  async fn exchange(self : Self, frame : OutboundFrame) -> InboundFrame raise TransportError
}

///|
/// A long-lived inbound stream.  Streamable HTTP SSE and stdio
/// multiplexing adapters implement this separately from one-shot exchange.
pub(open) trait FrameStream {
  async fn next(self : Self) -> String? raise TransportError
  fn close(self : Self) -> Unit
}
