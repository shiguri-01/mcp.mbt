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
  input_validator : CompiledJsonSchema
  output_validator : CompiledJsonSchema?
}

///|
/// Return the registered input schema for a tool.
///
/// Transport adapters use this read-only view to validate metadata mirrored
/// outside the JSON-RPC body while keeping the server registry authoritative.
pub fn Server::tool_input_schema(self : Server, name : String) -> Json? {
  match self.tools.get(name) {
    Some(registered) => Some(copy_json(registered.tool.input_schema))
    None => None
  }
}

///|
pub fn Server::supported_versions(self : Server) -> Array[String] {
  self.supported_versions.copy()
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
fn compile_resource_template(
  template : String,
) -> (Regex, Array[String]) raise McpError {
  let sections = template.split("{").to_array()
  let mut matcher = Regex::string(sections[0])
  let variables : Array[String] = []
  for index = 1; index < sections.length(); index = index + 1 {
    let pieces = sections[index].split("}").to_array()
    if pieces.length() != 2 {
      raise InvalidParams(
        "resource template must use simple {variable} expressions",
      )
    }
    let variable = pieces[0].to_owned()
    if variable.is_empty() || variables.contains(variable) {
      raise InvalidParams(
        "resource template variable must be non-empty and unique",
      )
    }
    variables.push(variable)
    matcher = matcher +
      Regex::unsafe_from_string("[^/?#]+").capture(variable) +
      Regex::string(pieces[1])
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
fn[A : @schema.JsonSchema] schema_for(_witness : A?) -> Json {
  A::json_schema()
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
  supported_versions? : Array[String] = [latest_protocol_version],
  tool_list_changed? : Bool = false,
  resource_list_changed? : Bool = false,
  prompt_list_changed? : Bool = false,
  resource_subscriptions? : Bool = false,
  extensions? : Map[String, Json] = Map([]),
  extension_result_types? : Map[String, String] = Map([]),
  experimental? : Map[String, Json] = Map([]),
) -> Server raise McpError {
  if supported_versions.is_empty() {
    raise InvalidParams("supported_versions must not be empty")
  }
  validate_extension_map(extensions, "server capabilities.extensions")
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
    resources: Map([]),
    resource_templates: Map([]),
    prompts: Map([]),
    completions: Map([]),
    raw_handlers: Map([]),
    tool_list_changed,
    resource_list_changed,
    prompt_list_changed,
    resource_subscriptions,
    extensions: copy_json_map(extensions),
    extension_result_types: extension_result_types.copy(),
    experimental: copy_json_map(experimental),
  }
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
fn Server::register_tool(
  self : Server,
  tool : Tool,
  handler : ToolHandler,
) -> Unit raise McpError {
  self.ensure_registering()
  if self.tools.contains(tool.name) {
    raise InvalidParams("tool already registered: \{tool.name}")
  }
  let input_validator = compile_json_schema(tool.input_schema)
  let output_validator = match tool.output_schema {
    Some(schema) => Some(compile_json_schema(schema))
    None => None
  }
  self.tools[tool.name] = { tool, handler, input_validator, output_validator }
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
  self.register_tool(tool, async fn(
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
pub fn Server::tool_json(
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
  self.register_tool(
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
fn get_prompt_arguments(
  params : Map[String, Json],
) -> Map[String, String] raise McpError {
  let values : Map[String, String] = Map([])
  match params.get("arguments") {
    Some(Object(arguments)) =>
      for key, value in arguments {
        match value {
          String(value) => values[key] = value
          _ => raise InvalidParams("prompts/get arguments must be strings")
        }
      }
    Some(Null) | None => ()
    Some(_) => raise InvalidParams("prompts/get arguments must be an object")
  }
  values
}

///|
fn parse_context(
  request : RpcRequest,
  hooks? : RequestHooks = RequestHooks(),
) -> RequestContext raise McpError {
  let fields = expect_object(request.params, "request params")
  let meta = match fields.get("_meta") {
    Some(value) => RequestMeta::decode(value)
    None => raise InvalidParams("request params._meta is required")
  }
  let input_responses = match fields.get("inputResponses") {
    Some(value) => Some(parse_input_responses(value))
    None => None
  }
  let request_state = get_optional_string(
    fields, "requestState", "request params",
  )
  RequestContext(
    request_id=request.id,
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
fn required_deprecated_capability(method_name : String) -> ClientCapabilities {
  ClientCapabilities(
    deprecated=match method_name {
      "roots/list" => DeprecatedClientCapabilities(roots=Json::object({}))
      "sampling/createMessage" =>
        DeprecatedClientCapabilities(sampling=Json::object({}))
      _ => DeprecatedClientCapabilities()
    },
  )
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
          let actual = context.meta.client_capabilities.deprecated
          let accepted = match (method_name, actual) {
            ("roots/list", Some({ roots: Some(_), .. })) => true
            ("sampling/createMessage", Some({ sampling: Some(_), .. })) => true
            _ => false
          }
          if !accepted {
            raise MissingRequiredClientCapability(
              "Request requires deprecated client capability: \{method_name}",
              required_deprecated_capability(method_name),
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
  let fields = expect_object(result.to_json(), "input_required result").copy()
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
  let fields = expect_object(result, "extension result").copy()
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
  let fields = expect_object(payload, "cacheable result").copy()
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
  fields : Map[String, Json],
) -> Json raise McpError {
  if self.tools.is_empty() {
    raise MethodNotFound("tools/list")
  }
  let page = paginate(
    Array::from_iter(self.tools.values().map(item => item.tool)),
    cursor?=get_optional_string(fields, "cursor", "tools/list params"),
  )
  let payload : Map[String, Json] = {
    "tools": page.items.map(item => item.to_json()).to_json(),
  }
  put_next_cursor(payload, page.next_cursor)
  self.cacheable_complete(Json::object(payload))
}

///|
async fn Server::call_tool(
  self : Server,
  context : RequestContext,
  fields : Map[String, Json],
) -> Json raise McpError {
  if self.tools.is_empty() {
    raise MethodNotFound("tools/call")
  }
  let name = get_string(fields, "name", "tools/call params")
  let arguments = match fields.get("arguments") {
    Some(Object(_) as value) => value
    Some(Null) | None => Json::object({})
    Some(_) =>
      raise InvalidParams("tools/call params.arguments must be an object")
  }
  match self.tools.get(name) {
    Some(registered) => {
      if registered.input_validator.validate(arguments) is Some(error) {
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
            if validator.validate(value) is Some(error) {
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
    None => raise InvalidParams("unknown tool: \{name}")
  }
}

///|
fn Server::list_resources(
  self : Server,
  fields : Map[String, Json],
) -> Json raise McpError {
  if self.resources.is_empty() && self.resource_templates.is_empty() {
    raise MethodNotFound("resources/list")
  }
  let page = paginate(
    Array::from_iter(self.resources.values().map(item => item.resource)),
    cursor?=get_optional_string(fields, "cursor", "resources/list params"),
  )
  let payload : Map[String, Json] = {
    "resources": page.items.map(item => item.to_json()).to_json(),
  }
  put_next_cursor(payload, page.next_cursor)
  self.cacheable_complete(Json::object(payload))
}

///|
fn Server::list_resource_templates(
  self : Server,
  fields : Map[String, Json],
) -> Json raise McpError {
  if self.resource_templates.is_empty() {
    raise MethodNotFound("resources/templates/list")
  }
  let page = paginate(
    Array::from_iter(
      self.resource_templates.values().map(item => item.template),
    ),
    cursor?=get_optional_string(
      fields, "cursor", "resources/templates/list params",
    ),
  )
  let payload : Map[String, Json] = {
    "resourceTemplates": page.items.map(item => item.to_json()).to_json(),
  }
  put_next_cursor(payload, page.next_cursor)
  self.cacheable_complete(Json::object(payload))
}

///|
async fn Server::read_resource(
  self : Server,
  context : RequestContext,
  fields : Map[String, Json],
) -> Json raise McpError {
  if self.resources.is_empty() && self.resource_templates.is_empty() {
    raise MethodNotFound("resources/read")
  }
  let uri = get_string(fields, "uri", "resources/read params")
  match self.resources.get(uri) {
    Some(registered) =>
      match (registered.handler)(context, uri) {
        Complete(value) => self.cacheable_complete(value.to_json())
        InputRequired(value) => self.input_required_json(context, value)
        ExtensionResult(result_type, value) =>
          self.extension_result_json(result_type, value)
      }
    None => {
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
  }
}

///|
fn Server::list_prompts(
  self : Server,
  fields : Map[String, Json],
) -> Json raise McpError {
  if self.prompts.is_empty() {
    raise MethodNotFound("prompts/list")
  }
  let page = paginate(
    Array::from_iter(self.prompts.values().map(item => item.prompt)),
    cursor?=get_optional_string(fields, "cursor", "prompts/list params"),
  )
  let payload : Map[String, Json] = {
    "prompts": page.items.map(item => item.to_json()).to_json(),
  }
  put_next_cursor(payload, page.next_cursor)
  self.cacheable_complete(Json::object(payload))
}

///|
async fn Server::get_prompt(
  self : Server,
  context : RequestContext,
  fields : Map[String, Json],
) -> Json raise McpError {
  if self.prompts.is_empty() {
    raise MethodNotFound("prompts/get")
  }
  let name = get_string(fields, "name", "prompts/get params")
  match self.prompts.get(name) {
    Some(registered) => {
      let arguments = get_prompt_arguments(fields)
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
    None => raise InvalidParams("unknown prompt: \{name}")
  }
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
  params : Json,
) -> Json raise McpError {
  if self.completions.is_empty() {
    raise MethodNotFound("completion/complete")
  }
  let request = parse_completion_request(Some(params))
  let key = completion_key(request.reference)
  match self.completions.get(key) {
    Some(handler) =>
      complete_result(
        handler(context, request).to_json(),
        server_info=self.info,
      )
    None => raise InvalidParams("no completion handler registered for \{key}")
  }
}

///|
async fn Server::dispatch_request(
  self : Server,
  request : RpcRequest,
  hooks? : RequestHooks = RequestHooks(),
) -> Json raise McpError {
  self.registry_frozen = true
  let context = parse_context(request, hooks~)
  self.ensure_supported_version(context)
  let fields = expect_object(request.params, "request params")
  match request.method_name {
    "server/discover" => self.discover()
    "tools/list" => self.list_tools(fields)
    "tools/call" => self.call_tool(context, fields)
    "resources/list" => self.list_resources(fields)
    "resources/templates/list" => self.list_resource_templates(fields)
    "resources/read" => self.read_resource(context, fields)
    "prompts/list" => self.list_prompts(fields)
    "prompts/get" => self.get_prompt(context, fields)
    "completion/complete" => self.complete(context, request.params)
    "subscriptions/listen" =>
      raise InvalidRequest(
        "subscriptions/listen must be handled as a transport stream",
      )
    method_name =>
      match self.raw_handlers.get(method_name) {
        Some(handler) =>
          self.outcome_json(
            context,
            method_name,
            handler(context, request.params),
          )
        None => raise MethodNotFound(method_name)
      }
  }
}

///|
fn response_error_id(message : Json) -> Json? {
  match message {
    Object({ "id": String(_) | Number(_) as id, .. }) => Some(id)
    _ => None
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
  if is_rpc_notification(message) {
    return None
  }
  let id = response_error_id(message)
  try {
    let request = parse_rpc_request(message)
    let result = self.dispatch_request(request, hooks~)
    Some(rpc_result_response(request.id, result))
  } catch {
    error => Some(rpc_error_response(id, error))
  } noraise {
    response => response
  }
}
