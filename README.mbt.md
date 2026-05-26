# shiguri/mcp

MoonBit implementation of the core Model Context Protocol server surface.

This package currently focuses on the small, useful server MVP:

- MCP `initialize`
- `notifications/initialized`
- `tools/list`
- `tools/call`
- raw JSON tool handlers
- typed `FromJson` / `ToJson` tool handlers
- JSON-RPC 2.0 request/response envelope helpers

The public API intentionally keeps a raw `Json` escape hatch. MCP has open
extension points such as `_meta`, JSON Schema, experimental capabilities, and
structured content, so the low-level API accepts JSON directly. The high-level
tool API uses MoonBit's `FromJson` and `ToJson` traits for normal typed
handlers.

```mbt check
///|
test {
  let server = @mcp.Server::new(name="example", version="0.1.0")
  try! server.add_text_tool(
    @mcp.Tool::new(
      name="hello",
      description="Return a greeting",
      input_schema=@mcp.empty_object_schema(),
    ),
    fn(_) { "Hello from MoonBit MCP" },
  )
  let result = try! server.handle("tools/list", None)
  guard result is Some(Object(fields)) else {
    fail("expected tools/list result")
  }
  guard fields["tools"] is Array([Object(tool)]) else {
    fail("expected one tool")
  }
  assert_true(tool["name"] == Json::string("hello"))
}
```

## Design

Protocol errors are represented with MoonBit checked errors:

```mbt nocheck
fn handler(input : Input) -> Output raise @mcp.McpError
```

Use `Result` only when an error needs to be stored as a value. Handler APIs use
`T raise E`.

JSON Schema is represented as `Json` for now. Validation can be layered on later
without changing the core server API.

## Examples

Run these from the repository root:

```bash
moon run examples/raw-tool
moon run examples/typed-tool
moon run examples/jsonrpc
```

- `examples/raw-tool` uses `Json` pattern matching directly.
- `examples/typed-tool` uses `FromJson` and `ToJson`.
- `examples/jsonrpc` sends MCP JSON-RPC messages through `handle_jsonrpc`.
