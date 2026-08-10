///|
test "request metadata owns reserved fields and preserves extension fields" {
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
test "metadata keys follow the MCP prefix and name grammar" {
  let client = try! Client(name="client", version="1")
  try
    client.request(
      method_name="example/run",
      options=RequestOptions(meta={ "bad/key/extra": Json::boolean(true) }),
    )
  catch {
    InvalidParams(_) => ()
    _ => fail("expected invalid metadata key")
  } noraise {
    _ => fail("invalid metadata key must be rejected")
  }
  ignore(
    try! client.request(
      method_name="example/run",
      options=RequestOptions(meta={ "com.example/trace-id": Json::string("1") }),
    ),
  )
}

///|
test "extension result types require an advertised extension mapping" {
  let capabilities = ClientCapabilities(extensions={
    "com.example/flow": Json::object({}),
  })
  let client = try! Client(name="client", version="1", capabilities~, extension_result_types={
    "paused": "com.example/flow",
  })
  let response = rpc_result_response(
    Json::number(1.0),
    Json::object({
      "resultType": Json::string("paused"),
      "resumeToken": Json::string("next"),
    }),
  )
  assert_true(client.decode_response(response) is ExtensionResult("paused", _))
  let strict = try! Client(name="strict", version="1")
  try strict.decode_response(response) catch {
    InvalidRequest("unknown resultType: paused") => ()
    _ => fail("expected unknown result type")
  } noraise {
    _ => fail("unadvertised result type must be rejected")
  }
}

///|
async test "progress values increase within one request" {
  let emitted : Array[Json] = []
  let context = try! RequestContext(
    request_id=Json::number(1.0),
    method_name="tools/call",
    meta=RequestMeta(progress_token=Json::string("progress-1")),
    hooks=RequestHooks(emit_notification=fn(message) { emitted.push(message) }),
  )
  context.report_progress(progress=0.25, total=1.0)
  try context.report_progress(progress=0.25, total=1.0) catch {
    InvalidParams(_) => ()
    _ => fail("expected invalid progress")
  } noraise {
    _ => fail("progress must increase")
  }
  assert_eq(emitted.length(), 1)
}

///|
test "cache TTL cannot be negative" {
  try CachePolicy(ttl_ms=-1L) catch {
    InvalidParams(_) => ()
    _ => fail("expected invalid cache policy")
  } noraise {
    _ => fail("expected negative ttlMs to raise")
  }
}

///|
test "input_required includes inputRequests or requestState" {
  try InputRequiredResult() catch {
    InvalidParams(_) => ()
    _ => fail("expected invalid input-required result")
  } noraise {
    _ => fail("expected empty input-required result to raise")
  }
}

///|
test "unsupported protocol errors identify requested and supported versions" {
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
    "approval": try! InputRequest(
      method_name="elicitation/create",
      params=Json::object({
        "message": Json::string("Continue?"),
        "requestedSchema": Json::object({
          "type": Json::string("object"),
          "properties": Json::object({}),
        }),
      }),
    ),
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
test "MRTR decoding preserves result metadata" {
  let result = parse_input_required_result(
    Json::object({
      "resultType": Json::string("input_required"),
      "requestState": Json::string("opaque"),
      "_meta": Json::object({ "com.example/trace": Json::string("trace-1") }),
    }),
  )
  assert_true(
    result.meta()
    is Some({ extra: { "com.example/trace": String("trace-1"), .. }, .. }),
  )
}

///|
test "MRTR retry options preserve request metadata" {
  let required = try! InputRequiredResult(request_state="opaque")
  let base = RequestOptions(
    progress_token=Json::string("progress-1"),
    log_level=Info,
    meta={ "com.example/trace": Json::string("trace-1") },
  )
  let retry = try! required.retry_options({}, base~)
  assert_eq(retry.progress_token, base.progress_token)
  assert_eq(retry.log_level, base.log_level)
  assert_eq(retry.meta, base.meta)
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
