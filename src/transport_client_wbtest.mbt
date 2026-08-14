///|
/// A transport test double only sees opaque JSON text.  It does not import or
/// inspect the JSON-RPC package; the protocol client owns the envelope.
priv struct EchoFrame {
  response_result : Json
}

///|
fn EchoFrame::new(response_result : Json) -> EchoFrame {
  { response_result, }
}

///|
impl @transport.FrameTransport for EchoFrame with fn exchange(
  self : EchoFrame,
  body : String,
  _headers : Map[String, String],
) -> @transport.FrameResponse raise @transport.TransportError {
  let request : Json = @json.parse(body) catch {
    error => raise @transport.TransportError::InvalidFrame(error.to_string())
  }
  guard request is Object({ "id": id, .. }) else {
    raise @transport.TransportError::InvalidFrame("request has no id")
  }
  let response = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id,
    "result": self.response_result,
  })
  @transport.FrameResponse(body=response.stringify())
}

///|
async test "protocol client exchanges through an opaque frame transport" {
  let client = try! Client(name="test-client", version="1")
  let request = try! client.discover_request()
  let response_result = Json::object({ "resultType": Json::string("complete") })
  let response = try! client.exchange(EchoFrame::new(response_result), request)
  guard response is Object({ "result": Object(fields), .. }) else {
    fail("expected JSON-RPC response")
  }
  assert_eq(fields["resultType"], Json::string("complete"))
}
