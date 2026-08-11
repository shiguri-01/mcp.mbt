# MCP 2026-07-28 server conformance fixture

This executable is a deterministic application built only from the public
MoonBit MCP SDK API. It represents the server behaviors exercised by the
frozen 2026-07-28 conformance requirements: discovery, stateless request
metadata, tools and content variants, resources and templates, prompts,
completion, progress delivery, capability enforcement, and multi-round input.

Run it on the native backend:

```mbt nocheck
moon run --target native src/integration/conformance-server
```

Then run the official frozen server suite against
`http://127.0.0.1:8080/mcp`. Fixture names and payloads are protocol contracts;
they are not a record of implementation history.

The fixture deliberately does not advertise list-change notifications. The
stateless scenario therefore treats those checks as not applicable. The
built-in resource router returns `-32602` for an unknown URI and includes the
rejected URI in `error.data.uri`.
