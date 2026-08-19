///|
fn test_client(
  name? : String = "client",
  version? : String = "1",
  protocol_version? : String,
  capabilities? : @mcp.ClientCapabilities = @mcp.ClientCapabilities::empty(),
) -> @client.Client raise @mcp.McpError {
  @client.Client(
    name~,
    version~,
    transport=@client.NoopTransport(),
    protocol_version?,
    capabilities~,
  )
}

///|
async test "each request carries the client context used by the server" {
  let builder = try! ServerBuilder(
    name="test-server",
    version="1.0.0",
    instructions="Use the echo tool",
    cache_policy=try! @mcp.CachePolicy(ttl_ms=1000L, scope=@mcp.Public),
  )
  try! builder.tool_raw(
    name="whoami",
    description="Return the request client name",
    fn(context, _arguments) -> @mcp.HandlerOutcome[@mcp.CallToolResult] {
      let name = context.meta.client_info
        .map(info => info.name)
        .unwrap_or("anonymous")
      @mcp.Complete(@mcp.CallToolResult::text(name))
    },
  )
  let server = builder.build()
  let first = try! test_client(name="client-a", version="1")
  let discover_response = server.handle_jsonrpc(
    first.request_raw(method_name="server/discover"),
  )
  guard discover_response is Some(discover_message) else {
    fail("expected discover response")
  }
  let discovered = try! first.decode_discover(discover_message)
  guard discovered.to_json()
    is Object(
      {
        "resultType": String("complete"),
        "supportedVersions": Array([String("2026-07-28")]),
        "ttlMs": Number(1000.0, ..),
        "cacheScope": String("public"),
        ..
      }
    ) else {
    fail("expected discovery result")
  }
  let tools_response = server.handle_jsonrpc(
    first.request_raw(method_name="tools/list"),
  )
  guard tools_response is Some(message) else { fail("expected tools response") }
  guard (try! first.decode_response(message))
    is @mcp.Complete(
      Object(
        {
          "resultType": String("complete"),
          "tools": Array([Object({ "name": String("whoami"), .. })]),
          "ttlMs": Number(1000.0, ..),
          ..
        }
      )
    ) else {
    fail("expected cacheable tools list")
  }
  let second = try! test_client(name="client-b", version="1")
  let call_response = server.handle_jsonrpc(
    try! second.request_raw(method_name="tools/call", params={
      "name": Json::string("whoami"),
    }),
  )
  guard call_response is Some(message) else { fail("expected call response") }
  guard (try! second.decode_response(message))
    is @mcp.Complete(
      Object(
        {
          "content": Array(
            [Object({ "type": String("text"), "text": String("client-b"), .. })]
          ),
          "resultType": String("complete"),
          ..
        }
      )
    ) else {
    fail("expected request-local client identity")
  }
}

///|
async test "unsupported protocol versions return -32022" {
  let server = (try! ServerBuilder(name="server", version="1")).build()
  let unsupported = try! test_client(
    name="unsupported",
    version="1",
    protocol_version="1900-01-01",
  )
  guard server.handle_jsonrpc(
      unsupported.request_raw(method_name="server/discover"),
    )
    is Some(
      Object(
        {
          "error": Object(
            { "code": Number(-32022.0, ..), "data": Object(_), .. }
          ),
          ..
        }
      )
    ) else {
    fail("expected unsupported protocol version")
  }
}

///|
async test "requests without required metadata return InvalidParams" {
  let server = (try! ServerBuilder(name="server", version="1")).build()
  let missing_meta = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "method": Json::string("server/discover"),
    "params": Json::object({}),
  })
  guard server.handle_jsonrpc(missing_meta)
    is Some(
      Object({ "error": Object({ "code": Number(-32602.0, ..), .. }), .. })
    ) else {
    fail("expected invalid params")
  }
}

///|
async test "JSON-RPC batches return InvalidRequest" {
  let server = (try! ServerBuilder(name="server", version="1")).build()
  guard server.handle_jsonrpc(Json::array([]))
    is Some(
      Object({ "error": Object({ "code": Number(-32600.0, ..), .. }), .. })
    ) else {
    fail("expected batch rejection")
  }
}

///|
async test "JSON-RPC notifications never receive a response" {
  let server = (try! ServerBuilder(name="server", version="1")).build()
  let notification = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("com.example/event"),
    "params": Json::object({}),
  })
  assert_eq(server.handle_jsonrpc(notification), None)
}

///|
async test "MRTR retries echo opaque state and supply input responses" {
  let builder = try! ServerBuilder(name="server", version="1")
  try! builder.tool_raw(name="confirm", fn(
    context,
    _arguments,
  ) -> @mcp.HandlerOutcome[@mcp.CallToolResult] {
    if context.request_state is Some("opaque") &&
      context.input_responses is Some(responses) &&
      responses.contains("answer") {
      return @mcp.Complete(@mcp.CallToolResult::text("accepted"))
    }
    @mcp.InputRequired(
      try! @mcp.InputRequiredResult(
        input_requests={
          "answer": try! @mcp.InputRequest(
            method_name="elicitation/create",
            params=Json::object({
              "message": Json::string("Continue?"),
              "requestedSchema": Json::object({
                "type": Json::string("object"),
                "properties": Json::object({}),
              }),
            }),
          ),
        },
        request_state="opaque",
      ),
    )
  })
  let server = builder.build()
  let client = try! test_client(
    name="client",
    version="1",
    capabilities=@mcp.ClientCapabilities(
      elicitation=@mcp.ElicitationCapability(form=Json::object({})),
    ),
  )
  let first = server.handle_jsonrpc(
    try! client.request_raw(method_name="tools/call", params={
      "name": Json::string("confirm"),
    }),
  )
  guard first is Some(message) else { fail("expected MRTR response") }
  let first_outcome = try! client.decode_response(message)
  guard first_outcome is @mcp.InputRequired(required) else {
    fail("expected input_required")
  }
  let retry = try! client.request_raw(
    method_name="tools/call",
    params={ "name": Json::string("confirm") },
    options=try! required.retry_options({
      "answer": @mcp.InputResponse(
        Json::object({
          "action": Json::string("accept"),
          "content": Json::object({}),
        }),
      ),
    }),
  )
  let second = server.handle_jsonrpc(retry)
  guard second is Some(message) else { fail("expected retry response") }
  assert_true(try! (client.decode_response(message) is @mcp.Complete(_)))
}

///|
async test "MRTR requirements without client capabilities return -32021" {
  let builder = try! ServerBuilder(name="server", version="1")
  try! builder.tool_raw(name="confirm", fn(
    _context,
    _arguments,
  ) -> @mcp.HandlerOutcome[@mcp.CallToolResult] {
    @mcp.InputRequired(
      try! @mcp.InputRequiredResult(input_requests={
        "answer": try! @mcp.InputRequest(
          method_name="elicitation/create",
          params=Json::object({
            "message": Json::string("Continue?"),
            "requestedSchema": Json::object({
              "type": Json::string("object"),
              "properties": Json::object({}),
            }),
          }),
        ),
      }),
    )
  })
  let server = builder.build()
  let client = try! test_client(name="client", version="1")
  let response = server.handle_jsonrpc(
    try! client.request_raw(method_name="tools/call", params={
      "name": Json::string("confirm"),
    }),
  )
  guard response
    is Some(
      Object(
        {
          "error": Object(
            {
              "code": Number(-32021.0, ..),
              "data": Object({ "requiredCapabilities": Object(_), .. }),
              ..
            }
          ),
          ..
        }
      )
    ) else {
    fail("expected missing capability error")
  }
}

///|
async test "progress notifications carry the request progress token" {
  let builder = try! ServerBuilder(name="server", version="1")
  try! builder.tool_raw(name="work", async fn(
    context,
    _arguments,
  ) -> @mcp.HandlerOutcome[@mcp.CallToolResult] raise @mcp.McpError {
    context.report_progress(progress=0.5, total=1.0, message="halfway")
    @mcp.Complete(@mcp.CallToolResult::text("done"))
  })
  let server = builder.build()
  let emitted : Array[Json] = []
  let hooks = @mcp.RequestHooks(emit_notification=fn(message) {
    emitted.push(message)
  })
  let client = try! test_client(name="client", version="1")
  let response = server.handle_jsonrpc_with_hooks(
    try! client.request_raw(
      method_name="tools/call",
      params={ "name": Json::string("work") },
      options=@mcp.RequestOptions(progress_token=Json::string("p-1")),
    ),
    hooks~,
  )
  assert_true(response is Some(_))
  guard emitted
    is [
      Object(
        {
          "method": String("notifications/progress"),
          "params": Object(
            { "progressToken": String("p-1"), "progress": Number(0.5, ..), .. }
          ),
          ..
        }
      ),
    ] else {
    fail("expected one request-scoped progress notification")
  }
}

///|
async test "tool input and structured output honor declared JSON Schemas" {
  let builder = try! ServerBuilder(name="schema-server", version="1")
  try! builder.tool_raw(
    name="bounded",
    input_schema=Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "count": Json::object({
          "type": Json::string("integer"),
          "minimum": Json::number(1.0),
        }),
      }),
      "required": ["count"].to_json(),
      "additionalProperties": Json::boolean(false),
    }),
    output_schema=Json::object({ "type": Json::string("string") }),
    fn(_context, _arguments) -> @mcp.HandlerOutcome[@mcp.CallToolResult] {
      @mcp.Complete(@mcp.CallToolResult::json(Json::number(42.0)))
    },
  )
  let server = builder.build()
  let client = try! test_client(name="client", version="1")
  let missing_input = server.handle_jsonrpc(
    try! client.request_raw(method_name="tools/call", params={
      "name": Json::string("bounded"),
    }),
  )
  guard missing_input
    is Some(Object({ "result": Object({ "isError": True, .. }), .. })) else {
    fail("expected actionable input validation error")
  }
  let bad_input = server.handle_jsonrpc(
    try! client.request_raw(method_name="tools/call", params={
      "name": Json::string("bounded"),
      "arguments": Json::object({ "count": Json::number(0.0) }),
    }),
  )
  guard bad_input
    is Some(
      Object(
        {
          "result": Object(
            {
              "resultType": String("complete"),
              "isError": True,
              "content": Array([Object({ "type": String("text"), .. })]),
              ..
            }
          ),
          ..
        }
      )
    ) else {
    fail("expected inputSchema validation error")
  }
  let bad_output = server.handle_jsonrpc(
    try! client.request_raw(method_name="tools/call", params={
      "name": Json::string("bounded"),
      "arguments": Json::object({ "count": Json::number(1.0) }),
    }),
  )
  guard bad_output
    is Some(
      Object({ "error": Object({ "code": Number(-32603.0, ..), .. }), .. })
    ) else {
    fail("expected outputSchema validation error")
  }
}

///|
async test "resource templates are readable through their registered handler" {
  let builder = try! ServerBuilder(name="resource-server", version="1")
  try! builder.resource_template(uri_template="notes://{id}", name="note", fn(
    _context,
    uri,
    captures,
  ) -> @mcp.HandlerOutcome[@mcp.ReadResourceResult] {
    @mcp.Complete(
      @mcp.ReadResourceResult::text(
        uri~,
        text=captures.get("id").unwrap_or("missing"),
      ),
    )
  })
  let server = builder.build()
  let client = try! test_client(name="client", version="1")
  let response = server.handle_jsonrpc(
    client.request_raw(method_name="resources/read", params={
      "uri": Json::string("notes://alpha"),
    }),
  )
  guard response
    is Some(
      Object(
        {
          "result": Object(
            {
              "contents": Array(
                [
                  Object(
                    {
                      "uri": String("notes://alpha"),
                      "text": String("alpha"),
                      ..
                    }
                  ),
                ]
              ),
              ..
            }
          ),
          ..
        }
      )
    ) else {
    fail("expected template handler result")
  }
}

///|
test "ServerBuilder duplicate tool registration fails" {
  let builder = try! ServerBuilder(name="test-server", version="1.0.0")
  try! builder.tool_raw(name="dummy", fn(_ctx, _input) {
    @mcp.Complete(@mcp.CallToolResult::text("dummy"))
  })
  let error_caught = Ref(false)
  builder.tool_raw(name="dummy", fn(_ctx, _input) {
    @mcp.Complete(@mcp.CallToolResult::text("dummy"))
  }) catch {
    @mcp.InvalidParams(_) => error_caught.val = true
    _ => ()
  }
  assert_true(error_caught.val)
}

///|
test "server constructor rejects empty protocol identities" {
  let assert_invalid_params = fn(
    f : () -> Unit raise @mcp.McpError,
  ) -> Unit raise {
    let error = try {
      f()
      false
    } catch {
      @mcp.InvalidParams(_) => true
      _ => false
    }
    assert_true(error)
  }
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    ignore(ServerBuilder(name="", version="1"))
  })
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    ignore(ServerBuilder(name="server", version="1", supported_versions=[""]))
  })
}

///|
test "server retains independent copies of mutable inputs" {
  let versions = [@mcp.LATEST_PROTOCOL_VERSION]
  let builder = try! ServerBuilder(
    name="server",
    version="1",
    supported_versions=versions,
  )
  let server = builder.build()
  versions[0] = "mutated"
  assert_true(server.supports_protocol_version(@mcp.LATEST_PROTOCOL_VERSION))
  assert_false(server.supports_protocol_version("mutated"))
}

///|
async test "prompts/get requires every advertised required argument" {
  let builder = try! ServerBuilder(name="server", version="1")
  try! builder.prompt(
    name="review",
    arguments=[@mcp.PromptArgument(name="document", required=true)],
    fn(_context, _arguments) { @mcp.Complete(@mcp.GetPromptResult::user("ok")) },
  )
  let server = builder.build()
  let client = try! test_client(name="client", version="1")
  guard server.handle_jsonrpc(
      try! client.request_raw(method_name="prompts/get", params={
        "name": Json::string("review"),
      }),
    )
    is Some(
      Object({ "error": Object({ "code": Number(-32602.0, ..), .. }), .. })
    ) else {
    fail("missing required prompt argument was accepted")
  }
}

///|
test "prompt argument descriptor names are unique" {
  let builder = try! ServerBuilder(name="server", version="1")
  let assert_invalid_params = fn(
    f : () -> Unit raise @mcp.McpError,
  ) -> Unit raise {
    let error = try {
      f()
      false
    } catch {
      @mcp.InvalidParams(_) => true
      _ => false
    }
    assert_true(error)
  }
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    builder.prompt(
      name="review",
      arguments=[
        @mcp.PromptArgument(name="document"),
        @mcp.PromptArgument(name="document"),
      ],
      fn(_context, _arguments) {
        @mcp.Complete(@mcp.GetPromptResult::user("ok"))
      },
    )
  })
}

///|
async test "transport descriptor snapshots do not expose the server registry" {
  let schema_fields : Map[String, Json] = { "type": Json::string("object") }
  let builder = try! ServerBuilder(name="server", version="1")
  try! builder.tool_raw(
    name="owned",
    input_schema=Json::object(schema_fields),
    fn(_context, _arguments) { @mcp.Complete(@mcp.CallToolResult::text("ok")) },
  )
  let server = builder.build()
  let descriptor = server.tool_descriptor("owned").unwrap()
  guard descriptor.input_schema is Object(fields) else {
    fail("descriptor did not contain an object schema")
  }
  fields["type"] = Json::string("string")
  let listed = server.handle_jsonrpc(
    try! test_client(name="client", version="1").request_raw(
      method_name="tools/list",
    ),
  )
  guard listed is Some(Object({ "result": Object(result), .. })) else {
    fail("tools/list did not return a result")
  }
  guard result["tools"]
    is Array(
      [
        Object({ "inputSchema": Object({ "type": String("object"), .. }), .. }),
        ..,
      ]
    ) else {
    fail("adapter snapshot mutation changed the server registry")
  }
}

///|
test "resource template validation rejects invalid syntax and supports literals" {
  let builder = try! ServerBuilder(name="server", version="1")
  let assert_invalid_params = fn(
    f : () -> Unit raise @mcp.McpError,
  ) -> Unit raise {
    let error = try {
      f()
      false
    } catch {
      @mcp.InvalidParams(_) => true
      _ => false
    }
    assert_true(error)
  }
  // Invalid unclosed {
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    builder.resource_template(uri_template="file:///items/{id", name="test", fn(
      _ctx,
      _uri,
      _vars,
    ) {
      @mcp.Complete(@mcp.ReadResourceResult::text(uri="a", text="b"))
    })
  })
  // Invalid nested {
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    builder.resource_template(
      uri_template="file:///items/{{id}}",
      name="test",
      fn(_ctx, _uri, _vars) {
        @mcp.ReadResourceResult::text(uri="a", text="b") |> @mcp.Complete
      },
    )
  })
  // Unexpected }
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    builder.resource_template(uri_template="file:///items/id}", name="test", fn(
      _ctx,
      _uri,
      _vars,
    ) {
      @mcp.HandlerOutcome::Complete(
        @mcp.ReadResourceResult::text(uri="a", text="b"),
      )
    })
  })
  // Valid with special characters in literals like . and +
  try! builder.resource_template(
    uri_template="file:///api/v1.0/items/{item_id}.json",
    name="item_template",
    fn(_ctx, _uri, _vars) {
      @mcp.HandlerOutcome::Complete(
        @mcp.ReadResourceResult::text(uri="a", text="b"),
      )
    },
  )
}

///|
test "client capabilities negotiation for roots and sampling" {
  let server = (try! ServerBuilder(name="server", version="1")).build()
  let result = try! @mcp.InputRequiredResult(input_requests={
    "roots": try! @mcp.InputRequest(method_name="roots/list"),
    "sampling": try! @mcp.InputRequest(
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
        "maxTokens": Json::number(1.0),
      }),
    ),
  })
  let context = try! @mcp.RequestContext(
    request_id=Json::number(1.0),
    method_name="tools/call",
    meta=@mcp.RequestMeta(
      client_capabilities=@mcp.ClientCapabilities(
        roots=@mcp.RootsCapability(),
        sampling=@mcp.SamplingCapability(),
      ),
    ),
  )
  try! server.validate_input_requests(context, result)

  let missing = try! @mcp.RequestContext(
    request_id=Json::number(2.0),
    method_name="tools/call",
    meta=@mcp.RequestMeta(),
  )
  try server.validate_input_requests(missing, result) catch {
    @mcp.MissingRequiredClientCapability(_, required) =>
      assert_true(required.roots is Some(_))
    _ => fail("expected missing capability")
  } noraise {
    _ => fail("expected missing capability")
  }
}

///|
test "subscription acceptance acknowledges the honored filter first" {
  let server = (try! ServerBuilder(
    name="server",
    version="1",
    tool_list_changed=true,
  )).build()
  let client = try! test_client(name="client", version="1")
  let request = client.request_raw(method_name="subscriptions/listen", params={
    "notifications": @mcp.SubscriptionFilter(
      tools_list_changed=true,
      prompts_list_changed=true,
    ).to_json(),
  })
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
            "notifications": Object({ "toolsListChanged": True, .. }),
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
test "empty cursor is a valid opaque cursor" {
  let page = try! paginate(["a", "b"], cursor="", page_size=1)
  assert_eq(page.items, ["a"])
  assert_eq(page.next_cursor, Some("1"))
}

///|
test "cursor parsing accepts the Int boundary and rejects overflow" {
  assert_eq(try! parse_cursor(Some("2147483647"), 2147483647), 2147483647)
  try ignore(parse_cursor(Some("2147483648"), 2147483647)) catch {
    @mcp.InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("overflowing cursor was accepted")
  }
}

///|
test "cursor parsing bounds work before decimal accumulation" {
  try ignore(parse_cursor(Some("000000000000000000000"), 1)) catch {
    @mcp.InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("overlong cursor was accepted")
  }
}
