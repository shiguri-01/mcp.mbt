# shiguri-01/mcp/http

Native Streamable HTTP transport for `shiguri-01/mcp`, following the
[MCP 2026-07-28 transport specification](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports).

The transport carries the protocol version, client identity, and client
capabilities on every request. Applications expose typed async tools through a
transport-neutral `@mcp.Server`; clients start with `server/discover` and call
only features advertised by the server.

This revision is modern-only: it has no initialization handshake, transport
session IDs, GET stream endpoint, or DELETE session lifecycle. Every JSON-RPC
request is an independent POST.

The client provides discovery, tools, resources, prompts, completion, bounded
MRTR helpers, and an incremental `subscriptions/listen` SSE reader. The server
can opt into request-scoped progress SSE with
`ServerOptions(stream_responses=true)` and publish validated subscription
notifications through `on_subscription`.

Authorization is intentionally not approximated by a boolean callback. Put an
OAuth 2.1 / MCP Authorization-aware middleware in front of this adapter when
the optional Authorization specification is enabled.

```mbt check
///|
pub fn make_client() -> @http.Client {
  @http.Client("http://127.0.0.1:8080/mcp")
}

///|
pub fn make_options() -> @http.ServerOptions {
  @http.ServerOptions(endpoint_path="/mcp")
}
```

Run the complete server and discover/call client examples from the repository
root:

```bash
moon run --target native src/examples/http-server
moon run --target native src/examples/http-client
```
