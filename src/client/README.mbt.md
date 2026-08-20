# shiguri-01/mcp/client

Typed Client implementation for `shiguri-01/mcp`.

## Usage

```moonbit nocheck
///|
async fn main {
  let client = try! @client.Client(
    name="my-client",
    version="1.0.0",
    transport~,
  )

  // Discover capabilities
  let info = client.discover()

  // Call tool
  let outcome = client.call_tool(name="greet", arguments={ "name": "Alice" })

  // Read resource
  let resource = client.read_resource(uri="memo://today")

  // Fetch prompt
  let prompt = client.get_prompt(name="review", arguments={
    "code": "fn main {}",
  })

  // Listen to notifications (resources/tools list changes)
  client.listen(
    notifications=@mcp.SubscriptionFilter(
      tools_list_changed=true,
      resources_list_changed=true,
    ),
    on_notification=fn(event) { ... },
  )
}
```
