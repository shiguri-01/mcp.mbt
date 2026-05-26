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
  let server = @mcp.Server::new(name="example", version="0.1.0")
  try! server.tool_text(
    name="hello",
    description="Return a greeting",
    input_schema=@mcp.empty_object_schema(),
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

## Server API

Use high-level helpers for normal server code:

```mbt nocheck
try! server.tool_text(
  name="hello",
  description="Return a greeting",
  input_schema=@mcp.object_schema(
    properties={
      "name": @mcp.string_property_schema(description="Name to greet"),
    },
    required=["name"],
  ),
  fn(args) raise @mcp.McpError {
    match args {
      Some(Object({ "name": String(name), .. })) => "Hello, \{name}!"
      _ => raise @mcp.InvalidParams("name must be a string")
    }
  },
)

try! server.resource_text(
  uri="memory://status",
  name="status",
  description="Server status",
  fn(_) { "ready" },
)

try! server.prompt_text(
  name="summarize",
  arguments=[
    @mcp.PromptArgument::{
      name: "topic",
      title: None,
      description: None,
      required: true,
    },
  ],
  fn(args) raise @mcp.McpError {
    match args.get("topic") {
      Some(topic) => "Summarize \{topic} in three bullets."
      None => raise @mcp.InvalidParams("topic is required")
    }
  },
)
```

Drop down to `add_tool_raw`, `add_resource`, and `add_prompt_raw` when the MCP
payload shape needs to stay fully dynamic.

## Examples

Run these from the repository root:

```bash
moon run examples/raw-tool
moon run examples/typed-tool
moon run examples/jsonrpc
moon run --target native examples/stdio-server
moon run --target native examples/stdio-client
```

- `examples/raw-tool` uses `Json` pattern matching directly.
- `examples/typed-tool` uses `FromJson` and `ToJson`.
- `examples/jsonrpc` sends MCP JSON-RPC messages through `handle_jsonrpc`.
- `examples/stdio-server` is a real stdio MCP server package for native target.
- `examples/stdio-client` spawns the stdio server and calls tools, resources, and prompts.

`shiguri/mcp/stdio` depends on `moonbitlang/async` and is native-only. On
Windows, `moonbitlang/async` currently requires an MSVC native toolchain; MinGW
GCC is not enough.

The current transport support is stdio for native target. Streamable HTTP is not
implemented yet.
