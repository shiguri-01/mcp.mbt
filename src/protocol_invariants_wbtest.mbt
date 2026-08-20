///|
test "request metadata owns reserved fields and preserves extension fields" {
  let meta = RequestMeta(progress_token=Json::string("p"), extra={
    "io.modelcontextprotocol/protocolVersion": Json::string("bad"),
    "com.example/trace": Json::string("trace-1"),
  })
  guard ToJson::to_json(meta) is Object(fields) else { fail("expected object") }
  assert_eq(
    fields["io.modelcontextprotocol/protocolVersion"],
    Json::string("2026-07-28"),
  )
  assert_true(fields["io.modelcontextprotocol/clientCapabilities"] is Object(_))
  assert_eq(fields["com.example/trace"], Json::string("trace-1"))
}

///|
test "metadata keys follow the MCP prefix and name grammar" {
  assert_false(valid_meta_key("bad/key/extra"))
  assert_true(valid_meta_key("com.example/trace-id"))
  try validate_meta_map({ "bad/key/extra": Json::boolean(true) }) catch {
    InvalidParams(_) => ()
    _ => fail("expected invalid metadata key")
  } noraise {
    _ => fail("invalid metadata key must be rejected")
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
    PROTOCOL_VERSION,
  ])
  guard ToJson::to_json(error)
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
      Json::object({
        "action": Json::string("accept"),
        "content": Json::object({}),
      }),
    ),
  })
  assert_true(options.input_responses is Some(_))
}

///|
test "form elicitation uses primitive schemas and validates accepted content" {
  try
    InputRequest(
      method_name="elicitation/create",
      params=Json::object({
        "message": Json::string("Nested value"),
        "requestedSchema": Json::object({
          "type": Json::string("object"),
          "properties": Json::object({
            "nested": Json::object({ "type": Json::string("object") }),
          }),
        }),
      }),
    )
  catch {
    InvalidParams(_) => ()
    _ => fail("expected invalid primitive schema error")
  } noraise {
    _ => fail("nested elicitation schema must be rejected")
  }
  let required = try! InputRequiredResult(input_requests={
    "age": try! InputRequest(
      method_name="elicitation/create",
      params=Json::object({
        "message": Json::string("Age"),
        "requestedSchema": Json::object({
          "type": Json::string("object"),
          "properties": Json::object({
            "age": Json::object({ "type": Json::string("integer") }),
          }),
          "required": ["age"].to_json(),
        }),
      }),
    ),
  })
  try
    required.retry_options({
      "age": InputResponse(
        Json::object({
          "action": Json::string("accept"),
          "content": Json::object({ "age": Json::string("unknown") }),
        }),
      ),
    })
  catch {
    InvalidParams(_) => ()
    _ => fail("expected elicitation content validation error")
  } noraise {
    _ => fail("accepted content must match requestedSchema")
  }
}

///|
test "MRTR decoding preserves result metadata" {
  let result = InputRequiredResult::from_json(
    Json::object({
      "resultType": Json::string("input_required"),
      "requestState": Json::string("opaque"),
      "_meta": Json::object({ "com.example/trace": Json::string("trace-1") }),
    }),
  )
  assert_true(
    result.meta
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
test "cancellation identifiers are never null" {
  try CancelledNotification(request_id=Json::null()) catch {
    InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("expected null cancellation id to raise")
  }
}

///|
test "discover accepts complete results without resultType" {
  let result = DiscoverResult::from_json(
    Json::object({
      "supportedVersions": Json::array([Json::string(PROTOCOL_VERSION)]),
      "capabilities": Json::object({
        "com.example/custom": Json::object({ "enabled": Json::boolean(true) }),
      }),
      "ttlMs": Json::number(0),
      "cacheScope": Json::string("private"),
    }),
  )
  assert_eq(
    result.capabilities.extra.get("com.example/custom"),
    Some(Json::object({ "enabled": Json::boolean(true) })),
  )
  assert_true(
    ToJson::to_json(result) is Object({ "resultType": String("complete"), .. }),
  )
}

///|
test "sampling MRTR validates message roles and response content" {
  try
    InputRequest(
      method_name="sampling/createMessage",
      params=Json::object({
        "messages": Json::array([
          Json::object({
            "role": Json::string("system"),
            "content": Json::object({
              "type": Json::string("text"),
              "text": Json::string("hello"),
            }),
          }),
        ]),
        "maxTokens": Json::number(32),
      }),
    )
  catch {
    InvalidParams(_) => ()
    _ => fail("expected invalid sampling message error")
  } noraise {
    _ => fail("expected invalid sampling message to raise")
  }
  let required = try! InputRequiredResult(input_requests={
    "sample": try! InputRequest(
      method_name="sampling/createMessage",
      params=Json::object({
        "messages": Json::array([
          Json::object({
            "role": Json::string("user"),
            "content": Json::object({
              "type": Json::string("text"),
              "text": Json::string("hello"),
            }),
          }),
        ]),
        "maxTokens": Json::number(32),
      }),
    ),
  })
  try
    required.retry_options({
      "sample": InputResponse(
        Json::object({
          "model": Json::string("example"),
          "role": Json::string("user"),
          "content": Json::boolean(true),
        }),
      ),
    })
  catch {
    InvalidParams(_) => ()
    _ => fail("expected invalid sampling response error")
  } noraise {
    _ => fail("expected invalid sampling response to raise")
  }
}

///|
test "roots MRTR responses require URI and allow omitted names" {
  let required = try! InputRequiredResult(input_requests={
    "roots": try! InputRequest(method_name="roots/list"),
  })
  ignore(
    try! required.retry_options({
      "roots": InputResponse(
        Json::object({
          "roots": Json::array([
            Json::object({ "uri": Json::string("file:///workspace") }),
          ]),
        }),
      ),
    }),
  )
  try
    required.retry_options({
      "roots": InputResponse(
        Json::object({
          "roots": Json::array([Json::object({ "name": Json::string("src") })]),
        }),
      ),
    })
  catch {
    InvalidParams(_) => ()
    _ => fail("expected invalid roots response error")
  } noraise {
    _ => fail("expected invalid roots response to raise")
  }
}
