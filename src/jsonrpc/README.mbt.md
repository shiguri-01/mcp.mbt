# JSON-RPC 2.0 envelope

This package contains only JSON-RPC 2.0 wire values. It does not know MCP
methods or any transport. Decode a single object with `decode`; constructors
reject invalid envelope values. Method-specific params and results belong to
the MCP package, so this package does not expose an MCP-specific `validate`
helper.

`@json.FromJson` is reserved for structural JSON decoding and reports
`JsonDecodeError`. It is not overloaded with MCP/domain validation errors.
JSON-RPC batches are rejected because MCP 2026-07-28 exchanges one message at
a time.
