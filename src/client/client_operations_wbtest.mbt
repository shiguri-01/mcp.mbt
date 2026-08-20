///|
priv struct MockTransport {
  handle : (Json, (Json) -> Unit) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError
  notifications : Array[Json]
}

///|
fn MockTransport::new(
  handle : (Json, (Json) -> Unit) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError,
) -> MockTransport {
  { handle, notifications: [] }
}

///|
impl ClientTransport for MockTransport with fn request_with_notifications(
  self : MockTransport,
  request : Json,
  on_notification~ : (Json) -> Unit,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  (self.handle)(request, on_notification)
}

///|
impl ClientTransport for MockTransport with fn notify(
  self : MockTransport,
  notification : Json,
) -> Unit raise @mcp.McpError {
  self.notifications.push(notification)
}

///|
impl ClientTransport for MockTransport with fn close(_self : MockTransport) -> Unit {
  ()
}

///|
async test "client discover over ClientTransport" {
  let discover_transport = MockTransport::new((req, _) => {
    guard req is Object({ "method": String("server/discover"), .. }) else {
      panic()
    }
    @mcp.Complete(
      Json::object({
        "resultType": Json::string("complete"),
        "supportedVersions": Json::array([Json::string(@mcp.PROTOCOL_VERSION)]),
        "capabilities": Json::object({}),
        "ttlMs": Json::number(3600.0, repr="3600"),
        "cacheScope": Json::string("public"),
      }),
    )
  })
  let client = try! Client(
    name="test-client",
    version="1.0.0",
    transport=discover_transport,
  )
  let discover_res = try! client.discover()
  assert_eq(discover_res.supported_versions, [@mcp.PROTOCOL_VERSION])
}

///|
async test "client list_tools over ClientTransport" {
  let list_tools_transport = MockTransport::new((req, _) => {
    guard req is Object({ "method": String("tools/list"), .. }) else { panic() }
    @mcp.Complete(
      Json::object({
        "resultType": Json::string("complete"),
        "tools": Json::array([
          Json::object({
            "name": Json::string("calculate"),
            "description": Json::string("Performs math"),
            "inputSchema": Json::object({ "type": Json::string("object") }),
          }),
        ]),
        "ttlMs": Json::number(0.0, repr="0"),
        "cacheScope": Json::string("private"),
      }),
    )
  })
  let client = try! Client(
    name="test-client",
    version="1.0.0",
    transport=list_tools_transport,
  )
  let tools_res = try! client.list_tools()
  assert_eq(tools_res.tools.length(), 1)
  assert_eq(tools_res.tools[0].name, "calculate")
}

///|
async test "client call_tool over ClientTransport" {
  let call_tool_transport = MockTransport::new((req, _) => {
    guard req
      is Object(
        { "method": String("tools/call"), "params": Object(params), .. }
      ) else {
      panic()
    }
    guard params.get("name") == Some(Json::string("calculate")) else { panic() }
    @mcp.Complete(
      Json::object({
        "resultType": Json::string("complete"),
        "content": Json::array([
          Json::object({
            "type": Json::string("text"),
            "text": Json::string("42"),
          }),
        ]),
      }),
    )
  })
  let client = try! Client(
    name="test-client",
    version="1.0.0",
    transport=call_tool_transport,
  )
  let call_outcome = try! client.call_tool(name="calculate")
  match call_outcome {
    @mcp.Complete(res) => {
      assert_eq(res.content.length(), 1)
      match res.content[0] {
        @mcp.Content::TextContent(text~, ..) => assert_eq(text, "42")
        _ => fail("expected text content")
      }
    }
    _ => fail("expected Complete outcome")
  }
}

///|
async test "client MRTR resolving with multiple rounds" {
  let mut round = 0
  let mrtr_transport = MockTransport::new((req, _) => {
    round += 1
    if round == 1 {
      @mcp.InputRequired(
        @mcp.InputRequiredResult(request_state="needs_input", input_requests={
          "req1": @mcp.InputRequest(
            method_name="elicitation/create",
            params=Json::object({
              "mode": Json::string("form"),
              "message": Json::string("Please enter your name"),
              "requestedSchema": Json::object({
                "type": Json::string("object"),
                "properties": Json::object({
                  "name": Json::object({ "type": Json::string("string") }),
                }),
                "required": Json::array([Json::string("name")]),
              }),
            }),
          ),
        }),
      )
    } else {
      guard req
        is Object(
          {
            "params": Object(
              {
                "inputResponses": Object(
                  {
                    "req1": Object(
                      {
                        "action": String("accept"),
                        "content": Object({ "name": String("Alice"), .. }),
                        ..
                      }
                    ),
                    ..
                  }
                ),
                "requestState": String("needs_input"),
                ..
              }
            ),
            ..
          }
        ) else {
        panic()
      }
      @mcp.Complete(
        Json::object({
          "resultType": Json::string("complete"),
          "content": Json::array([
            Json::object({
              "type": Json::string("text"),
              "text": Json::string("Hello Alice!"),
            }),
          ]),
        }),
      )
    }
  })
  let client = try! Client(
    name="test-client",
    version="1.0.0",
    transport=mrtr_transport,
    capabilities=@mcp.ClientCapabilities(
      elicitation=@mcp.ElicitationCapability(form=Json::object({})),
    ),
  )
  let outcome = try! client.call_tool(name="greet_wizard", resolve_input=fn(
    reqs,
  ) -> Map[String, @mcp.InputResponse] raise @mcp.McpError {
    guard reqs.length() == 1 else {
      raise @mcp.InvalidParams("expected 1 request")
    }
    {
      "req1": @mcp.InputResponse(
        Json::object({
          "action": Json::string("accept"),
          "content": Json::object({ "name": Json::string("Alice") }),
        }),
      ),
    }
  })
  guard outcome is @mcp.Complete(result) else {
    fail("expected Complete outcome")
  }
  assert_eq(round, 2)
  match result.content[0] {
    @mcp.Content::TextContent(text~, ..) => assert_eq(text, "Hello Alice!")
    _ => fail("expected text content")
  }
}

///|
async test "client listen over ClientTransport" {
  let notifications_received : Array[Json] = []
  let listen_transport = MockTransport::new((req, on_notification) => {
    guard req is Object({ "method": String("subscriptions/listen"), .. }) else {
      panic()
    }
    on_notification(
      Json::object({
        "jsonrpc": Json::string("2.0"),
        "method": Json::string("notifications/subscriptions/acknowledged"),
        "params": Json::object({
          "_meta": Json::object({
            "io.modelcontextprotocol/subscriptionId": Json::string("sub-123"),
          }),
          "notifications": Json::object({
            "toolsListChanged": Json::boolean(true),
          }),
        }),
      }),
    )
    on_notification(
      Json::object({
        "jsonrpc": Json::string("2.0"),
        "method": Json::string("notifications/tools/list_changed"),
        "params": Json::object({
          "_meta": Json::object({
            "io.modelcontextprotocol/subscriptionId": Json::string("sub-123"),
          }),
        }),
      }),
    )
    @mcp.Complete(
      Json::object({
        "resultType": Json::string("complete"),
        "_meta": Json::object({
          "io.modelcontextprotocol/subscriptionId": Json::string("sub-123"),
        }),
      }),
    )
  })
  let client = try! Client(
    name="test-client",
    version="1.0.0",
    transport=listen_transport,
  )
  let final_result = try! client.listen(
    notifications=@mcp.SubscriptionFilter(tools_list_changed=true),
    on_notification=fn(n) { notifications_received.push(n) },
  )
  assert_eq(notifications_received.length(), 2)
  guard final_result is Object(res) else { fail("expected object result") }
  assert_eq(res.get("resultType"), Some(Json::string("complete")))
}

///|
test "client constructor rejects empty protocol identities" {
  let r1 = try
    ignore(Client(name="", version="1", transport=NoopTransport()))
  catch {
    @mcp.InvalidParams(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(r1)
  let r2 = try
    ignore(
      Client(
        name="client",
        version="",
        protocol_version="",
        transport=NoopTransport(),
      ),
    )
  catch {
    @mcp.InvalidParams(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(r2)
}

///|
test "metadata keys follow the MCP prefix and name grammar" {
  let client = try! Client(
    name="client",
    version="1",
    transport=NoopTransport(),
  )
  try
    client.request_raw(
      method_name="example/run",
      options=@mcp.RequestOptions(meta={ "bad/key/extra": Json::boolean(true) }),
    )
  catch {
    @mcp.InvalidParams(_) => ()
    _ => fail("expected invalid metadata key")
  } noraise {
    _ => fail("invalid metadata key must be rejected")
  }
  ignore(
    try! client.request_raw(
      method_name="example/run",
      options=@mcp.RequestOptions(meta={
        "com.example/trace-id": Json::string("1"),
      }),
    ),
  )
}

///|
test "extension result types require an advertised extension mapping" {
  let capabilities = @mcp.ClientCapabilities(extensions={
    "com.example/flow": Json::object({}),
  })
  let client = try! Client(
    name="client",
    version="1",
    transport=NoopTransport(),
    capabilities~,
    extension_result_types={ "paused": "com.example/flow" },
  )
  let response = @jsonrpc.Response::Success(
    id=try! @jsonrpc.RequestId::number(1.0),
    result=Json::object({
      "resultType": Json::string("paused"),
      "resumeToken": Json::string("next"),
    }),
  ).to_json()
  assert_true(
    client.decode_response(response) is @mcp.ExtensionResult("paused", _),
  )
  let strict = try! Client(
    name="strict",
    version="1",
    transport=NoopTransport(),
  )
  try strict.decode_response(response) catch {
    @mcp.InvalidRequest("unknown resultType: paused") => ()
    _ => fail("expected unknown result type")
  } noraise {
    _ => fail("unadvertised result type must be rejected")
  }
}

///|
test "client retains independent copies of mutable inputs" {
  let settings : Map[String, Json] = { "enabled": Json::boolean(true) }
  let extensions : Map[String, Json] = {
    "com.example/feature": Json::object(settings),
  }
  let client = try! Client(
    name="client",
    version="1",
    transport=NoopTransport(),
    capabilities=@mcp.ClientCapabilities(extensions~),
  )
  settings["enabled"] = Json::boolean(false)
  guard client.capabilities.to_json()
    is Object(
      {
        "extensions": Object(
          {
            "com.example/feature": Object(
              { "enabled": True, "mutated"? : None, .. }
            ),
            ..
          }
        ),
        ..
      }
    ) else {
    fail("client capabilities mutated")
  }
}

///|
async test "offline client raises InternalError on operations" {
  let client = try! Client(
    name="client",
    version="1",
    transport=NoopTransport(),
  )
  let error_caught = try {
    ignore(client.discover())
    false
  } catch {
    @mcp.InternalError("client is using NoopTransport") => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(error_caught)
}
