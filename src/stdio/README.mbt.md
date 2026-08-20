# shiguri-01/mcp/stdio

Native newline-delimited JSON-RPC stdio transport.

## Server

```moonbit nocheck
///|
async fn main {
  let server = builder.build()
  @stdio.serve(server)
}
```

## Client

```moonbit nocheck
///|
async fn main {
  @async.with_task_group(async fn(group) {
    let transport = try! @stdio.Transport(group, "path/to/server", args=[])
    let client = try! @client.Client(name="client", version="1.0.0", transport~)

    let res = client.call_tool(name="greet", arguments={ "name": "World" })
    transport.shutdown()
  })
}
```
