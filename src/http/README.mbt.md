# shiguri-01/mcp/http

Native Streamable HTTP transport with SSE streaming and OAuth 2.0.

## Server

```moonbit nocheck
///|
async fn main {
  let server = builder.build()
  let http_server = try! @async_http.Server::new(port=8080)
  let options = try! @http.ServerOptions(
    endpoint_path="/mcp",
    stream_responses=true,
  )

  @http.serve(http_server, server, options=Some(options))
}
```

## Client

```moonbit nocheck
///|
async fn main {
  let transport = try! @http.Transport("http://127.0.0.1:8080/mcp")
  let client = try! @client.Client(name="client", version="1.0.0", transport~)

  let outcome = client.call_tool(name="greet", arguments={ "name": "World" })
}
```
