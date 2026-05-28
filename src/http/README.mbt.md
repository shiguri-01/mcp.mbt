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

`serve` receives a factory instead of a shared server instance. Each HTTP
session owns its own transport-neutral `@mcp.Server`, because MCP lifecycle
state is per session.

```mbt check
///|
test {
  let client = @http.Client("http://127.0.0.1:8080/mcp")
  assert_true(client.session_id() is None)
  let options = @http.ServerOptions(endpoint_path="/mcp")
  assert_eq(options.endpoint_path, "/mcp")
}
```

Run the included example server and client from the repository root:

```bash
moon run --target native src/examples/http-server
moon run --target native src/examples/http-client
```
