# MCP 2026-07-28 client conformance driver

This native executable is the client-under-test adapter for the frozen MCP
2026-07-28 conformance requirements. The runner supplies the scenario through
`MCP_CONFORMANCE_SCENARIO`, the protocol version through
`MCP_CONFORMANCE_PROTOCOL_VERSION`, optional scenario data through
`MCP_CONFORMANCE_CONTEXT`, and appends the scenario server URL as the final
command argument.

The driver exercises the public MoonBit MCP HTTP client API for tool calls,
per-request metadata and protocol-version negotiation, opaque MRTR
`requestState`, standard and schema-directed HTTP headers, invalid annotated
tool filtering, and non-dereferencing of network JSON Schema references.

Build it with:

```mbt nocheck
moon build --target native src/integration/conformance-client
```

Authorization scenarios require an `@auth`-enabled driver configuration and
are rejected explicitly by this non-authorization executable.
