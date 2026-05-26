# shiguri/mcp/stdio

Native stdio transport for `shiguri/mcp`.

Use this package when the process should speak MCP over stdin/stdout. Server
programs call `serve(server)`. Client-side integration tests and local tools can
use `Client::spawn(...)` to launch a stdio server and issue JSON-RPC requests.

This package is intentionally separate from `shiguri/mcp` because it depends on
`moonbitlang/async`, process pipes, and the native backend.

```mbt nocheck
///|
async fn main {
  let server = @mcp.Server(name="example", version="0.1.0")
  try! server.tool(name="hello", fn(_) {
    @mcp.CallToolResult::text("Hello from MoonBit MCP")
  })
  @mcp_stdio.serve(server)
}
```

On Windows, `moonbitlang/async` currently requires an MSVC native toolchain.
