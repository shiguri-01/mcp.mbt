# shiguri-01/mcp

A MoonBit library for building Model Context Protocol servers and clients.

This module targets the
[MCP `2025-11-25` specification](https://modelcontextprotocol.io/specification/2025-11-25)
and provides:

- typed server APIs for tools, resources, prompts, completion, logging, and resource subscriptions
- JSON-RPC request builders for MCP clients
- typed content blocks, capabilities, lifecycle state, and MCP errors
- raw `Json` escape hatches for extension fields and low-level handlers
- native stdio and Streamable HTTP transports

## Install

```bash
moon add shiguri-01/mcp
```

## Quick Start

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
async fn main {
  let server = @mcp.Server(name="example", version="0.1.0")
  try! server.tool(name="hello", description="Return a greeting", fn(
    input : HelloInput,
  ) {
    @mcp.CallToolResult::text("Hello, \{input.name}!")
  })
  @mcp_stdio.serve(server)
}
```

## Packages

- `shiguri-01/mcp`: transport-neutral MCP types, server dispatch, client
  request builders, content blocks, capabilities, lifecycle, and errors.
- `shiguri-01/mcp/schema`: small JSON Schema builders for typed tool inputs.
- `shiguri-01/mcp/stdio`: stdio server and client helpers for MoonBit's
  native backend.
- `shiguri-01/mcp/http`: Streamable HTTP server and client helpers for MoonBit's native backend.

## Examples

```bash
moon run --target native src/examples/stdio-server
moon run --target native src/examples/stdio-client
moon run --target native src/examples/http-server
moon run --target native src/examples/http-client
```
