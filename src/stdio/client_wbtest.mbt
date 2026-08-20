///|
test "stdio accepts only requests in the outbound direction" {
  let core = try! @client.Client(
    name="test",
    version="1",
    transport=@client.NoopTransport(),
  )
  let request = core.request_raw(method_name="server/discover")
  let decoded = try! @jsonrpc.decode(request)
  guard decoded is Request({ id, .. }) else { fail("expected request message") }
  assert_eq(id, try! @jsonrpc.RequestId::number(1.0, repr="1"))
}

///|
test "stdio distinguishes notifications from responses" {
  let notification = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("notifications/progress"),
    "params": Json::object({}),
  })
  let decoded_notif = try! @jsonrpc.decode(notification)
  assert_true(decoded_notif is Notification(_))
  let response = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::string("request-1"),
    "result": Json::object({ "resultType": Json::string("complete") }),
  })
  let decoded_resp = try! @jsonrpc.decode(response)
  guard decoded_resp is Response(Success(id~, ..)) else {
    fail("expected response success")
  }
  assert_eq(id, @jsonrpc.RequestId::string("request-1"))
  let reverse_request = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::string("server-request"),
    "method": Json::string("sampling/createMessage"),
    "params": Json::object({}),
  })
  let decoded_req = try! @jsonrpc.decode(reverse_request)
  assert_true(decoded_req is Request(_))
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
  let cancel = try! @mcp.CancelledNotification(
    request_id=Json::string("listen-1"),
    reason="done",
  )
  assert_eq(cancel.params.request_id, Json::string("listen-1"))
  assert_eq(cancel.params.reason, Some("done"))
  assert_eq(cancel.to_jsonrpc().method_name, "notifications/cancelled")
}

///|
test "subscriptions/listen is a long-lived transport request" {
  let core = try! @client.Client(
    name="test",
    version="1",
    transport=@client.NoopTransport(),
  )
  let request = core.request_raw(method_name="subscriptions/listen", params={
    "notifications": @mcp.SubscriptionFilter(tools_list_changed=true).to_json(),
  })
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
  pending[(try! @jsonrpc.RequestId::number(1.0, repr="1")).to_routing_key()] = first
  pending[(try! @jsonrpc.RequestId::number(2.0, repr="2")).to_routing_key()] = second
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
  let id1 = try! @jsonrpc.RequestId::number(1.0, repr="1")
  let ids = @jsonrpc.RequestId::string("1")
  assert_true(ids.to_routing_key() != id1.to_routing_key())
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
    core.call_tool(name="test", max_rounds=0, resolve_input=fn(_) { Map([]) })
  catch {
    @mcp.InvalidRequest(message) => assert_true(message.contains("positive"))
    _ => fail("expected invalid request")
  } noraise {
    _ => fail("expected max_rounds validation error")
  }
}
