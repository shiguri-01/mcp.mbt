///|
fn assert_invalid_params(run : () -> Unit raise @mcp.McpError) -> Unit raise {
  try run() catch {
    @mcp.InvalidParams(_) => ()
    _ => fail("expected InvalidParams")
  } noraise {
    _ => fail("expected InvalidParams")
  }
}

///|
test "descriptor constructors enforce numeric wire constraints" {
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    ignore(@mcp.Resource(uri="memory://a", name="a", size=-1L))
  })
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    ignore(
      @mcp.ResourceLink::ResourceLink(uri="memory://a", name="a", size=-1L),
    )
  })
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    ignore(@mcp.CompleteResult(values=[], total=-1))
  })
  for priority in [-0.1, 1.1, 0.0 / 0.0, 1.0 / 0.0] {
    assert_invalid_params(fn() -> Unit raise @mcp.McpError {
      ignore(@mcp.Annotations(priority~))
    })
  }
  ignore(try! @mcp.Resource(uri="memory://a", name="a", size=0L))
  ignore(
    try! @mcp.ResourceLink::ResourceLink(uri="memory://a", name="a", size=0L),
  )
  ignore(try! @mcp.CompleteResult(values=[], total=0))
  ignore(try! @mcp.Annotations(priority=1.0))
}

///|
test "result decoders enforce descriptor numeric constraints" {
  assert_invalid_params(() => {
    ignore(
      @mcp.Content::from_json(
        Json::object({
          "type": Json::string("resource_link"),
          "uri": Json::string("memory://a"),
          "name": Json::string("a"),
          "size": Json::number(-1.0),
        }),
      ),
    )
  })
  assert_invalid_params(() => {
    ignore(
      @mcp.Content::from_json(
        Json::object({
          "type": Json::string("text"),
          "text": Json::string("a"),
          "annotations": Json::object({ "priority": Json::number(1.1) }),
        }),
      ),
    )
  })
  assert_invalid_params(() => {
    ignore(
      @mcp.CompleteResult::from_json(
        Json::object({
          "resultType": Json::string("complete"),
          "completion": Json::object({
            "values": Json::array([]),
            "total": Json::number(-1.0),
          }),
        }),
      ),
    )
  })
}

///|
test "protocol objects retain independent copies of mutable inputs" {
  let schema_fields : Map[String, Json] = { "type": Json::string("object") }
  let tool = try! @mcp.Tool(
    name="stable",
    input_schema=Json::object(schema_fields),
  )
  schema_fields["type"] = Json::string("string")
  guard tool.to_json()
    is Object({ "inputSchema": Object({ "type": String("object"), .. }), .. }) else {
    fail("tool schema changed with caller-owned JSON")
  }
  let resources = ["memory://a"]
  let filter = @mcp.SubscriptionFilter(resource_subscriptions=resources)
  resources[0] = "memory://mutated"
  guard filter.to_json()
    is Object({ "resourceSubscriptions": Array([String("memory://a")]), .. }) else {
    fail("subscription filter changed with caller-owned array")
  }

  let sizes = ["16x16"]
  let icon = @mcp.Icon(src="data:image/png;base64,AA==", sizes~)
  let annotations = try! @mcp.Annotations(audience=[@mcp.Role::User])
  let resource = try! @mcp.Resource(
    uri="memory://owned",
    name="owned",
    icons=[icon],
    annotations~,
  )
  icon.sizes[0] = "mutated"
  annotations.audience[0] = @mcp.Role::Assistant
  guard resource.to_json()
    is Object(
      {
        "icons": Array([Object({ "sizes": Array([String("16x16")]), .. })]),
        "annotations": Object({ "audience": Array([String("user")]), .. }),
        ..
      }
    ) else {
    fail("resource descriptor changed with nested caller-owned arrays")
  }

  let request_capabilities = @mcp.ClientCapabilities(extensions={
    "com.example/request": Json::object({ "enabled": Json::boolean(true) }),
  })
  let request_info = @mcp.Implementation(name="request-client", version="1", icons=[
    icon,
  ])
  let request_meta = try! @mcp.RequestMeta(
    client_info=request_info,
    client_capabilities=request_capabilities,
  )
  request_capabilities.extensions["com.example/request"] = Json::object({
    "enabled": Json::boolean(false),
  })
  request_info.icons[0].sizes[0] = "changed-again"
  guard request_meta.to_json()
    is Object(
      {
        "io.modelcontextprotocol/clientCapabilities": Object(
          {
            "extensions": Object(
              { "com.example/request": Object({ "enabled": True, .. }), .. }
            ),
            ..
          }
        ),
        "io.modelcontextprotocol/clientInfo": Object(
          {
            "icons": Array(
              [Object({ "sizes": Array([String("mutated")]), .. })]
            ),
            ..
          }
        ),
        ..
      }
    ) else {
    fail(
      "request metadata changed with caller-owned implementation or capabilities",
    )
  }
}

///|
test "prompt argument descriptor names are unique" {
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    ignore(
      @mcp.Prompt(name="review", arguments=[
        @mcp.PromptArgument(name="document"),
        @mcp.PromptArgument(name="document"),
      ]),
    )
  })
}

///|
test "decoded prompt argument descriptor names are unique" {
  assert_invalid_params(() => {
    ignore(
      @mcp.ListPromptsResult::from_json(
        Json::object({
          "resultType": Json::string("complete"),
          "prompts": [
            Json::object({
              "name": Json::string("review"),
              "arguments": [
                Json::object({ "name": Json::string("document") }),
                Json::object({ "name": Json::string("document") }),
              ].to_json(),
            }),
          ].to_json(),
          "ttlMs": Json::number(0.0),
          "cacheScope": Json::string("private"),
        }),
      ),
    )
  })
}

///|
test "protocol result constructors own nested metadata and JSON values" {
  let structured : Map[String, Json] = { "answer": Json::string("ok") }
  let extra : Map[String, Json] = {
    "com.example/result": Json::object({ "enabled": Json::boolean(true) }),
  }
  let result_meta = try! @mcp.ResultMeta(extra~)
  let result = @mcp.CallToolResult(
    content=[],
    structured_content=Json::object(structured),
    meta=result_meta,
  )
  structured["answer"] = Json::string("changed")
  extra["com.example/result"] = Json::null()
  guard result.to_json()
    is Object(
      {
        "structuredContent": Object({ "answer": String("ok"), .. }),
        "_meta": Object(
          { "com.example/result": Object({ "enabled": True, .. }), .. }
        ),
        ..
      }
    ) else {
    fail("tool result retained caller-owned nested JSON")
  }
}

///|
test "request options own retry responses and metadata" {
  let responses : Map[String, @mcp.InputResponse] = Map([
    (
      "answer",
      @mcp.InputResponse(Json::object({ "value": Json::string("ok") })),
    ),
  ])
  let meta : Map[String, Json] = {
    "com.example/request": Json::object({ "enabled": Json::boolean(true) }),
  }
  let options = @mcp.RequestOptions(input_responses=responses, meta~)
  responses["answer"] = @mcp.InputResponse(Json::null())
  meta["com.example/request"] = Json::null()
  let params = try! options.request_params(
    {},
    client_capabilities=@mcp.ClientCapabilities::empty(),
  )
  guard params
    is Object(
      {
        "inputResponses": Object(
          { "answer": Object({ "value": String("ok"), .. }), .. }
        ),
        "_meta": Object(
          { "com.example/request": Object({ "enabled": True, .. }), .. }
        ),
        ..
      }
    ) else {
    fail("request options retained caller-owned retry data")
  }
}

///|
test "request meta constructor rejects empty protocol version" {
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    ignore(@mcp.RequestMeta(protocol_version=""))
  })
}
