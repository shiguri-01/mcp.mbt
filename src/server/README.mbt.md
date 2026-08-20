# shiguri-01/mcp/server

Typed Server implementation and dispatch runtime for `shiguri-01/mcp`.

## Defining Tools, Resources, and Prompts

```moonbit nocheck
///|
struct GreetInput {
  name : String
} derive(@json.FromJson, ToJson)

///|
impl @schema.JsonSchema for GreetInput with fn json_schema() {
  @schema.Schema::object(
    properties={ "name": @schema.Schema::string(min_length=1) },
    required=["name"],
  )
}

///|
async fn main {
  let builder = try! @server.ServerBuilder(name="my-server", version="1.0.0")

  // Tool
  try! builder.tool(name="greet", description="Greets someone", fn(
    _ctx,
    input : GreetInput,
  ) {
    @mcp.Complete(@mcp.CallToolResult::text("Hello, \{input.name}!"))
  })

  // Resource
  try! builder.resource(uri="memo://today", name="Today's Memo", fn(
    _ctx,
    _uri,
  ) {
    @mcp.Complete(
      @mcp.ReadResourceResult::text(uri="memo://today", text="Hello!"),
    )
  })

  // Prompt
  try! builder.prompt(
    name="review",
    arguments=[@mcp.PromptArgument::PromptArgument(name="code", required=true)],
    fn(_ctx, args) {
      let code = args.get("code").default("")
      @mcp.Complete(@mcp.GetPromptResult::user("Review this code:\n\{code}"))
    },
  )

  let server = builder.build()

  // Dispatch JSON-RPC message directly or pass to a transport
  let res = server.handle_jsonrpc(request_json)
}
```
