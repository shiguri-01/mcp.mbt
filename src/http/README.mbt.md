# shiguri-01/mcp/http

Native Streamable HTTP transport for `shiguri-01/mcp`.

This package implements the MCP Streamable HTTP endpoint defined by the
2025-11-25 transport specification:
<https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>

The current implementation supports POST-based JSON-RPC exchange, session
management with `MCP-Session-Id`, `DELETE` session termination, Origin checks,
and protocol/header validation. Standalone GET SSE streams intentionally return
`405 Method Not Allowed`; the specification permits this for servers that do not
offer an SSE stream at the MCP endpoint.

```mbt nocheck
///|
async fn main {
  let http_server = @async_http.Server(@socket.Addr::parse("127.0.0.1:8080"))
  @http.serve(http_server, fn() { @mcp.Server(name="example", version="0.1.0") })
}
```
