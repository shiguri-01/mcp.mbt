# shiguri-01/mcp

MoonBit implementation of the Model Context Protocol server and client surface.

The core package is transport-neutral and targets MCP `2025-11-25`:

- MCP `initialize`
- `notifications/initialized`
- `tools/list`
- `tools/call`
- `resources/list`
- `resources/read`
- `resources/templates/list`
- `prompts/list`
- `prompts/get`
- `completion/complete`
- `logging/setLevel`
- `ping`
- cancellation, progress, list-changed, resource-updated, and logging
  notification builders
- cursor pagination for list endpoints
- `FromJson` / `ToJson` tool and prompt handlers
- raw JSON escape hatches
- JSON-RPC 2.0 request/response envelope helpers
- native stdio server and client helpers

The public API intentionally keeps a raw `Json` escape hatch. MCP has open
extension points such as `_meta`, JSON Schema, experimental capabilities, and
structured content, so the low-level API accepts JSON directly. The high-level
tool API uses MoonBit's `FromJson` and `ToJson` traits for normal typed
handlers.

```mbt check
///|
struct HelloInput {
  name : String
} derive(FromJson)

///|
impl @schema.JsonSchema for HelloInput with fn json_schema() {
  @schema.schema([@schema.string(name="name", required=true)])
}

///|
test {
  let server = @mcp.Server(name="example", version="0.1.0")
  try! server.tool(name="hello", description="Return a greeting", fn(
    input : HelloInput,
  ) {
    @mcp.CallToolResult::text("Hello, \{input.name}!")
  })
  assert_true(server.is_initialized() == false)
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

- `shiguri-01/mcp` is the transport-neutral core package. It contains MCP data
  types, request builders, and the in-memory server dispatch API. JSON-RPC 2.0
  envelope handling is delegated to `shiguri-01/jsonrpc`.
- `shiguri-01/mcp/schema` contains the JSON Schema trait and small builders used by
  typed tool inputs.
- `shiguri-01/mcp/stdio` is the native stdio transport package. It depends on
  `moonbitlang/async`, process pipes, and the native backend.
- `shiguri-01/mcp/examples/stdio-server` and
  `shiguri-01/mcp/examples/stdio-client` are runnable examples. They exercise a
  real MCP stdio session instead of printing mock output.

## Server API

Use the API that matches the shape you want to return:

| Use case | API |
| --- | --- |
| Tool decodes typed input and returns `CallToolResult` | `server.tool(...)` |
| Tool reads raw `Json?` and returns `CallToolResult` | `server.json_tool(...)` |
| Resource returns full `ReadResourceResult` | `server.resource(...)` |
| Resource template is discoverable | `server.resource_template(...)` |
| Prompt decodes typed arguments and returns `GetPromptResult` | `server.prompt(...)` |
| Prompt reads raw string arguments and returns `GetPromptResult` | `server.string_prompt(...)` |
| Completion returns argument suggestions | `server.completion(...)` |

```mbt nocheck
struct HelloInput {
  name : String
} derive(FromJson)

impl @schema.JsonSchema for HelloInput with fn json_schema() {
  @schema.schema([
    @schema.string(name="name", description="Name to greet", required=true),
  ])
}

try! server.tool(
  name="hello",
  description="Return a greeting",
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

try! server.resource_template(
  uri_template="memory://notes/{name}",
  name="note",
  description="Named note resource",
  mime_type="text/plain",
)

struct SummarizeInput {
  topic : String
} derive(FromJson)

impl @mcp.PromptArguments for SummarizeInput with fn prompt_arguments() {
  [@mcp.PromptArgument(name="topic", required=true)]
}

try! server.prompt(
  name="summarize",
  fn(input : SummarizeInput) {
    @mcp.GetPromptResult::user("Summarize \{input.topic} in three bullets.")
  },
)

try! server.completion(reference=@mcp.PromptRef(name="summarize"), fn(
  request,
) raise @mcp.McpError {
  if request.argument_name == "topic" && request.argument_value == "M" {
    @mcp.CompleteResult(values=["MCP", "MoonBit"], total=2)
  } else {
    @mcp.CompleteResult(values=[])
  }
})
```

The `json_tool` and `string_prompt` methods are escape hatches. Normal server
code should start with `tool`, `resource`, or `prompt`.

`handle_jsonrpc` is a lower-level dispatch hook for transports and tests.
Application code should normally talk through a transport such as
`shiguri-01/mcp/stdio` instead of spelling MCP method names as strings.

## Lifecycle

The server follows the MCP lifecycle described in the official
[`2025-11-25` lifecycle specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle):

1. the client sends `initialize` with `protocolVersion`, `capabilities`, and
   `clientInfo`
2. the server responds with the negotiated protocol version, server
   capabilities, and `serverInfo`
3. the client sends `notifications/initialized`
4. normal requests such as `tools/list`, `resources/read`, and `prompts/get`
   are accepted

Before `initialize`, only `ping` and `initialize` are accepted. After
`initialize` and before `notifications/initialized`, only `ping` and
`notifications/initialized` are accepted. The server stores the negotiated
protocol version, client capabilities, and client implementation metadata for
the active session.

## Examples

Run these from the repository root:

```bash
moon run --target native src/examples/stdio-server
moon run --target native src/examples/stdio-client
```

- `src/examples/stdio-server` is a real stdio MCP server package for native target.
- `src/examples/stdio-client` spawns that server over stdio and calls tools,
  resources, and prompts through the client transport.

`shiguri-01/mcp/stdio` depends on `moonbitlang/async` and is native-only. On
Windows, `moonbitlang/async` currently requires an MSVC native toolchain; MinGW
GCC is not enough.

The current transport support is stdio for native target. Streamable HTTP is the
next transport package to add on top of the same core request/dispatch surface.
