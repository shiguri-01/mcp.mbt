///|
test "tool schemas preserve arbitrary 2020-12 keywords" {
  let input_schema = Json::object({
    "type": Json::string("object"),
    "$defs": Json::object({
      "value": Json::object({ "type": Json::string("string") }),
    }),
    "if": Json::object({ "required": ["mode"].to_json() }),
    "then": Json::object({ "required": ["value"].to_json() }),
    "unevaluatedProperties": Json::boolean(false),
  })
  let output_schema = Json::boolean(true)
  let tool = try! @mcp.Tool(name="conditional", input_schema~, output_schema~, icons=[
    @mcp.Icon(src="https://example.com/tool.png", sizes=["48x48"]),
  ]).to_json()
  guard tool is Object(fields) else { fail("expected tool object") }
  assert_eq(fields["inputSchema"], input_schema)
  assert_eq(fields["outputSchema"], output_schema)
  guard fields["icons"] is Array([Object(icon)]) else {
    fail("expected tool icon")
  }
  assert_eq(icon["sizes"], ["48x48"].to_json())
}

///|
test "tool input schema requires an object root" {
  try
    @mcp.Tool(
      name="invalid",
      input_schema=Json::object({ "type": Json::string("string") }),
    )
  catch {
    @mcp.InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("expected invalid tool schema to raise")
  }
}

///|
test "tool constructor rejects network schema references" {
  try
    @mcp.Tool(
      name="invalid-ref",
      input_schema=Json::object({
        "type": Json::string("object"),
        "$ref": Json::string("https://example.com/schema.json"),
      }),
    )
  catch {
    @mcp.InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("expected network reference to raise")
  }
}

///|
test "prompt metadata and messages match the content union" {
  let prompt = (try! @mcp.Prompt(name="review", icons=[
    @mcp.Icon(src="data:image/png;base64,AA=="),
  ])).to_json()
  guard prompt is Object({ "icons": Array([Object(icon)]), .. }) else {
    fail("expected prompt icon")
  }
  assert_eq(icon["src"], Json::string("data:image/png;base64,AA=="))
  let message = @mcp.PromptMessage(
    role=@mcp.Role::Assistant,
    content=@mcp.Content::resource_link(
      @mcp.ResourceLink(uri="memory://report", name="report"),
    ),
  ).to_json()
  guard message
    is Object(
      {
        "role": String("assistant"),
        "content": Object({ "type": String("resource_link"), .. }),
        ..
      }
    ) else {
    fail("expected typed prompt message")
  }
}

///|
test "operation payloads exclude result envelope metadata" {
  for
    result in [
      @mcp.CallToolResult::json(Json::array([Json::number(1.0)])).to_json(),
      @mcp.ReadResourceResult::text(uri="memory://x", text="x").to_json(),
      @mcp.GetPromptResult::user("hello").to_json(),
      (try! @mcp.CompleteResult(values=["one"])).to_json(),
    ] {
    guard result is Object(fields) else { fail("expected result object") }
    assert_true(!fields.contains("resultType"))
    assert_true(!fields.contains("_meta"))
  }
}

///|
test "subscription filters and acknowledgements use protocol field names" {
  let filter = @mcp.SubscriptionFilter(tools_list_changed=true, resource_subscriptions=[
    "memory://status",
  ])
  let notifications = filter.to_json()
  guard notifications is Object(fields) else {
    fail("expected subscription filter object")
  }
  assert_eq(fields["toolsListChanged"], Json::boolean(true))
  assert_true(!fields.contains("promptsListChanged"))
  let ack = @mcp.subscriptions_acknowledged_notification(
    subscription_id=Json::string("subscription-1"),
    notifications=filter,
  )
  guard ack
    is Object(
      {
        "method": String("notifications/subscriptions/acknowledged"),
        "params": Object(
          {
            "_meta": Object(
              {
                "io.modelcontextprotocol/subscriptionId": String(
                  "subscription-1"
                ),
                ..
              }
            ),
            ..
          }
        ),
        ..
      }
    ) else {
    fail("expected subscription acknowledgement")
  }
}
