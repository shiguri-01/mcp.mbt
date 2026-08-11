# shiguri-01/mcp/stdio

Native newline-delimited JSON-RPC transport for `shiguri-01/mcp`.

Server programs register typed async handlers and pass the transport-neutral
server to `serve`. Client programs can spawn a server process, send
`server/discover`, and then call its advertised tools.

The client-facing verbs return the canonical result types from
`shiguri-01/mcp`; wire JSON remains available through the corresponding
`*_raw` verbs and the general `request` method.

```mbt nocheck
let listed = client.list_resources()
for resource in listed.resources {
  println(resource.uri)
}
match client.read_resource(uri="file:///guide.txt") {
  Complete(result) => println(result.contents.length().to_string())
  InputRequired(pending) => handle_input(pending)
  ExtensionResult(kind, value) => handle_extension(kind, value)
}
```

```mbt nocheck
///|
struct GreetInput {
  name : String
} derive(FromJson)

///|
impl @schema.JsonSchema for GreetInput with fn json_schema() {
  @schema.schema([@schema.string(name="name", required=true)])
}

///|
async fn main {
  let server = try! @mcp.Server(name="greeter", version="1.0.0")
  try! server.simple_tool(name="greet", (input : GreetInput) => {
    @mcp.CallToolResult::text("Hello, \{input.name}!")
  })
  @mcp_stdio.serve(server)
}
```

Build the server before running the client so the client process can launch it
directly (without nesting another `moon` build):

```bash
moon build --target native src/examples/stdio-server
MCP_STDIO_SERVER="$PWD/_build/native/debug/build/examples/stdio-server/stdio-server" \
  moon run --target native src/examples/stdio-client
```

On Windows, `moonbitlang/async` requires an MSVC native toolchain.
