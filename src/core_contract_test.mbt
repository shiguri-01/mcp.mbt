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
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    ignore(
      @mcp.decode_content_block(
        Json::object({
          "type": Json::string("resource_link"),
          "uri": Json::string("memory://a"),
          "name": Json::string("a"),
          "size": Json::number(-1.0),
        }),
      ),
    )
  })
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    ignore(
      @mcp.decode_content_block(
        Json::object({
          "type": Json::string("text"),
          "text": Json::string("a"),
          "annotations": Json::object({ "priority": Json::number(1.1) }),
        }),
      ),
    )
  })
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    ignore(
      @mcp.decode_complete_result(
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
  let versions = [@mcp.latest_protocol_version]
  let server = try! @mcp.Server(
    name="server",
    version="1",
    supported_versions=versions,
  )
  versions[0] = "mutated"
  assert_eq(server.supported_versions(), [@mcp.latest_protocol_version])
  let settings : Map[String, Json] = { "enabled": Json::boolean(true) }
  let extensions : Map[String, Json] = {
    "com.example/feature": Json::object(settings),
  }
  let client = try! @mcp.Client(
    name="client",
    version="1",
    capabilities=@mcp.ClientCapabilities(extensions~),
  )
  settings["enabled"] = Json::boolean(false)
  guard client.capabilities.to_json()
    is Object(
      {
        "extensions": Object(
          { "com.example/feature": Object({ "enabled": True, .. }), .. }
        ),
        ..
      }
    ) else {
    fail("client capabilities changed with caller-owned JSON")
  }
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
async test "prompts/get requires every advertised required argument" {
  let server = try! @mcp.Server(name="server", version="1")
  try! server.prompt(
    name="review",
    arguments=[@mcp.PromptArgument(name="document", required=true)],
    fn(_context, _arguments) { @mcp.Complete(@mcp.GetPromptResult::user("ok")) },
  )
  let client = try! @mcp.Client(name="client", version="1")
  guard server.handle_jsonrpc(try! client.get_prompt_request(name="review"))
    is Some(
      Object({ "error": Object({ "code": Number(-32602.0, ..), .. }), .. })
    ) else {
    fail("missing required prompt argument was accepted")
  }
}

///|
test "prompt argument descriptor names are unique" {
  let server = try! @mcp.Server(name="server", version="1")
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    server.prompt(
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
test "decoded prompt argument descriptor names are unique" {
  assert_invalid_params(fn() -> Unit raise @mcp.McpError {
    ignore(
      @mcp.decode_list_prompts_result(
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
