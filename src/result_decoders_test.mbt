///|
test "complete tool results decode the official content union" {
  let result = try! @mcp.CallToolResult::from_json(
    Json::object({
      "resultType": Json::string("complete"),
      "content": Json::array([
        Json::object({
          "type": Json::string("text"),
          "text": Json::string("hello"),
        }),
        Json::object({
          "type": Json::string("image"),
          "data": Json::string("AA=="),
          "mimeType": Json::string("image/png"),
        }),
      ]),
      "structuredContent": Json::object({ "ok": Json::boolean(true) }),
    }),
  )
  assert_true(
    result.content
    is [
      @mcp.TextContent(text="hello", ..),
      @mcp.ImageContent(data="AA==", mime_type="image/png", ..),
    ],
  )
  assert_true(result.structured_content is Some(Object({ "ok": True, .. })))
  assert_false(result.is_error)
}

///|
test "list results preserve descriptors pagination caching and metadata" {
  let result = try! @mcp.ListToolsResult::from_json(
    Json::object({
      "resultType": Json::string("complete"),
      "tools": Json::array([
        Json::object({
          "name": Json::string("echo"),
          "description": Json::string("Echo input"),
          "inputSchema": Json::object({
            "type": Json::string("object"),
            "properties": Json::object({}),
          }),
        }),
      ]),
      "nextCursor": Json::string("next-page"),
      "ttlMs": Json::number(2500.0),
      "cacheScope": Json::string("public"),
      "_meta": Json::object({
        "io.modelcontextprotocol/serverInfo": Json::object({
          "name": Json::string("fixture"),
          "version": Json::string("1"),
        }),
      }),
    }),
  )
  assert_eq(result.tools[0].name, "echo")
  assert_eq(result.next_cursor, Some("next-page"))
  assert_eq(result.cache_policy.ttl_ms, 2500L)
  assert_eq(result.cache_policy.scope, @mcp.Public)
  assert_true(result.meta is Some(_))
}

///|
test "resource prompt and completion payloads decode to canonical types" {
  let resource = try! @mcp.ReadResourceResult::from_json(
    Json::object({
      "resultType": Json::string("complete"),
      "contents": Json::array([
        Json::object({
          "uri": Json::string("test://greeting"),
          "text": Json::string("hello"),
          "mimeType": Json::string("text/plain"),
        }),
      ]),
      "ttlMs": Json::number(0.0),
      "cacheScope": Json::string("private"),
    }),
  )
  assert_true(
    resource.contents
    is [@mcp.ResourceText(uri="test://greeting", text="hello", ..)],
  )
  assert_true(resource.cache_policy is Some(_))

  let prompt = try! @mcp.GetPromptResult::from_json(
    Json::object({
      "resultType": Json::string("complete"),
      "description": Json::string("Greeting prompt"),
      "messages": Json::array([
        Json::object({
          "role": Json::string("user"),
          "content": Json::object({
            "type": Json::string("text"),
            "text": Json::string("Say hello"),
          }),
        }),
      ]),
    }),
  )
  assert_true(
    prompt.messages
    is [{ role: @mcp.User, content: @mcp.TextContent(text="Say hello", ..) }],
  )

  let completion = try! @mcp.CompleteResult::from_json(
    Json::object({
      "resultType": Json::string("complete"),
      "completion": Json::object({
        "values": Json::array([Json::string("alpha"), Json::string("alpine")]),
        "total": Json::number(2.0),
        "hasMore": Json::boolean(false),
      }),
    }),
  )
  assert_eq(completion.values, ["alpha", "alpine"])
  assert_eq(completion.total, Some(2))
  assert_false(completion.has_more)
}
