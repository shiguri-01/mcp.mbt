# shiguri-01/mcp/http

Native Streamable HTTP transport for `shiguri-01/mcp`, following the
[MCP 2026-07-28 transport specification](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports).

The transport carries the protocol version, client identity, and client
capabilities on every request. Applications expose typed async tools through a
transport-neutral `@mcp.Server`; clients start with `server/discover` and call
only features advertised by the server. Clients may list supported protocol
versions in preference order; an `UnsupportedProtocolVersion` response is
retried once with the first mutually supported version and a fresh JSON-RPC ID.

The transport contract is modern-only: it has no initialization handshake,
transport session IDs, GET stream endpoint, or DELETE session lifecycle. Every
JSON-RPC request is an independent POST.

The client provides discovery, tools, resources, prompts, completion, bounded
MRTR helpers, and an incremental `subscriptions/listen` SSE reader. The server
can opt into request-scoped progress SSE with
`ServerOptions(stream_responses=true)` and publish validated subscription
notifications through `on_subscription`. Client notifications are sent with
`Client::notify` and require the specified HTTP 202 response with an empty
body.

Request bodies and retained client response bodies are limited to 4 MiB by
default. Configure `ServerOptions(max_request_body_bytes=...)` and
`Client(max_response_body_bytes=...)` for applications with a different size
budget. SSE remains incremental and may run indefinitely; each retained event
is limited to 1 MiB by default and is configured with
`Client(max_sse_event_bytes=...)`. Limits count UTF-8 octets, not MoonBit string
code units. An oversized server request receives HTTP 413, and an oversized
client response raises `InvalidRequest` before JSON parsing.

Normal client verbs decode complete responses into the canonical domain types
from `shiguri-01/mcp`. For example, `list_tools` returns `ListToolsResult` and
`call_tool` returns `HandlerOutcome[CallToolResult]`. Use `list_tools_raw`,
`call_tool_raw`, or the general `request` method only when an extension needs
access to fields outside the core result model.

```mbt nocheck

let listed = client.list_tools()
for tool in listed.tools {
  println(tool.name)
}
match client.call_tool(name="greet", arguments={ "name": "MoonBit" }) {
  Complete(result) => println(result.content.length().to_string())
  InputRequired(pending) => handle_input(pending)
  ExtensionResult(kind, value) => handle_extension(kind, value)
}
```

Authorization is optional and configured with `AuthorizationOptions`. When it
is enabled, every request path—including notifications and subscription
streams—handles Bearer challenges with bounded retries. The client discovers
Protected Resource and Authorization Server metadata, selects pre-registration,
Client ID Metadata Documents, or Dynamic Client Registration, runs PKCE S256,
and stores credentials by issuer and tokens by issuer plus resource. An
`insufficient_scope` challenge preserves prior scopes while adding the required
scope; an `invalid_token` challenge uses a bound refresh token before reopening
the authorization interaction.

A 401 response may omit `WWW-Authenticate`; discovery then starts at the RFC
9728 well-known locations. A 403 response triggers authorization only for a
Bearer `insufficient_scope` challenge, so unrelated authorization failures are
returned unchanged.

`@auth.AuthorizationProvider` is the host boundary for authorization HTTP,
opening the authorization URL, cryptographic entropy, and destination policy.
Its built-in check requires HTTPS and rejects reserved literal addresses.
Native conformance and local development can explicitly set
`allow_insecure_loopback=true`. A concrete provider must validate resolved IP
addresses and every redirect hop through `validate_destination`; the built-in
string and literal checks alone are not a complete public-network policy.

The built-in server does not validate access tokens. Deployments that require
authorization must authenticate before calling the adapter (for example in a
reverse proxy or an enclosing HTTP service), reject unauthorized requests
there, and forward only trusted identity metadata. The adapter's raw header
transport metadata is not an authenticated principal.

Bearer access tokens are attached only through the `Authorization` header of
the configured MCP resource endpoint. They are never placed in MCP request
bodies, endpoint queries, discovery URLs, or authorization URL queries.
`AuthorizationOptions(resource_uri=...)` preserves an explicitly significant
resource identifier, including a trailing slash, across metadata validation,
token audience parameters, and cache keys. Without it, the endpoint-derived
canonical resource identifier is used.

JSON metadata and token responses must declare `application/json` (parameters
and header-name casing are accepted). A successful body with another media type
is rejected before parsing.

The conformance-client integration supplies:

- `send_request`: sends `@auth.HttpRequest` and returns raw status, headers, and
  body as `@auth.HttpResponse`;
- `open_authorization_url`: completes user-agent interaction and returns the
  complete callback URI;
- `random_bytes`: cryptographically secure entropy;
- either issuer-keyed `pre_registered` credentials, a
  `client_id_metadata_url`, or a server supporting dynamic registration.

```mbt check
///|
pub fn make_client() -> @http.Client {
  try! @http.Client("http://127.0.0.1:8080/mcp")
}

///|
pub fn make_options() -> @http.ServerOptions {
  try! @http.ServerOptions(endpoint_path="/mcp")
}
```

Run the complete server and discover/call client examples from the repository
root:

```bash
moon run --target native src/examples/http-server
moon run --target native src/examples/http-client
```
