///|
test "result metadata merges extras and protects serverInfo" {
  let sdk_info = @mcp.Implementation(name="sdk", version="2")
  let result = try! @mcp.complete_result(
    Json::object({
      "_meta": Json::object({
        "existing": Json::string("kept"),
        "io.modelcontextprotocol/serverInfo": Json::object({
          "name": Json::string("untrusted"),
          "version": Json::string("0"),
        }),
      }),
    }),
    server_info=sdk_info,
    meta={ "added": Json::boolean(true) },
  )
  guard result
    is Object(
      {
        "_meta": Object(
          {
            "existing": String("kept"),
            "added": True,
            "io.modelcontextprotocol/serverInfo": Object(
              { "name": String("sdk"), "version": String("2"), .. }
            ),
            ..
          }
        ),
        ..
      }
    ) else {
    fail("expected merged result metadata")
  }
}

///|
test "discover and request implementation codecs retain icons and metadata" {
  let discover : @mcp.DiscoverResult = try! @json.from_json(
    Json::object({
      "resultType": Json::string("complete"),
      "supportedVersions": [Json::string(@mcp.latest_protocol_version)].to_json(),
      "capabilities": Json::object({}),
      "ttlMs": Json::number(5.0),
      "cacheScope": Json::string("private"),
      "_meta": Json::object({
        "trace": Json::string("t-1"),
        "io.modelcontextprotocol/serverInfo": Json::object({
          "name": Json::string("server"),
          "version": Json::string("1"),
          "icons": [
            Json::object({
              "src": Json::string("https://example.test/icon.png"),
              "mimeType": Json::string("image/png"),
              "theme": Json::string("dark"),
            }),
          ].to_json(),
        }),
      }),
    }),
  )
  guard discover.meta
    is Some(
      {
        server_info: Some({ icons: [{ mime_type: Some("image/png"), .. }], .. }),
        extra: { "trace": String("t-1"), .. },
      }
    ) else {
    fail("expected discover metadata and server icons")
  }

  let request_meta = try! @mcp.parse_request_meta(
    Json::object({
      "io.modelcontextprotocol/protocolVersion": Json::string(
        @mcp.latest_protocol_version,
      ),
      "io.modelcontextprotocol/clientCapabilities": Json::object({}),
      "io.modelcontextprotocol/clientInfo": Json::object({
        "name": Json::string("client"),
        "version": Json::string("1"),
        "icons": [
          Json::object({ "src": Json::string("data:image/png;base64,AA==") }),
        ].to_json(),
      }),
    }),
  )
  assert_true(request_meta.client_info is Some({ icons: [_], .. }))
}

///|
test "deprecated and unknown client capabilities round trip" {
  let meta = try! @mcp.parse_request_meta(
    Json::object({
      "io.modelcontextprotocol/protocolVersion": Json::string(
        @mcp.latest_protocol_version,
      ),
      "io.modelcontextprotocol/clientCapabilities": Json::object({
        "roots": Json::object({ "listChanged": Json::boolean(true) }),
        "sampling": Json::object({}),
        "com.example/customCapability": Json::object({
          "enabled": Json::boolean(true),
        }),
      }),
    }),
  )
  guard meta.client_capabilities
    is {
      deprecated: Some({ roots: Some(Object(_)), sampling: Some(Object(_)) }),
      extra: { "com.example/customCapability": Object(_), .. },
      ..,
    } else {
    fail("expected wire-compatible capabilities")
  }
  guard meta.client_capabilities.to_json()
    is Object(
      {
        "roots": Object(_),
        "sampling": Object(_),
        "com.example/customCapability": Object(_),
        ..
      }
    ) else {
    fail("expected capabilities to round trip")
  }
}

///|
test "unknown remote errors retain code message and data" {
  let data = Json::object({ "retryAfterMs": Json::number(25.0) })
  let error = try! @mcp.McpError::from_rpc_parts(
    -32123,
    "extension failed",
    data~,
  )
  assert_true(
    error
    is RemoteError(
      code=-32123,
      message="extension failed",
      data=Some(Object({ "retryAfterMs": Number(25.0, ..), .. }))
    ),
  )
  guard error.to_json() is Object({ "data": round_tripped, .. }) else {
    fail("expected error data")
  }
  assert_eq(round_tripped, data)
}

///|
test "invalid resource parameters preserve the requested URI" {
  let error = try! @mcp.McpError::from_rpc_parts(
    -32602,
    "resource not found",
    data=Json::object({ "uri": Json::string("test://missing") }),
  )
  assert_eq(error.code(), -32602)
  assert_eq(
    error.data(),
    Some(Json::object({ "uri": Json::string("test://missing") })),
  )
}
