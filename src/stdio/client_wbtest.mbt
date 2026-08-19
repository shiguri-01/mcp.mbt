///|
test "stdio accepts only requests in the outbound direction" {
  let core = try! @client.Client(
    name="test",
    version="1",
    transport=@client.NoopTransport(),
  )
  let request = core.discover_request()
  assert_eq(@mcp.request_id(request), Json::number(1.0, repr="1"))
  try
    @mcp.request_id(
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
  assert_eq(try! @mcp.response_id(notification), None)
  let response = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::string("request-1"),
    "result": Json::object({ "resultType": Json::string("complete") }),
  })
  assert_eq(try! @mcp.response_id(response), Some(Json::string("request-1")))
  let reverse_request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::string("server-request"),
    "method": Json::string("sampling/createMessage"),
    "params": Json::object({}),
  })
  try @mcp.response_id(reverse_request) catch {
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
  assert_eq(@mcp.response_id(cancel), None)
  let decoded = try! @jsonrpc.decode(cancel)
  guard decoded
    is Notification({ method_name: "notifications/cancelled", params }) else {
    fail("expected cancellation notification")
  }
  let parsed = try! @mcp.CancelledNotificationParams::from_json(params)
  assert_eq(parsed.request_id, Json::string("listen-1"))
  assert_eq(parsed.reason, Some("done"))
}

///|
test "subscriptions/listen is a long-lived transport request" {
  let core = try! @client.Client(
    name="test",
    version="1",
    transport=@client.NoopTransport(),
  )
  let request = core.listen_request(
    notifications=SubscriptionFilter(tools_list_changed=true),
  )
  let decoded = try! @jsonrpc.decode(request)
  guard decoded is Request({ method_name: "subscriptions/listen", id, .. }) else {
    fail("expected subscriptions/listen request")
  }
  assert_true(id.as_json() is Number(_))
}

///|
async test "single reader demultiplexes interleaved responses" {
  let pending : Map[String, @aqueue.Queue[Inbound]] = Map([])
  let first : @aqueue.Queue[Inbound] = Queue(kind=Unbounded)
  let second : @aqueue.Queue[Inbound] = Queue(kind=Unbounded)
  pending[@mcp.routing_key(Json::number(1.0, repr="1"))] = first
  pending[@mcp.routing_key(Json::number(2.0, repr="2"))] = second
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
test "numeric request ids route by JSON number value" {
  assert_eq(
    @mcp.routing_key(Json::number(1.0, repr="1")),
    @mcp.routing_key(Json::number(1.0, repr="1.0")),
  )
  assert_true(
    @mcp.routing_key(Json::string("1")) !=
    @mcp.routing_key(Json::number(1.0, repr="1")),
  )
}

///|
test "closing a client wakes every pending request" {
  let pending : Map[String, @aqueue.Queue[Inbound]] = Map([])
  let queue : @aqueue.Queue[Inbound] = Queue(kind=Unbounded)
  pending["number:1"] = queue
  fail_pending_now(pending, "closed")
  assert_true(queue.try_get() is Some(Failed(InternalError("closed"))))
  assert_true(pending.is_empty())
}

///|
async test "MRTR resolution requires a positive bound" {
  let core = try! @client.Client(
    name="test",
    version="1",
    transport=@client.NoopTransport(),
  )
  try
    core.call_tool_resolving(name="test", max_rounds=0, resolve=fn(_) {
      Map([])
    })
  catch {
    @mcp.InvalidRequest(message) => assert_true(message.contains("positive"))
    _ => fail("expected invalid request")
  } noraise {
    _ => fail("expected max_rounds validation error")
  }
}
