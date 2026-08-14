# MCP 2026-07-28 MoonBit API design

This document is the contract for the next implementation pass. It is
deliberately written in MCP terminology. It is not a history of the current
implementation and it does not describe compatibility aliases.

## Design rules

1. The names in the public API follow the MCP method and type names:
   `ServerDiscover`, `ToolsList`, `ToolsCall`, `ResourcesRead`,
   `PromptsGet`, `CompletionComplete`, `SubscriptionsListen`,
   `RequestMeta`, `ResultType`, `InputRequiredResult`, and `CachePolicy`.
2. A data record is a `pub struct` with readable fields. Its constructor is
   the only public creation path when an invariant must hold. There are no
   Java-style getters for fields.
3. Wire JSON is decoded once at the boundary. Application handlers receive
   typed values, never an unvalidated `Json` value for a typed operation.
4. `Json` remains available for extension methods and extension fields. It is
   not the normal API for core MCP methods.
5. `from_json` is reserved for the `@json.FromJson` protocol used by MoonBit.
   Named protocol decoders are `decode_*`; constructors never perform a second
   parse. `parse_*` is reserved for textual grammars such as URIs or headers.
6. Transport carries bytes/text, HTTP metadata, and stream lifetime. It does
   not know JSON-RPC, MCP method names, result types, or `_meta`.
7. JSON Schema is a separate subsystem with an explicit supported-dialect
   contract. It must not be mixed into MCP dispatch helpers.

## Public package shape

The root package exposes MCP domain types and typed operations. The following
packages are implementation boundaries:

```text
schema       JSON Schema documents, compilation, instance validation
jsonrpc      JSON-RPC 2.0 envelope and error codec
transport    byte/text exchange and stream lifetime only
mcp          MCP wire/domain types, typed server and client core
http         Streamable HTTP binding and HTTP authentication adapter
stdio        newline-delimited stdio binding
auth         OAuth policy and provider seam
```

`mcp` may depend on `jsonrpc`, `schema`, and `transport`; `transport` must not
depend on `mcp` or `jsonrpc`. `http` and `stdio` may depend on `mcp` and
`transport`, but must not define a second JSON-RPC envelope.

## Typed server API

The server registry is built through one constructor and is sealed before the
first dispatch. Registration names use MCP concepts directly:

```moonbit
let server = try! Server::new(
  implementation=Implementation::new(name="greeter", version="1.0.0"),
)
try! server.register_tool(
  Tool::new(name="greet", description="Greet a person", input_schema),
  async fn(context : RequestContext, input : GreetInput) {
    Complete(CallToolResult::text("Hello, \\{input.name}!"))
  },
)
```

There is one registration function per MCP feature (`register_tool`,
`register_resource`, `register_resource_template`, `register_prompt`, and
`register_completion`). A raw escape hatch is named `register_method` and is
explicitly documented as a wire-level API. `tool`, `tool_json`, and multiple
`simple_*` variants are not part of the public surface.

The server automatically implements `server/discover`, `tools/list`,
`tools/call`, `resources/list`, `resources/read`, `prompts/list`,
`prompts/get`, and `completion/complete` for registered features. It derives
capability presence from the registry and only advertises list-change,
subscription, and extension capabilities when explicitly enabled.

Handlers return `HandlerOutcome[T] = Complete(T) | InputRequired(...)`.
`resultType`, result metadata, cache fields, and server information are added
by the dispatcher, not by application handlers.

## Typed client API

The client has typed verbs matching MCP methods:

```moonbit
let client = try! Client::new(
  implementation=Implementation::new(name="example", version="1.0.0"),
  capabilities=ClientCapabilities::empty(),
)
let discovered = try! client.server_discover()
let tools = try! client.tools_list()
let result = try! client.tools_call(name="greet", arguments=input)
```

The default verbs return `DiscoverResult`, `ListToolsResult`,
`CallToolResult`, `ReadResourceResult`, `GetPromptResult`, and
`CompleteResult`. `request_raw` and `*_raw` are the only APIs that expose raw
JSON. MRTR retry is implemented by the typed verbs with a bounded policy and a
typed input callback.

## JSON Schema redesign

The current validator is too large and too ambitious for an implicit helper.
The replacement has three explicit layers:

### 1. Document model

`schema::Document` is an immutable, constructor-created JSON Schema document.
It preserves `$id`, `$ref`, `$defs`, `$dynamicAnchor`, `$dynamicRef`,
`$vocabulary`, and embedded resources without silently normalizing them.
`Document::new(value)` performs only document-shape checks and resource/index
construction. It never fetches a network reference.

### 2. Compilation

`Document::compile(options)` returns `CompiledSchema` or `SchemaError`.
Compilation resolves only references inside the supplied compound document,
uses RFC 3986 URI resolution and RFC 6901 JSON Pointer, and rejects an
unsupported dialect/vocabulary explicitly. The options contain resource and
evaluation limits; there is no global mutable resolver.

### 3. Instance validation

`CompiledSchema::validate(instance)` returns `ValidationResult`, not a
boolean and not an MCP error. The result contains assertion status and the
annotations required by `unevaluatedProperties` and `unevaluatedItems`.
MCP maps this result to protocol errors or tool execution errors at the
dispatcher boundary. Schema validation never raises `McpError` directly.

The first supported dialect is JSON Schema 2020-12 with a documented subset
of ECMA-262 regular expressions. Unsupported regex constructs are rejected at
compilation; they are never approximated. Full ECMA-262 compatibility is a
separate milestone, not an undocumented claim.

## Error and codec rules

- `JsonRpcError` represents JSON-RPC envelope errors.
- `McpError` represents MCP protocol errors (`-32020` through `-32022` and
  invalid params/method errors).
- `SchemaError` and `ValidationResult` remain in `schema`.
- `TransportError` represents I/O, framing, size, and stream errors.

The codec names are fixed: `decode_*` consumes a `Json` value, `encode_*`
creates a `Json` value, and `parse_*` handles text. No public `validate` helper
duplicates constructor or codec validation.

## Implementation order

1. Freeze this public contract and remove obsolete aliases/getters.
2. Rebuild `schema` as an independent document/compiler/validation package.
3. Rebuild JSON-RPC and MCP codecs around the canonical `jsonrpc` package.
4. Implement typed server/client core and use it from HTTP and stdio.
5. Add transport-specific conformance tests and typed quickstart tests.
6. Run all MCP 2026-07-28 conformance suites and publish only claims backed by
   those tests.
