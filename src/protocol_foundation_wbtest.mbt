///|
test "modern metadata protects reserved keys" {
  let meta = RequestMeta(progress_token=Json::string("p"), extra={
    "io.modelcontextprotocol/protocolVersion": Json::string("bad"),
    "com.example/trace": Json::string("trace-1"),
  })
  guard meta.to_json() is Object(fields) else { fail("expected object") }
  assert_eq(
    fields["io.modelcontextprotocol/protocolVersion"],
    Json::string("2026-07-28"),
  )
  assert_true(fields["io.modelcontextprotocol/clientCapabilities"] is Object(_))
  assert_eq(fields["com.example/trace"], Json::string("trace-1"))
}

///|
test "cache and MRTR constructors enforce invariants" {
  try CachePolicy(ttl_ms=-1L) catch {
    InvalidParams(_) => ()
    _ => fail("expected invalid cache policy")
  } noraise {
    _ => fail("expected negative ttlMs to raise")
  }
  try InputRequiredResult() catch {
    InvalidParams(_) => ()
    _ => fail("expected invalid input-required result")
  } noraise {
    _ => fail("expected empty input-required result to raise")
  }
}

///|
test "modern protocol errors carry structured data" {
  let error = UnsupportedProtocolVersion(requested="1900-01-01", supported=[
    latest_protocol_version,
  ])
  guard error.to_json()
    is Object(
      {
        "code": Number(-32022.0, ..),
        "data": Object(
          {
            "requested": String("1900-01-01"),
            "supported": Array([String("2026-07-28")]),
            ..
          }
        ),
        ..
      }
    ) else {
    fail("expected unsupported protocol error data")
  }
}

///|
test "MRTR retry helper requires matching response keys" {
  let required = try! InputRequiredResult(input_requests={
    "approval": try! InputRequest(method_name="elicitation/create"),
  })
  try required.retry_options({}) catch {
    InvalidParams("missing input response: approval") => ()
    _ => fail("expected missing response error")
  } noraise {
    _ => fail("expected missing response to raise")
  }
  let options = try! required.retry_options({
    "approval": InputResponse(
      Json::object({ "action": Json::string("accept") }),
    ),
  })
  assert_true(options.input_responses is Some(_))
}

///|
test "subscription acceptance acknowledges the honored filter first" {
  let server = try! Server(name="server", version="1", tool_list_changed=true)
  let client = Client(name="client", version="1")
  let request = client.listen_request(
    notifications=SubscriptionFilter(
      tools_list_changed=true,
      prompts_list_changed=true,
    ),
  )
  let subscription = try! server.accept_subscription(request)
  guard subscription.acknowledgement()
    is Object(
      {
        "method": String("notifications/subscriptions/acknowledged"),
        "params": Object(
          {
            "_meta": Object(
              { "io.modelcontextprotocol/subscriptionId": Number(1.0, ..), .. }
            ),
            "notifications": Object(
              { "toolsListChanged": True, "promptsListChanged"? : None, .. }
            ),
            ..
          }
        ),
        ..
      }
    ) else {
    fail("expected acknowledgement with honored filter")
  }
  guard subscription.close_response()
    is Object(
      {
        "id": Number(1.0, ..),
        "result": Object({ "resultType": String("complete"), .. }),
        ..
      }
    ) else {
    fail("expected graceful final response")
  }
}

///|
test "cancellation identifiers are never null" {
  try cancelled_notification(request_id=Json::null()) catch {
    InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("expected null cancellation id to raise")
  }
}
