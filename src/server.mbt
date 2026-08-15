///|
type ToolHandler = async (RequestContext, Json) -> HandlerOutcome[
  CallToolResult,
] raise McpError

///|
type ResourceHandler = async (RequestContext, String) -> HandlerOutcome[
  ReadResourceResult,
] raise McpError

///|
type PromptHandler = async (RequestContext, Map[String, String]) -> HandlerOutcome[
  GetPromptResult,
] raise McpError

///|
type CompletionHandler = async (RequestContext, CompletionRequest) -> CompleteResult raise McpError

///|
type RawHandler = async (RequestContext, Json) -> HandlerOutcome[Json] raise McpError

///|
struct RegisteredTool {
  tool : Tool
  handler : ToolHandler
  input_validator : @schema.CompiledSchema
  output_validator : @schema.CompiledSchema?
}

///|
fn compile_tool_schema(value : Json) -> @schema.CompiledSchema raise McpError {
  let document = @schema.Document(value) catch {
    _ => raise InvalidParams("invalid JSON Schema document")
  }
  document.compile() catch {
    _ => raise InvalidParams("invalid JSON Schema document")
  }
}

///|
fn schema_validation_error(
  validator : @schema.CompiledSchema,
  value : Json,
) -> String? {
  let result = validator.validate(value)
  if result.valid {
    None
  } else {
    Some(result.errors.to_json().stringify())
  }
}

///|
struct RegisteredResource {
  resource : Resource
  handler : ResourceHandler
}

///|
struct RegisteredResourceTemplate {
  template : ResourceTemplate
  matcher : Regex
  variables : Array[String]
  handler : async (RequestContext, String, Map[String, String]) -> HandlerOutcome[
    ReadResourceResult,
  ] raise McpError
}

///|

///|

///|
let template_var_segment_regex : Regex = re"[^/?#]+"

///|
let template_placeholder_regex : Regex = re"[{]([a-zA-Z0-9_]+)[}]"

///|
fn compile_resource_template(
  template : String,
) -> (Regex, Array[String]) raise McpError {
  let remaining = template_placeholder_regex.replace_by(template, _ => "")
  if remaining.contains("{") || remaining.contains("}") {
    raise InvalidParams(
      "invalid syntax or unclosed brace in template: \{template}",
    )
  }
  let literals = template_placeholder_regex.split(template).to_array()
  let matches = template_placeholder_regex.find(template).to_array()
  let variables : Array[String] = []
  let mut matcher = Regex::string(literals[0].to_owned())
  for i, m in matches {
    guard m.group(1) is Some(var_view) else { continue }
    let var_name = var_view.to_owned()
    if variables.contains(var_name) {
      raise InvalidParams(
        "resource template variable '\{var_name}' must be unique",
      )
    }
    variables.push(var_name)
    matcher = matcher + template_var_segment_regex.capture(var_name)
    let next_literal = literals[i + 1].to_owned()
    if !next_literal.is_empty() {
      matcher = matcher + Regex::string(next_literal)
    }
  }
  (matcher, variables)
}

///|
fn RegisteredResourceTemplate::captures(
  self : RegisteredResourceTemplate,
  uri : String,
) -> Map[String, String]? {
  guard self.matcher.execute(uri) is Some(found) else { return None }
  if !found.before().is_empty() || !found.after().is_empty() {
    return None
  }
  let captures : Map[String, String] = Map([])
  for variable in self.variables {
    guard found.named_group(variable) is Some(value) else { return None }
    captures[variable] = value.to_owned()
  }
  Some(captures)
}

///|
struct RegisteredPrompt {
  prompt : Prompt
  handler : PromptHandler
}

///|
fn[A : @schema.JsonSchema] schema_for(_witness : A?) -> Json raise McpError {
  let schema = A::json_schema() catch {
    _ => raise InvalidParams("typed tool produced an invalid JSON Schema")
  }
  schema.to_json()
}

///|
/// A transport-neutral, stateless MCP 2026-07-28 server registry.
///
/// Registration is sealed by the first request. Per-client protocol state is
/// carried exclusively by `RequestContext` and is never stored on this value.
pub struct Server {
  priv info : Implementation
  priv instructions : String?
  priv cache_policy : CachePolicy
  priv supported_versions : Array[String]
  priv mut registry_frozen : Bool
  priv tools : Map[String, RegisteredTool]
  priv tool_schemas : Map[String, Tool]
  priv resources : Map[String, RegisteredResource]
  priv resource_templates : Map[String, RegisteredResourceTemplate]
  priv prompts : Map[String, RegisteredPrompt]
  priv completions : Map[String, CompletionHandler]
  priv raw_handlers : Map[String, RawHandler]
  priv tool_list_changed : Bool
  priv resource_list_changed : Bool
  priv prompt_list_changed : Bool
  priv resource_subscriptions : Bool
  priv extensions : Map[String, Json]
  priv extension_result_types : Map[String, String]
  priv experimental : Map[String, Json]
}

///|
pub fn Server::Server(
  name~ : String,
  version~ : String,
  title? : String,
  description? : String,
  icons? : Array[Icon] = [],
  website_url? : String,
  instructions? : String,
  cache_policy? : CachePolicy,
  supported_versions? : Array[String] = [LATEST_PROTOCOL_VERSION],
  tool_list_changed? : Bool = false,
  resource_list_changed? : Bool = false,
  prompt_list_changed? : Bool = false,
  resource_subscriptions? : Bool = false,
  extensions? : Map[String, Json] = Map([]),
  extension_result_types? : Map[String, String] = Map([]),
  experimental? : Map[String, Json] = Map([]),
) -> Server raise McpError {
  if name.is_empty() || version.is_empty() {
    raise InvalidParams("server name and version must not be empty")
  }
  if supported_versions.is_empty() ||
    supported_versions.any(fn(value) { value.is_empty() }) {
    raise InvalidParams("supported_versions must not be empty")
  }
  validate_extension_map(extensions)
  validate_extension_result_types(extension_result_types, extensions)
  {
    info: Implementation(
      name~,
      version~,
      title?,
      description?,
      icons~,
      website_url?,
    ),
    instructions,
    cache_policy: cache_policy.unwrap_or(CachePolicy(ttl_ms=0L, scope=Private)),
    supported_versions: supported_versions.copy(),
    registry_frozen: false,
    tools: Map([]),
    tool_schemas: Map([]),
    resources: Map([]),
    resource_templates: Map([]),
    prompts: Map([]),
    completions: Map([]),
    raw_handlers: Map([]),
    tool_list_changed,
    resource_list_changed,
    prompt_list_changed,
    resource_subscriptions,
    extensions: extensions.copy_json(),
    extension_result_types: extension_result_types.copy(),
    experimental: experimental.copy_json(),
  }
}

///|
/// Explicitly seal the server registry, preventing any further tool, resource,
/// prompt, or completion registrations.
pub fn Server::seal(self : Server) -> Unit {
  self.registry_frozen = true
}

///|
fn Server::ensure_registering(self : Server) -> Unit raise McpError {
  if self.registry_frozen {
    raise InvalidRequest("server registry is sealed after its first request")
  }
}

///|
fn Server::capabilities(self : Server) -> ServerCapabilities {
  ServerCapabilities(
    tools?=if self.tools.is_empty() {
      None
    } else {
      Some(ToolsCapability(list_changed=self.tool_list_changed))
    },
    resources?=if self.resources.is_empty() &&
      self.resource_templates.is_empty() {
      None
    } else {
      Some(
        ResourcesCapability(
          subscribe=self.resource_subscriptions,
          list_changed=self.resource_list_changed,
        ),
      )
    },
    prompts?=if self.prompts.is_empty() {
      None
    } else {
      Some(PromptsCapability(list_changed=self.prompt_list_changed))
    },
    completions=!self.completions.is_empty(),
    extensions=self.extensions,
    experimental=self.experimental,
  )
}

///|
fn Server::install_tool(
  self : Server,
  tool : Tool,
  handler : ToolHandler,
) -> Unit raise McpError {
  self.ensure_registering()
  if self.tools.contains(tool.name) {
    raise InvalidParams("tool already registered: \{tool.name}")
  }
  let input_validator = compile_tool_schema(tool.input_schema)
  let output_validator = match tool.output_schema {
    Some(schema) => Some(compile_tool_schema(schema))
    None => None
  }
  self.tools[tool.name] = { tool, handler, input_validator, output_validator }
  self.tool_schemas[tool.name] = tool
}

///|
/// Return an owned descriptor snapshot for a transport adapter.
///
/// Adapters must inspect the descriptor to validate transport-specific
/// annotations, but must not receive the server's registry map itself.
pub fn Server::tool_descriptor(self : Server, name : String) -> Tool? {
  self.tool_schemas.get(name).map(tool => tool.copy())
}

///|
/// Register a typed async tool handler with request context and MRTR support.
pub fn[A : FromJson + @schema.JsonSchema] Server::tool(
  self : Server,
  name~ : String,
  title? : String,
  description? : String,
  input_schema? : Json,
  output_schema? : Json,
  annotations? : ToolAnnotations,
  icons? : Array[Icon] = [],
  meta? : Json,
  handler : async (RequestContext, A) -> HandlerOutcome[CallToolResult] raise McpError,
) -> Unit raise McpError {
  let schema = match input_schema {
    Some(value) => value
    None => schema_for((None : A?))
  }
  let tool = Tool(
    name~,
    title?,
    description?,
    input_schema=schema,
    output_schema?,
    annotations?,
    icons~,
    meta?,
  )
  self.install_tool(tool, async fn(
    context,
    arguments,
  ) -> HandlerOutcome[CallToolResult] raise McpError {
    let decoded : A = @json.from_json(arguments) catch {
      error =>
        return Complete(
          CallToolResult::error_text("Invalid tool arguments: \{error}"),
        )
    }
    handler(context, decoded)
  })
}

///|
/// Register a raw JSON tool while retaining request context and MRTR support.

///|
/// Register a tool whose arguments and result are handled as raw JSON.
/// This is the explicit escape hatch; typed tools should use `tool`.
pub fn Server::tool_raw(
  self : Server,
  name~ : String,
  title? : String,
  description? : String,
  input_schema? : Json = empty_object_schema(),
  output_schema? : Json,
  annotations? : ToolAnnotations,
  icons? : Array[Icon] = [],
  meta? : Json,
  handler : ToolHandler,
) -> Unit raise McpError {
  self.install_tool(
    Tool(
      name~,
      title?,
      description?,
      input_schema~,
      output_schema?,
      annotations?,
      icons~,
      meta?,
    ),
    handler,
  )
}

///|
pub fn Server::resource(
  self : Server,
  uri~ : String,
  name? : String,
  title? : String,
  description? : String,
  mime_type? : String,
  icons? : Array[Icon] = [],
  annotations? : Annotations,
  size? : Int64,
  meta? : Json,
  handler : async (RequestContext, String) -> HandlerOutcome[ReadResourceResult] raise McpError,
) -> Unit raise McpError {
  self.ensure_registering()
  if self.resources.contains(uri) {
    raise InvalidParams("resource already registered: \{uri}")
  }
  self.resources[uri] = {
    resource: Resource(
      uri~,
      name=name.unwrap_or(uri),
      title?,
      description?,
      mime_type?,
      icons~,
      annotations?,
      size?,
      meta?,
    ),
    handler,
  }
}

///|
pub fn Server::resource_template(
  self : Server,
  uri_template~ : String,
  name? : String,
  title? : String,
  description? : String,
  mime_type? : String,
  icons? : Array[Icon] = [],
  annotations? : Annotations,
  meta? : Json,
  handler : async (RequestContext, String, Map[String, String]) -> HandlerOutcome[
    ReadResourceResult,
  ] raise McpError,
) -> Unit raise McpError {
  self.ensure_registering()
  if self.resource_templates.contains(uri_template) {
    raise InvalidParams("resource template already registered: \{uri_template}")
  }
  let (matcher, variables) = compile_resource_template(uri_template)
  self.resource_templates[uri_template] = {
    template: ResourceTemplate(
      uri_template~,
      name=name.unwrap_or(uri_template),
      title?,
      description?,
      mime_type?,
      icons~,
      annotations?,
      meta?,
    ),
    matcher,
    variables,
    handler,
  }
}

///|
pub fn Server::prompt(
  self : Server,
  name~ : String,
  title? : String,
  description? : String,
  arguments? : Array[PromptArgument] = [],
  icons? : Array[Icon] = [],
  meta? : Json,
  handler : async (RequestContext, Map[String, String]) -> HandlerOutcome[
    GetPromptResult,
  ] raise McpError,
) -> Unit raise McpError {
  self.ensure_registering()
  if self.prompts.contains(name) {
    raise InvalidParams("prompt already registered: \{name}")
  }
  validate_prompt_argument_names(arguments, "prompt \{name}")
  self.prompts[name] = {
    prompt: Prompt(name~, title?, description?, arguments~, icons~, meta?),
    handler,
  }
}

///|
pub fn Server::completion(
  self : Server,
  reference~ : CompletionReference,
  handler : CompletionHandler,
) -> Unit raise McpError {
  self.ensure_registering()
  let key = completion_key(reference)
  if self.completions.contains(key) {
    raise InvalidParams("completion already registered: \{key}")
  }
  self.completions[key] = handler
}

///|
/// Register a negotiated extension method.
pub fn Server::on(
  self : Server,
  method_name~ : String,
  handler : RawHandler,
) -> Unit raise McpError {
  self.ensure_registering()
  if self.raw_handlers.contains(method_name) {
    raise InvalidParams("method already registered: \{method_name}")
  }
  self.raw_handlers[method_name] = handler
}

///|
fn parse_context(
  request : @jsonrpc.Request[Json],
  hooks? : RequestHooks = RequestHooks(),
) -> RequestContext raise McpError {
  guard request.params is Object(fields) else {
    raise InvalidParams("request params must be an object")
  }
  let meta = match fields {
    { "_meta": value, .. } => RequestMeta::from_json(value)
    _ => raise InvalidParams("request params._meta is required")
  }
  let input_responses = match fields {
    { "inputResponses": value, .. } => Some(InputResponse::map_from_json(value))
    _ => None
  }
  let request_state = match fields {
    { "requestState": String(s), .. } => Some(s)
    { "requestState": Null, .. } => None
    { "requestState": _, .. } =>
      raise InvalidParams("request params.requestState must be a string")
    _ => None
  }
  RequestContext(
    request_id=request.id.as_json(),
    method_name=request.method_name,
    meta~,
    input_responses?,
    request_state?,
    hooks~,
  )
}

///|
fn Server::ensure_supported_version(
  self : Server,
  context : RequestContext,
) -> Unit raise McpError {
  let requested = context.meta.protocol_version
  if !self.supported_versions.contains(requested) {
    raise UnsupportedProtocolVersion(
      requested~,
      supported=self.supported_versions.copy(),
    )
  }
}

///|
/// Report whether a protocol version is accepted by this server.
pub fn Server::supports_protocol_version(
  self : Server,
  version : String,
) -> Bool {
  self.supported_versions.contains(version)
}

///|
fn required_elicitation_capability(
  request : InputRequest,
) -> ClientCapabilities {
  let is_url = request.params is Object({ "mode": String("url"), .. })
  ClientCapabilities(
    elicitation=if is_url {
      ElicitationCapability(url=Json::object({}))
    } else {
      ElicitationCapability(form=Json::object({}))
    },
  )
}

///|
fn required_client_capability(method_name : String) -> ClientCapabilities {
  match method_name {
    "roots/list" => ClientCapabilities(roots=RootsCapability())
    "sampling/createMessage" =>
      ClientCapabilities(sampling=SamplingCapability())
    _ => ClientCapabilities()
  }
}

///|
fn Server::validate_input_requests(
  self : Server,
  context : RequestContext,
  result : InputRequiredResult,
) -> Unit raise McpError {
  ignore(self)
  if result.input_requests is Some(requests) {
    for _, request in requests {
      match request.method_name {
        "elicitation/create" => {
          let required = required_elicitation_capability(request)
          let actual = context.meta.client_capabilities.elicitation
          let accepted = match (required.elicitation, actual) {
            (Some({ url: Some(_), .. }), Some({ url: Some(_), .. })) => true
            (Some({ form: Some(_), .. }), Some({ form: Some(_), .. })) => true
            (Some({ form: Some(_), .. }), Some({ form: None, url: None })) =>
              true
            _ => false
          }
          if !accepted {
            raise MissingRequiredClientCapability(
              "Request requires client elicitation capability", required,
            )
          }
        }
        "roots/list" | "sampling/createMessage" as method_name => {
          let actual_roots = context.meta.client_capabilities.roots
          let actual_sampling = context.meta.client_capabilities.sampling
          let accepted = match method_name {
            "roots/list" => actual_roots is Some(_)
            "sampling/createMessage" => actual_sampling is Some(_)
            _ => false
          }
          if !accepted {
            raise MissingRequiredClientCapability(
              "Request requires client capability: \{method_name}",
              required_client_capability(method_name),
            )
          }
        }
        method_name =>
          raise InvalidRequest("unsupported MRTR input request: \{method_name}")
      }
    }
  }
}

///|
fn Server::input_required_json(
  self : Server,
  context : RequestContext,
  result : InputRequiredResult,
) -> Json raise McpError {
  self.validate_input_requests(context, result)
  guard result.to_json() is Object(fields) else {
    raise InvalidParams("input_required result must be an object")
  }
  let fields = fields.copy_json()
  merge_result_meta(fields, server_info=self.info)
  Json::object(fields)
}

///|
fn Server::extension_result_json(
  self : Server,
  result_type : String,
  result : Json,
) -> Json raise McpError {
  if !self.extension_result_types.contains(result_type) {
    raise InvalidRequest(
      "handler returned unregistered extension result type \{result_type}",
    )
  }
  guard result is Object(fields) else {
    raise InvalidParams("extension result must be an object")
  }
  let fields = fields.copy_json()
  fields["resultType"] = Json::string(result_type)
  merge_result_meta(fields, server_info=self.info)
  Json::object(fields)
}

///|
fn[T : ToJson] Server::outcome_json(
  self : Server,
  context : RequestContext,
  method_name : String,
  outcome : HandlerOutcome[T],
) -> Json raise McpError {
  match outcome {
    Complete(value) => complete_result(value.to_json(), server_info=self.info)
    InputRequired(result) => {
      if method_name != "tools/call" &&
        method_name != "resources/read" &&
        method_name != "prompts/get" {
        raise InvalidRequest("input_required is not allowed for \{method_name}")
      }
      self.input_required_json(context, result)
    }
    ExtensionResult(result_type, result) =>
      self.extension_result_json(result_type, result)
  }
}

///|
fn Server::cacheable_complete(
  self : Server,
  payload : Json,
) -> Json raise McpError {
  guard payload is Object(fields) else {
    raise InvalidParams("cacheable result must be an object")
  }
  let fields = fields.copy_json()
  self.cache_policy.put(fields)
  complete_result(Json::object(fields), server_info=self.info)
}

///|
fn Server::discover(self : Server) -> Json raise McpError {
  DiscoverResult(
    supported_versions=self.supported_versions,
    capabilities=self.capabilities(),
    instructions?=self.instructions,
    cache_policy=self.cache_policy,
    meta=ResultMeta(server_info=self.info),
  ).to_json()
}

///|
fn Server::list_tools(
  self : Server,
  params : ListParams,
) -> Json raise McpError {
  if self.tools.is_empty() {
    raise MethodNotFound("tools/list")
  }
  let page = paginate(
    Array::from_iter(self.tools.values().map(item => item.tool)),
    cursor?=params.cursor,
  )
  let payload : Map[String, Json] = {
    "tools": page.items.map(item => item.to_json()).to_json(),
  }
  payload.set_opt("nextCursor", page.next_cursor.map(Json::string))
  self.cacheable_complete(Json::object(payload))
}

///|
async fn Server::call_tool(
  self : Server,
  context : RequestContext,
  params : CallToolParams,
) -> Json raise McpError {
  if self.tools.is_empty() {
    raise MethodNotFound("tools/call")
  }
  let name = params.name
  let arguments = params.arguments
  guard self.tools.get(name) is Some(registered) else {
    raise InvalidParams("unknown tool: \{name}")
  }
  if schema_validation_error(registered.input_validator, arguments)
    is Some(error) {
    return self.outcome_json(
      context,
      "tools/call",
      Complete(
        CallToolResult::error_text(
          "Invalid tool arguments: inputSchema validation failed: \{error}",
        ),
      ),
    )
  }
  let outcome = (registered.handler)(context, arguments)
  match outcome {
    Complete(result) =>
      if registered.output_validator is Some(validator) && !result.is_error {
        guard result.structured_content is Some(value) else {
          raise InternalError(
            "tool declares outputSchema but returned no structuredContent",
          )
        }
        if schema_validation_error(validator, value) is Some(error) {
          raise InternalError(
            "tool structuredContent does not match outputSchema: \{error}",
          )
        }
      }
    InputRequired(_) => ()
    ExtensionResult(_, _) => ()
  }
  self.outcome_json(context, "tools/call", outcome)
}

///|
fn Server::list_resources(
  self : Server,
  params : ListParams,
) -> Json raise McpError {
  if self.resources.is_empty() && self.resource_templates.is_empty() {
    raise MethodNotFound("resources/list")
  }
  let page = paginate(
    Array::from_iter(self.resources.values().map(item => item.resource)),
    cursor?=params.cursor,
  )
  let payload : Map[String, Json] = {
    "resources": page.items.map(item => item.to_json()).to_json(),
  }
  payload.set_opt("nextCursor", page.next_cursor.map(Json::string))
  self.cacheable_complete(Json::object(payload))
}

///|
fn Server::list_resource_templates(
  self : Server,
  params : ListParams,
) -> Json raise McpError {
  if self.resource_templates.is_empty() {
    raise MethodNotFound("resources/templates/list")
  }
  let page = paginate(
    Array::from_iter(
      self.resource_templates.values().map(item => item.template),
    ),
    cursor?=params.cursor,
  )
  let payload : Map[String, Json] = {
    "resourceTemplates": page.items.map(item => item.to_json()).to_json(),
  }
  payload.set_opt("nextCursor", page.next_cursor.map(Json::string))
  self.cacheable_complete(Json::object(payload))
}

///|
async fn Server::read_resource(
  self : Server,
  context : RequestContext,
  params : ReadResourceParams,
) -> Json raise McpError {
  if self.resources.is_empty() && self.resource_templates.is_empty() {
    raise MethodNotFound("resources/read")
  }
  let uri = params.uri
  if self.resources.get(uri) is Some(registered) {
    return match (registered.handler)(context, uri) {
      Complete(value) => self.cacheable_complete(value.to_json())
      InputRequired(value) => self.input_required_json(context, value)
      ExtensionResult(result_type, value) =>
        self.extension_result_json(result_type, value)
    }
  }
  for registered in self.resource_templates.values() {
    if registered.captures(uri) is Some(captures) {
      return match (registered.handler)(context, uri, captures) {
        Complete(value) => self.cacheable_complete(value.to_json())
        InputRequired(value) => self.input_required_json(context, value)
        ExtensionResult(result_type, value) =>
          self.extension_result_json(result_type, value)
      }
    }
  }
  raise InvalidParamsWithData(
    "resource not found: \{uri}",
    Json::object({ "uri": Json::string(uri) }),
  )
}

///|
fn Server::list_prompts(
  self : Server,
  params : ListParams,
) -> Json raise McpError {
  if self.prompts.is_empty() {
    raise MethodNotFound("prompts/list")
  }
  let page = paginate(
    Array::from_iter(self.prompts.values().map(item => item.prompt)),
    cursor?=params.cursor,
  )
  let payload : Map[String, Json] = {
    "prompts": page.items.map(item => item.to_json()).to_json(),
  }
  payload.set_opt("nextCursor", page.next_cursor.map(Json::string))
  self.cacheable_complete(Json::object(payload))
}

///|
async fn Server::get_prompt(
  self : Server,
  context : RequestContext,
  params : GetPromptParams,
) -> Json raise McpError {
  if self.prompts.is_empty() {
    raise MethodNotFound("prompts/get")
  }
  let name = params.name
  guard self.prompts.get(name) is Some(registered) else {
    raise InvalidParams("unknown prompt: \{name}")
  }
  let arguments = params.arguments
  for argument in registered.prompt.arguments {
    if argument.required && !arguments.contains(argument.name) {
      raise InvalidParams(
        "prompts/get required argument is missing: \{argument.name}",
      )
    }
  }
  self.outcome_json(
    context,
    "prompts/get",
    (registered.handler)(context, arguments),
  )
}

///|
fn completion_key(reference : CompletionReference) -> String {
  match reference {
    PromptRef(name~, ..) => "prompt:\{name}"
    ResourceRef(uri~) => "resource:\{uri}"
  }
}

///|
async fn Server::complete(
  self : Server,
  context : RequestContext,
  request : CompletionRequest,
) -> Json raise McpError {
  if self.completions.is_empty() {
    raise MethodNotFound("completion/complete")
  }
  let key = completion_key(request.reference)
  guard self.completions.get(key) is Some(handler) else {
    raise InvalidParams("no completion handler registered for \{key}")
  }
  complete_result(handler(context, request).to_json(), server_info=self.info)
}

///|
async fn Server::dispatch_request(
  self : Server,
  request : @jsonrpc.Request[Json],
  hooks? : RequestHooks = RequestHooks(),
) -> Json raise McpError {
  self.registry_frozen = true
  let context = parse_context(request, hooks~)
  self.ensure_supported_version(context)
  match request.method_name {
    "server/discover" => self.discover()
    "tools/list" => self.list_tools(ListParams::from_json(request.params))
    "tools/call" =>
      self.call_tool(context, CallToolParams::from_json(request.params))
    "resources/list" =>
      self.list_resources(ListParams::from_json(request.params))
    "resources/templates/list" =>
      self.list_resource_templates(ListParams::from_json(request.params))
    "resources/read" =>
      self.read_resource(context, ReadResourceParams::from_json(request.params))
    "prompts/list" => self.list_prompts(ListParams::from_json(request.params))
    "prompts/get" =>
      self.get_prompt(context, GetPromptParams::from_json(request.params))
    "completion/complete" =>
      self.complete(context, CompletionRequest::from_json(request.params))
    "subscriptions/listen" =>
      raise InvalidRequest(
        "subscriptions/listen must be handled as a transport stream",
      )
    method_name => {
      guard self.raw_handlers.get(method_name) is Some(handler) else {
        raise MethodNotFound(method_name)
      }
      self.outcome_json(context, method_name, handler(context, request.params))
    }
  }
}

///|
/// Handle one MCP JSON-RPC request. Batches and client-sent responses are
/// rejected. The stdio transport consumes cancellation notifications itself.
pub async fn Server::handle_jsonrpc(self : Server, message : Json) -> Json? {
  self.handle_jsonrpc_with_hooks(message, hooks=RequestHooks())
}

///|
/// Dispatch one request with transport-owned progress, cancellation, and
/// authentication metadata hooks.
pub async fn Server::handle_jsonrpc_with_hooks(
  self : Server,
  message : Json,
  hooks~ : RequestHooks,
) -> Json? {
  let decoded = @jsonrpc.decode(message) catch {
    error =>
      return Some(
        error_response(
          InvalidRequest(
            match error {
              InvalidMessage(msg) => msg
            },
          ),
        ),
      )
  }
  match decoded {
    @jsonrpc.Message::Notification(_) => None
    @jsonrpc.Message::Response(_) =>
      Some(error_response(InvalidRequest("MCP server expected a request")))
    @jsonrpc.Message::Request(request) =>
      try {
        let result = self.dispatch_request(request, hooks~)
        Some(success_response(request.id, result))
      } catch {
        error => Some(error_response(id=request.id, error))
      } noraise {
        response => response
      }
  }
}

///|
/// Check if a message is a `subscriptions/listen` request.
pub fn is_subscription_request(message : Json) -> Bool {
  try (
    @jsonrpc.decode(message)
    is Request({ method_name: "subscriptions/listen", .. })
  ) catch {
    _ => false
  }
}

///|
pub fn Server::is_subscription_request(self : Server, message : Json) -> Bool {
  ignore(self)
  is_subscription_request(message)
}

///|
/// Check if a message is a `notifications/cancelled` notification.
pub fn is_cancelled_notification(message : Json) -> Bool {
  try (
    @jsonrpc.decode(message)
    is Notification({ method_name: "notifications/cancelled", .. })
  ) catch {
    _ => false
  }
}

///|
pub fn Server::is_cancelled_notification(self : Server, message : Json) -> Bool {
  ignore(self)
  is_cancelled_notification(message)
}

///|

///|

///|
priv struct ActiveSessionTask {
  cancelled : Ref[Bool]
  task : @async.Task[Unit]
}

///|
fn ActiveSessionTask::cancel(self : ActiveSessionTask) -> Unit {
  self.cancelled.val = true
  self.task.cancel()
}

///|
priv struct ServerSession {
  server : Server
  group : @async.TaskGroup[Unit]
  output : @aqueue.Queue[Json?]
  active_tasks : Map[String, ActiveSessionTask]
  handlers : Array[@async.Task[Unit]]
  on_subscription : async (Subscription, async (Json) -> Unit) -> Unit
}

///|
async fn ServerSession::emit(self : ServerSession, message : Json) -> Unit {
  self.output.put(Some(message)) catch {
    _ => ()
  }
}

///|
fn ServerSession::dispatch_subscription(
  self : ServerSession,
  request_id : Json,
  message : Json,
) -> Unit {
  let subscription = self.server.accept_subscription(message) catch {
    error => {
      ignore(
        self.group.spawn(() => {
          self.emit(error_response_from_json_id(id=request_id, error))
        }),
      )
      return
    }
  }
  let key = subscription.id.stringify()
  let cancelled = Ref(false)
  let task = self.group.spawn(() => {
    self.emit(subscription.acknowledgement())
    let emit_event = async fn(notification : Json) {
      if subscription.allows_event(notification) {
        self.emit(notification)
      }
    }
    (self.on_subscription)(subscription, emit_event) catch {
      _ => ()
    }
    if !cancelled.val {
      self.emit(subscription.close_response())
    }
    self.active_tasks.remove(key)
  })
  self.active_tasks[key] = { cancelled, task }
}

///|
fn ServerSession::cancel_task(self : ServerSession, message : Json) -> Unit {
  try {
    guard @jsonrpc.decode(message) is Notification({ params, .. }) else {
      return
    }
    let params = CancelledNotificationParams::from_json(params)
    let key = params.request_id.stringify()
    if self.active_tasks.get(key) is Some(active) {
      self.active_tasks.remove(key)
      active.cancel()
    }
  } catch {
    _ => ()
  }
}

///|
fn ServerSession::dispatch_rpc(
  self : ServerSession,
  request_id : Json?,
  message : Json,
) -> Unit {
  let key_opt = request_id.map(fn(id) { id.stringify() })
  let cancelled = Ref(false)
  let task = self.group.spawn(() => {
    let hooks = RequestHooks(
      emit_notification=async fn(notification) raise McpError {
        self.emit(notification) catch {
          error => raise InternalError(error.to_string())
        }
      },
      is_cancelled=fn() { cancelled.val },
    )
    if self.server.handle_jsonrpc_with_hooks(message, hooks~) is Some(response) {
      self.emit(response)
    }
    if key_opt is Some(key) {
      self.active_tasks.remove(key)
    }
  })
  self.handlers.push(task)
  if key_opt is Some(key) {
    self.active_tasks[key] = { cancelled, task }
  }
}

///|
fn ServerSession::handle_message(self : ServerSession, message : Json) -> Unit {
  let decoded = Some(@jsonrpc.decode(message)) catch { _ => None }
  match decoded {
    Some(Request({ id, method_name: "subscriptions/listen", .. })) =>
      self.dispatch_subscription(id.as_json(), message)
    Some(Notification({ method_name: "notifications/cancelled", .. })) =>
      self.cancel_task(message)
    Some(Request({ id, .. })) => self.dispatch_rpc(Some(id.as_json()), message)
    _ => self.dispatch_rpc(None, message)
  }
}

///|
async fn ServerSession::shutdown(self : ServerSession) -> Unit {
  for _, active in self.active_tasks {
    active.cancel()
  }
  for task in self.handlers {
    task.wait() catch {
      _ => ()
    }
  }
  self.output.put(None) catch {
    _ => ()
  }
}

///|
/// Serve a bidirectional stream of MCP messages.
///
/// Handles concurrent request dispatch, `subscriptions/listen` stream lifecycles,
/// `notifications/cancelled` task cancellation, and progress notifications.
pub async fn Server::serve_framed(
  self : Server,
  read_message~ : async () -> Json?,
  send_message~ : async (Json) -> Unit,
  on_subscription? : async (Subscription, async (Json) -> Unit) -> Unit = fn(
    _,
    _,
  ) {
    ()
  },
) -> Unit {
  @async.with_task_group(group => {
    let output : @aqueue.Queue[Json?] = Queue(kind=Unbounded)
    let writer = group.spawn(() => {
      while output.get() is Some(msg) {
        send_message(msg)
      }
    })
    let session = ServerSession::{
      server: self,
      group,
      output,
      active_tasks: Map([]),
      handlers: [],
      on_subscription,
    }
    while read_message() is Some(message) {
      session.handle_message(message)
    }
    session.shutdown()
    writer.wait() catch {
      _ => ()
    }
  })
}
