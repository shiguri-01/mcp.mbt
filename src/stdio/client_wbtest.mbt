///|
test "stdio accepts only requests in the outbound direction" {
  let core = @mcp.Client(name="test", version="1")
  let request = core.discover_request()
  assert_eq(request_id(request), Json::number(1.0, repr="1"))
  try
    request_id(
      Json::object({
        "jsonrpc": Json::string("2.0"),
        "method": Json::string("notifications/cancelled"),
      }),
    )
  catch {
    InvalidRequest(_) => ()
    _ => fail("expected invalid request")
  } noraise {
    _ => fail("expected request direction error")
  }
}

///|
test "stdio distinguishes notifications from responses" {
  let notification = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/progress"),
    "params": Json::object({}),
  })
  assert_eq(try! response_id(notification), None)
  let response = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::string("request-1"),
    "result": Json::object({ "resultType": Json::string("complete") }),
  })
  assert_eq(try! response_id(response), Some(Json::string("request-1")))
  let reverse_request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::string("server-request"),
    "method": Json::string("sampling/createMessage"),
    "params": Json::object({}),
  })
  try response_id(reverse_request) catch {
    InvalidRequest(_) => ()
    _ => fail("expected invalid request")
  } noraise {
    _ => fail("expected response direction error")
  }
}

///|
test "stdio framing is one compact JSON value per line" {
  let message = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "result": Json::object({ "resultType": Json::string("complete") }),
  })
  let frame = encode_frame(message)
  assert_true(frame.has_suffix("\n"))
  assert_true(!frame.trim().contains("\n"))
  assert_eq(try! decode_frame(frame), message)
}

///|
test "cancel is a client-to-server notification" {
  let cancel = @mcp.cancelled_notification(
    request_id=Json::string("listen-1"),
    reason="done",
  )
  assert_eq(response_id(cancel), None)
  guard cancel is Object({ "id"? : None, "params": Object(params), .. }) else {
    fail("expected cancellation notification")
  }
  assert_eq(params["requestId"], Json::string("listen-1"))
  assert_eq(cancelled_request_id(cancel), Some(Json::string("listen-1")))
}

///|
test "stdio transport owns listen requests" {
  let core = @mcp.Client(name="test", version="1")
  let request = core.listen_request(
    notifications=SubscriptionFilter(tools_list_changed=true),
  )
  assert_true(is_listen_request(request))
  assert_true(inbound_id(request) is Some(Number(_)))
}

///|
async test "single reader demultiplexes interleaved responses" {
  let pending : Map[String, @aqueue.Queue[Inbound]] = Map([])
  let first : @aqueue.Queue[Inbound] = Queue(kind=Unbounded)
  let second : @aqueue.Queue[Inbound] = Queue(kind=Unbounded)
  pending[routing_key(Json::number(1.0, repr="1"))] = first
  pending[routing_key(Json::number(2.0, repr="2"))] = second
  let response = (id : Int) => {
    Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(id.to_double(), repr="\{id}"),
      "result": Json::object({ "resultType": Json::string("complete") }),
    })
  }
  route_message(pending, Map([]), response(2))
  route_message(pending, Map([]), response(1))
  guard first.get() is Message(Object({ "id": Number(1.0, ..), .. })) else {
    fail("first response was not routed by id")
  }
  guard second.get() is Message(Object({ "id": Number(2.0, ..), .. })) else {
    fail("second response was not routed by id")
  }
}

///|
test "MRTR resolution requires a positive bound" {
  try validate_max_rounds(0) catch {
    InvalidRequest(message) => assert_true(message.contains("positive"))
    _ => fail("expected invalid request")
  } noraise {
    _ => fail("expected max_rounds validation error")
  }
}
