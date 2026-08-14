# Transport frames

`transport` is the I/O boundary for the MCP SDK. It deliberately does not
know JSON-RPC, MCP method names, or result types.

An adapter implements `FrameTransport::exchange` for one request/response
exchange. The opaque body is produced by the protocol layer; the adapter may
frame it as a Streamable HTTP POST or any application-specific protocol.
`FrameResponse` carries the opaque response body and adapter-defined metadata
back to the protocol layer. HTTP status is just one possible metadata key, not
part of this package's contract.

Long-lived Streamable HTTP SSE and stdio multiplexing use `FrameStream`, which
is separate from one-shot exchange. `TransportError` is intentionally distinct
from JSON-RPC errors and MCP `McpError` values.
