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

Authorization scenarios use the HTTP client's authorization configuration.
The provider sends OAuth discovery, registration, and token requests, follows
the authorization endpoint's redirect without contacting the callback URI,
and permits insecure loopback URLs only because the conformance runner binds
its isolated servers to loopback. The authorization user-agent seam requires
the `curl` executable and reads its non-following HTTP response.

The frozen authorization suite exercises these contracts:

| Scenarios | Client contract |
|---|---|
| `auth/metadata-*`, `auth/basic-cimd` | RFC 9728/RFC 8414/OIDC discovery order and Client ID Metadata Documents |
| `auth/scope-*` | challenge scope precedence, scope union during step-up, and bounded retries |
| `auth/token-endpoint-auth-*` | selected token endpoint authentication and resource parameter consistency |
| `auth/pre-registration` | issuer-bound credentials from `MCP_CONFORMANCE_CONTEXT` without dynamic registration |
| `auth/resource-mismatch` | rejection of protected-resource metadata for another resource |
| `auth/offline-access-*` | refresh-token grant metadata and conditional `offline_access` scope |
| `auth/authorization-server-migration` | credentials are not reused after the resource changes authorization server |
| `auth/iss-*`, `auth/metadata-issuer-mismatch` | exact issuer validation in metadata and authorization responses |
