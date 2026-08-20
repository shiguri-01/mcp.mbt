///|
pub struct NoopTransport {}

///|
pub fn NoopTransport::NoopTransport() -> NoopTransport {
  NoopTransport::{  }
}

///|
pub impl ClientTransport for NoopTransport with fn request_with_notifications(
  _self,
  _request,
  on_notification~,
) {
  ignore(on_notification)
  raise @mcp.InternalError("client is using NoopTransport")
}

///|
pub impl ClientTransport for NoopTransport with fn notify(_self, _notification) {
  raise @mcp.InternalError("client is using NoopTransport")
}

///|
pub impl ClientTransport for NoopTransport with fn close(_self) {
  ()
}
