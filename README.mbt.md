# shiguri/mcp

MoonBit implementation of the core Model Context Protocol server surface.

This package currently focuses on the small, useful server MVP:

- MCP `initialize`
- `notifications/initialized`
- `tools/list`
- `tools/call`
- `resources/list`
- `resources/read`
- `prompts/list`
- `prompts/get`
- raw JSON tool handlers
- typed `FromJson` / `ToJson` tool handlers
- JSON-RPC 2.0 request/response envelope helpers
- native stdio server and client helpers

The public API intentionally keeps a raw `Json` escape hatch. MCP has open
extension points such as `_meta`, JSON Schema, experimental capabilities, and
structured content, so the low-level API accepts JSON directly. The high-level
tool API uses MoonBit's `FromJson` and `ToJson` traits for normal typed
handlers.

```mbt check
///|
test {
  let server = @mcp.Server(name="example", version="0.1.0")
  try! server.tool(name="hello", description="Return a greeting", fn(_) {
    @mcp.CallToolResult::text("Hello from MoonBit MCP")
  })
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

## Packages

- `shiguri/mcp` is the transport-neutral core package. It contains MCP data
  types, JSON-RPC helpers, schema builders, and the in-memory server/client
  dispatch API.
- `shiguri/mcp/stdio` is the native stdio transport package. It depends on
  `moonbitlang/async`, process pipes, and the native backend.
- `examples/stdio-server` and `examples/stdio-client` are the runnable examples.
  They exercise a real MCP stdio session instead of printing mock output.

## Server API

Use the API that matches the shape you want to return:

| Use case | API |
| --- | --- |
| Tool reads raw `Json?` and returns `CallToolResult` | `server.tool(...)` |
| Tool decodes typed input and returns `CallToolResult` | `server.typed_tool(...)` |
| Tool needs full MCP `Tool` and `CallToolResult` control | `server.raw_tool(...)` |
| Resource returns full `ReadResourceResult` | `server.resource(...)` |
| Resource needs a prebuilt `Resource` descriptor | `server.raw_resource(...)` |
| Prompt reads raw string arguments and returns `GetPromptResult` | `server.prompt(...)` |
| Prompt decodes typed arguments and returns `GetPromptResult` | `server.typed_prompt(...)` |
| Prompt needs raw JSON result control | `server.raw_prompt(...)` |

```mbt nocheck
struct HelloInput {
  name : String
} derive(FromJson)

try! server.typed_tool(
  name="hello",
  description="Return a greeting",
  input_schema=@mcp.object([
    @mcp.string_prop(name="name", description="Name to greet", required=true),
  ]),
  fn(input : HelloInput) {
    @mcp.CallToolResult::text("Hello, \{input.name}!")
  },
)

try! server.resource(
  uri="memory://status",
  name="status",
  description="Server status",
  fn(uri) {
    @mcp.ReadResourceResult::text(uri~, text="ready", mime_type="text/plain")
  },
)

struct SummarizeInput {
  topic : String
} derive(FromJson)

try! server.typed_prompt(
  name="summarize",
  arguments=[
    @mcp.PromptArgument(name="topic", required=true),
  ],
  fn(input : SummarizeInput) {
    @mcp.GetPromptResult::user("Summarize \{input.topic} in three bullets.")
  },
)
```

The `raw_*` methods are the low-level escape hatches. Normal server code should
start with `typed_tool`, `resource`, or `typed_prompt`.

## Examples

Run these from the repository root:

```bash
moon run --target native examples/stdio-server
moon run --target native examples/stdio-client
```

- `examples/stdio-server` is a real stdio MCP server package for native target.
- `examples/stdio-client` spawns that server over stdio and calls tools,
  resources, and prompts through the client transport.

`shiguri/mcp/stdio` depends on `moonbitlang/async` and is native-only. On
Windows, `moonbitlang/async` currently requires an MSVC native toolchain; MinGW
GCC is not enough.

The current transport support is stdio for native target. Streamable HTTP is not
implemented yet.
