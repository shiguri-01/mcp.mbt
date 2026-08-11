///|
async test "each request carries the client context used by the server" {
  let server = try! @mcp.Server(
    name="test-server",
    version="1.0.0",
    instructions="Use the echo tool",
    cache_policy=try! @mcp.CachePolicy(ttl_ms=1000L, scope=@mcp.Public),
  )
  try! server.json_tool(
    name="whoami",
    description="Return the request client name",
    fn(context, _arguments) -> @mcp.HandlerOutcome[@mcp.CallToolResult] {
      let name = context.meta().client_info
        .map(info => info.name)
        .unwrap_or("anonymous")
      @mcp.Complete(@mcp.CallToolResult::text(name))
    },
  )
  let first = @mcp.Client(name="client-a", version="1")
  let discover_response = server.handle_jsonrpc(first.discover_request())
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
  let tools_response = server.handle_jsonrpc(first.list_tools_request())
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
  let second = @mcp.Client(name="client-b", version="1")
  let call_response = server.handle_jsonrpc(
    try! second.call_tool_request(name="whoami"),
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
  let server = try! @mcp.Server(name="server", version="1")
  let old = @mcp.Client(name="old", version="1", protocol_version="1900-01-01")
  guard server.handle_jsonrpc(old.discover_request())
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
  let server = try! @mcp.Server(name="server", version="1")
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
  let server = try! @mcp.Server(name="server", version="1")
  guard server.handle_jsonrpc(Json::array([]))
    is Some(
      Object({ "error": Object({ "code": Number(-32600.0, ..), .. }), .. })
    ) else {
    fail("expected batch rejection")
  }
}

///|
async test "JSON-RPC notifications never receive a response" {
  let server = try! @mcp.Server(name="server", version="1")
  let notification = Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("com.example/event"),
    "params": Json::object({}),
  })
  assert_eq(server.handle_jsonrpc(notification), None)
}

///|
async test "MRTR retries echo opaque state and supply input responses" {
  let server = try! @mcp.Server(name="server", version="1")
  try! server.json_tool(name="confirm", fn(
    context,
    _arguments,
  ) -> @mcp.HandlerOutcome[@mcp.CallToolResult] {
    if context.request_state() is Some("opaque") &&
      context.input_responses() is Some(responses) &&
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
  let client = @mcp.Client(
    name="client",
    version="1",
    capabilities=@mcp.ClientCapabilities(
      elicitation=@mcp.ElicitationCapability(form=Json::object({})),
    ),
  )
  let first = server.handle_jsonrpc(
    try! client.call_tool_request(name="confirm"),
  )
  guard first is Some(message) else { fail("expected MRTR response") }
  let first_outcome = try! client.decode_response(message)
  guard first_outcome is @mcp.InputRequired(required) else {
    fail("expected input_required")
  }
  let retry = try! client.call_tool_request(
    name="confirm",
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
  let server = try! @mcp.Server(name="server", version="1")
  try! server.json_tool(name="confirm", fn(
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
  let client = @mcp.Client(name="client", version="1")
  let response = server.handle_jsonrpc(
    try! client.call_tool_request(name="confirm"),
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
  let server = try! @mcp.Server(name="server", version="1")
  try! server.json_tool(name="work", async fn(
    context,
    _arguments,
  ) -> @mcp.HandlerOutcome[@mcp.CallToolResult] raise @mcp.McpError {
    context.report_progress(progress=0.5, total=1.0, message="halfway")
    @mcp.Complete(@mcp.CallToolResult::text("done"))
  })
  let emitted : Array[Json] = []
  let hooks = @mcp.RequestHooks(emit_notification=fn(message) {
    emitted.push(message)
  })
  let client = @mcp.Client(name="client", version="1")
  let response = server.handle_jsonrpc_with_hooks(
    try! client.call_tool_request(
      name="work",
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
  let server = try! @mcp.Server(name="schema-server", version="1")
  try! server.json_tool(
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
  let client = @mcp.Client(name="client", version="1")
  let missing_input = server.handle_jsonrpc(
    try! client.call_tool_request(name="bounded", arguments={}),
  )
  guard missing_input
    is Some(Object({ "result": Object({ "isError": True, .. }), .. })) else {
    fail("expected actionable input validation error")
  }
  let bad_input = server.handle_jsonrpc(
    try! client.call_tool_request(name="bounded", arguments={
      "count": Json::number(0.0),
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
    try! client.call_tool_request(name="bounded", arguments={
      "count": Json::number(1.0),
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
  let server = try! @mcp.Server(name="resource-server", version="1")
  try! server.resource_template(uri_template="notes://{id}", name="note", fn(
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
  let client = @mcp.Client(name="client", version="1")
  let response = server.handle_jsonrpc(
    client.read_resource_request(uri="notes://alpha"),
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
