///|
priv struct MockTransport {
  handle : (Json, (Json) -> Unit) -> HandlerOutcome[Json]
  notifications : Array[Json]
}

///|
fn MockTransport::new(
  handle : (Json, (Json) -> Unit) -> HandlerOutcome[Json],
) -> MockTransport {
  { handle, notifications: [] }
}

///|
impl ClientTransport for MockTransport with fn request_with_notifications(
  self : MockTransport,
  request : Json,
  on_notification~ : (Json) -> Unit,
) -> HandlerOutcome[Json] raise McpError {
  (self.handle)(request, on_notification)
}

///|
impl ClientTransport for MockTransport with fn notify(
  self : MockTransport,
  notification : Json,
) -> Unit raise McpError {
  self.notifications.push(notification)
}

///|
async test "client discover over ClientTransport" {
  let client = try! Client(name="test-client", version="1.0.0")
  let discover_transport = MockTransport::new((req, _) => {
    guard req is Object({ "method": String("server/discover"), .. }) else {
      panic()
    }
    Complete(
      Json::object({
        "resultType": Json::string("complete"),
        "supportedVersions": Json::array([Json::string(LATEST_PROTOCOL_VERSION)]),
        "capabilities": Json::object({}),
        "ttlMs": Json::number(3600.0, repr="3600"),
        "cacheScope": Json::string("public"),
      }),
    )
  })
  let discover_res = try! client.discover(discover_transport)
  assert_eq(discover_res.supported_versions, [LATEST_PROTOCOL_VERSION])
}

///|
async test "client list_tools over ClientTransport" {
  let client = try! Client(name="test-client", version="1.0.0")
  let list_tools_transport = MockTransport::new((req, _) => {
    guard req is Object({ "method": String("tools/list"), .. }) else { panic() }
    Complete(
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
  let tools_res = try! client.list_tools(list_tools_transport)
  assert_eq(tools_res.tools.length(), 1)
  assert_eq(tools_res.tools[0].name, "calculate")
}

///|
async test "client call_tool over ClientTransport" {
  let client = try! Client(name="test-client", version="1.0.0")
  let call_tool_transport = MockTransport::new((req, _) => {
    guard req
      is Object(
        { "method": String("tools/call"), "params": Object(params), .. }
      ) else {
      panic()
    }
    guard params.get("name") == Some(Json::string("calculate")) else { panic() }
    Complete(
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
  let call_outcome = try! client.call_tool(
    call_tool_transport,
    name="calculate",
  )
  guard call_outcome is Complete(tool_result) else {
    fail("expected complete outcome")
  }
  assert_eq(tool_result.content.length(), 1)
}

///|
async test "client complete over ClientTransport" {
  let client = try! Client(name="test-client", version="1.0.0")
  let complete_transport = MockTransport::new((req, _) => {
    guard req is Object({ "method": String("completion/complete"), .. }) else {
      panic()
    }
    Complete(
      Json::object({
        "resultType": Json::string("complete"),
        "completion": Json::object({
          "values": Json::array([Json::string("opt1"), Json::string("opt2")]),
        }),
      }),
    )
  })
  let comp_res = try! client.complete(
    complete_transport,
    reference=CompletionReference::prompt(name="summarize"),
    argument_name="lang",
    argument_value="moo",
  )
  assert_eq(comp_res.values, ["opt1", "opt2"])
}

///|
async test "client MRTR tool resolution over ClientTransport" {
  let client = try! Client(name="test-client", version="1.0.0")
  let round = [0]

  let mrtr_transport = MockTransport::new((req, _) => {
    guard req
      is Object(
        { "method": String("tools/call"), "params": Object(params), .. }
      ) else {
      panic()
    }
    round[0] += 1
    if round[0] == 1 {
      InputRequired(
        try! InputRequiredResult::from_json(
          Json::object({
            "resultType": Json::string("input_required"),
            "inputRequests": Json::object({
              "roots": Json::object({
                "method": Json::string("roots/list"),
                "params": Json::object({}),
              }),
            }),
          }),
        ),
      )
    } else {
      guard params.get("inputResponses") is Some(Object(resps)) else { panic() }
      guard resps.contains("roots") else { panic() }
      Complete(
        Json::object({
          "resultType": Json::string("complete"),
          "content": Json::array([
            Json::object({
              "type": Json::string("text"),
              "text": Json::string("Authenticated"),
            }),
          ]),
        }),
      )
    }
  })

  let final_result = try! client.call_tool_resolving(
    mrtr_transport,
    name="secure_tool",
    resolve=fn(requests) {
      let responses : Map[String, InputResponse] = Map([])
      if requests.contains("roots") {
        responses["roots"] = InputResponse(
          Json::object({ "roots": Json::array([]) }),
        )
      }
      responses
    },
  )
  assert_eq(round[0], 2)
  assert_eq(final_result.content.length(), 1)
}
