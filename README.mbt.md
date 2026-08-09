# shiguri-01/mcp

An ergonomic MoonBit SDK for the
[MCP 2026-07-28 specification](https://modelcontextprotocol.io/specification/2026-07-28).
It provides typed async server handlers, request-scoped metadata, multi-round
trip results, modern discovery, and native stdio and Streamable HTTP transports.

## Install

```bash
moon add shiguri-01/mcp
```

## Quick start

Define a typed async tool. `JsonSchema` advertises its arguments and `FromJson`
decodes each call before your handler runs.

```mbt check
///|
struct GreetInput {
  name : String
} derive(FromJson)

///|
impl @schema.JsonSchema for GreetInput with fn json_schema() {
  @schema.schema([@schema.string(name="name", required=true)])
}

///|
async test "discover and call a typed tool" {
  let server = try! @mcp.Server(name="greeter", version="1.0.0")
  try! server.simple_tool(
    name="greet",
    description="Greet someone by name",
    (input : GreetInput) => {
      @mcp.CallToolResult::text("Hello, \{input.name}!")
    },
  )

  let client = @mcp.Client(name="example-client", version="1.0.0")
  let discover_response = server.handle_jsonrpc(client.discover_request())
  guard discover_response is Some(discover_response) else {
    fail("server/discover returned no response")
  }
  let discovered = try! client.decode_discover(discover_response)
  assert_true(discovered.supported_versions.length() > 0)

  let call_response = server.handle_jsonrpc(
    try! client.call_tool_request(
      name="greet",
      arguments=Json::object({ "name": Json::string("MoonBit") }),
    ),
  )
  guard call_response is Some(call_response) else {
    fail("tools/call returned no response")
  }
  guard (try! client.decode_response(call_response))
    is @mcp.HandlerOutcome::Complete(result) else {
    fail("tool requested more input")
  }
  guard result
    is Object({ "content": Array([Object({ "text": String(greeting), .. })]), .. }) else {
    fail("expected text tool result")
  }
  assert_eq(greeting, "Hello, MoonBit!")
}
```

For a standalone native server, register the same tool and pass the server to
`@mcp_stdio.serve`. See `src/examples/stdio-server` for the complete program.

Tool schemas are compiled when registered. Calls are checked against
`inputSchema` before the handler runs, and successful structured results are
checked against `outputSchema`; remote `$ref` fetching is deliberately disabled.
Resource templates require a handler and expose captured simple `{variable}`
expressions, so every advertised template is readable.

## Packages

- `shiguri-01/mcp`: protocol types, typed server dispatch, modern client
  request builders, discovery, and response decoding.
- `shiguri-01/mcp/schema`: JSON Schema builders for typed tool inputs.
- `shiguri-01/mcp/stdio`: native newline-delimited JSON-RPC transport.
- `shiguri-01/mcp/http`: native Streamable HTTP transport.

## Migrating from 0.1

Version 0.2 is intentionally source- and wire-incompatible with the old
connection-oriented API. Remove `initialize`, `initialized`, `ping`, session
stores and IDs, `logging/setLevel`, and resource subscribe/unsubscribe calls.
Construct `Client` with its identity and capabilities once; the SDK copies
them into every request. Register async handlers on a stateless `Server`, use
`server/discover` when capability discovery is useful, and use
`subscriptions/listen` or `InputRequiredResult` for streaming and MRTR flows.

See [`docs/design-2026-07-28.md`](docs/design-2026-07-28.md) for the design and
the complete list of deliberate breaking changes.

## Examples

```bash
moon run --target native src/examples/stdio-server
moon run --target native src/examples/stdio-client
moon run --target native src/examples/http-server
moon run --target native src/examples/http-client
```
