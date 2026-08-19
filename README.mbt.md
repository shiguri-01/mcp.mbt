# shiguri-01/mcp

An ergonomic MoonBit SDK for the [Model Context Protocol (2026-07-28)](https://modelcontextprotocol.io/specification/2026-07-28).

## Server

Define typed inputs with `@schema.JsonSchema` and `@json.FromJson`, register them on `@server.ServerBuilder`, and serve over standard I/O or Streamable HTTP.

```moonbit
struct GreetInput {
  name : String
} derive(@json.FromJson, ToJson)

impl @schema.JsonSchema for GreetInput with fn json_schema() {
  @schema.Schema::object(
    properties={ "name": @schema.Schema::string(min_length=1) },
    required=["name"],
  )
}

async fn main {
  let builder = try! @server.ServerBuilder(name="greeter", version="1.0.0")
  try! builder.tool(name="greet", fn(_ctx, input : GreetInput) {
    @mcp.Complete(@mcp.CallToolResult::text("Hello, \{input.name}!"))
  })

  // Stdio transport
  @stdio.serve(builder.build())
}
```

## Client

Connect to a server and call tools, read resources, or fetch prompts:

```moonbit
async fn main {
  @async.with_task_group(async fn(group) {
    let transport = try! @stdio.Transport(group, "path/to/server")
    let client = try! @client.Client(name="client", version="1.0.0", transport~)

    match client.call_tool(name="greet", arguments={ "name": "MoonBit" }) {
      Complete(res) => println(res.content)
      InputRequired(pending) => ... // Handle multi-round interactive requests
      ExtensionResult(kind, val) => ...
    }

    transport.shutdown()
  })
}
```

## Packages

| Package | Description |
|---|---|
| [`shiguri-01/mcp`](./src) | Core protocol types, content models, and error definitions (`McpError`) |
| [`shiguri-01/mcp/server`](./src/server) | Typed server builder, dispatching, and session management |
| [`shiguri-01/mcp/client`](./src/client) | Client runtime, discovery, typed invocation, and MRTR resolution |
| [`shiguri-01/mcp/schema`](./src/schema) | JSON Schema (Draft 2020-12) builder, validator, and typed decoder |
| [`shiguri-01/mcp/stdio`](./src/stdio) | Stdio transport (server runner & subprocess client) |
| [`shiguri-01/mcp/http`](./src/http) | Streamable HTTP transport (SSE progress/subscriptions & OAuth 2.0) |
| [`shiguri-01/mcp/auth`](./src/auth) | Native MCP Authorization (RFC 9728, PKCE S256, token caching) |
| [`shiguri-01/mcp/jsonrpc`](./src/jsonrpc) | Low-level JSON-RPC 2.0 wire envelopes and parser |

## Examples

```bash
# Stdio Server & Client
moon build --target native src/examples/stdio-server
MCP_STDIO_SERVER="$PWD/_build/native/debug/build/examples/stdio-server/stdio-server" \
  moon run --target native src/examples/stdio-client

# HTTP Server & Client
moon run --target native src/examples/http-server
moon run --target native src/examples/http-client
```
