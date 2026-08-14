# Transport frames

`transport` is the I/O boundary for the MCP SDK. It deliberately does not
know JSON-RPC, MCP method names, or result types.

An adapter implements `FrameTransport::exchange` for one request/response
exchange. The opaque `OutboundFrame.body` is produced by the protocol layer;
the adapter may frame it as newline-delimited stdio, a Streamable HTTP POST,
or any application-specific protocol. `InboundFrame` carries status, headers,
and the opaque response body back to the protocol layer.

Long-lived Streamable HTTP SSE and stdio multiplexing use `FrameStream`, which
is separate from one-shot exchange. `TransportError` is intentionally distinct
from JSON-RPC errors and MCP `McpError` values.
