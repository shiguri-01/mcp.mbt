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
let server = try! @mcp.Server(
  name="greeter", version="1.0.0",
)
try! server.tool(
  name="greet",
  description="Greet a person",
  fn(context : RequestContext, input : GreetInput) {
    Complete(CallToolResult::text("Hello, \\{input.name}!"))
  },
)
```

There is one high-level registration method per MCP feature (`tool`,
`resource`, `resource_template`, `prompt`, and `completion`). Raw JSON tools
use the explicitly named `tool_raw` escape hatch; `on` is the wire-level
custom-method escape hatch. There are no `simple_*` convenience variants.

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
let client = try! @mcp.Client(
  name="example", version="1.0.0",
  capabilities=ClientCapabilities::empty(),
)
let discover_request = try! client.discover_request()
let tools_request = try! client.list_tools_request()
let call_request = try! client.call_tool_request(name="greet", arguments=input)
```

The root client is the transport-independent request builder and decoder.
The HTTP and stdio bindings provide the asynchronous typed verbs `discover`,
`list_tools`, `call_tool`, `read_resource`, `get_prompt`, and `complete`, which
return `DiscoverResult`, `ListToolsResult`, `CallToolResult`,
`ReadResourceResult`, `GetPromptResult`, and `CompleteResult`. `request_raw` and
the transport-specific `*_raw` methods are the explicit escape hatches for
extension methods. MRTR retry is exposed by the transport bindings with a
bounded policy and typed input callback.

## JSON Schema

The current validator is too large and too ambitious for an implicit helper.
The replacement has three explicit layers:

The public schema package has two input paths. A `JsonSchema` implementation
describes a MoonBit type and is the normal path for MCP tool input schemas.
Applications can also construct a schema programmatically with typed schema
constructors (`Schema::string`, `Schema::object`, `Schema::array`,
`Schema::one_of`, and so on). A raw `Json` document is retained as an explicit
interop escape hatch, not as the only way to create a schema. Both paths
produce the same `Document` model.

`JsonSchema` returns the typed `Schema` AST, not a hand-built `Json` value.
`FromJson`/`ToJson` and `JsonSchema` are separate traits: a type can be decoded
without being able to publish a schema, and a schema can be authored without a
generated decoder. MCP's typed tool API requires both traits at registration
time.

### 1. Typed schema and document model

`schema::Schema` is a typed schema AST for the common 2020-12 vocabulary.
Boolean schemas are represented directly. Each modeled keyword has a
constructor that validates its local invariant. `Schema::raw` is the explicit
escape hatch for a valid keyword not yet modeled by the AST, and
`Schema::to_json` is the only conversion used to create a document.

`schema::Document` is a constructor-created JSON Schema document. It preserves
the input JSON without silently normalizing it. `@schema.Document(value)`
performs document-shape checks and never fetches a network reference.

### 2. Compilation

`Document::compile(options)` returns `CompiledSchema` or `SchemaError`.
Compilation resolves local references inside the supplied document using JSON
Pointer and rejects network references by default. Unsupported dialects are
reported explicitly. The options contain depth and node limits; there is no
global mutable resolver.

### 3. Instance validation

`CompiledSchema::validate(instance)` returns `ValidationResult`, not a
boolean and not an MCP error. The result contains assertion status and the
annotations required by `unevaluatedProperties` and `unevaluatedItems`.
MCP maps this result to protocol errors or tool execution errors at the
dispatcher boundary. Schema validation never raises `McpError` directly.

The first supported dialect is JSON Schema 2020-12 with the implemented
assertion subset documented by the package tests. Unsupported keywords and
regex constructs are not silently approximated; full vocabulary and ECMA-262
compatibility remain separate milestones.

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
