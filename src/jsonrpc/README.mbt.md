# shiguri-01/mcp/jsonrpc

JSON-RPC 2.0 wire envelopes and parser.

## Usage

```moonbit nocheck
// Parse message
match try! @jsonrpc.decode(json) {
  Request(req) => ...
  Notification(notif) => ...
  Response(res) => ...
}

// Build response
let res = @jsonrpc.Response::Success(id~, result~)
```
