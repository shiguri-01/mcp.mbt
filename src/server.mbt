///|
type ToolHandler = (Json?) -> CallToolResult raise McpError

///|
type ResourceHandler = (String) -> ReadResourceResult raise McpError

///|
type PromptHandler = (Map[String, String]) -> Json raise McpError

///|
type CompletionHandler = (CompletionRequest) -> CompleteResult raise McpError

///|
enum SessionState {
  Created
  InitializeResponded
  Ready
}

///|
pub(all) struct InitializeParams {
  protocol_version : String
  capabilities : ClientCapabilities
  client_info : Implementation
  meta : Json?
} derive(Debug, Eq)

///|
struct RegisteredTool {
  tool : Tool
  handler : ToolHandler
}

///|
struct RegisteredResourceTemplate {
  template : ResourceTemplate
}

///|
struct RegisteredResource {
  resource : Resource
  handler : ResourceHandler
}

///|
struct RegisteredPrompt {
  prompt : Prompt
  handler : PromptHandler
}

///|
pub struct Server {
  priv info : Implementation
  priv capabilities : ServerCapabilities
  priv instructions : String?
  priv mut state : SessionState
  priv mut protocol_version : String?
  priv mut client_capabilities : ClientCapabilities?
  priv mut client_info : Implementation?
  priv tools : Map[String, RegisteredTool]
  priv resources : Map[String, RegisteredResource]
  priv resource_subscriptions : Map[String, Bool]
  priv resource_templates : Map[String, RegisteredResourceTemplate]
  priv prompts : Map[String, RegisteredPrompt]
  priv completions : Map[String, CompletionHandler]
  priv mut logging_level : LoggingLevel
}

///|
/// Create a transport-neutral MCP server dispatcher.
pub fn Server::Server(
  name~ : String,
  version~ : String,
  title? : String,
  description? : String,
  icons? : Array[Icon] = [],
  website_url? : String,
  instructions? : String,
  capabilities? : ServerCapabilities = ServerCapabilities::full(),
) -> Server {
  {
    info: Implementation(
      name~,
      version~,
      title?,
      description?,
      icons~,
      website_url?,
    ),
    capabilities,
    instructions,
    state: Created,
    protocol_version: None,
    client_capabilities: None,
    client_info: None,
    tools: {},
    resources: {},
    resource_subscriptions: {},
    resource_templates: {},
    prompts: {},
    completions: {},
    logging_level: Info,
  }
}

///|
/// Register a tool with raw `Json?` arguments.
///
/// Use this when MoonBit pattern matching on `Json` is clearer than defining a
/// typed input struct.
pub fn Server::json_tool(
  self : Server,
  name~ : String,
  title? : String,
  description? : String,
  input_schema? : Json = empty_object_schema(),
  output_schema? : Json,
  annotations? : ToolAnnotations,
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
    ),
    handler,
  )
}

///|
fn Server::register_resource(
  self : Server,
  resource : Resource,
  handler : ResourceHandler,
) -> Unit raise McpError {
  if self.resources.contains(resource.uri) {
    raise InvalidParams("resource already registered: \{resource.uri}")
  }
  self.resources[resource.uri] = { resource, handler }
}

///|
fn Server::register_resource_template(
  self : Server,
  template : ResourceTemplate,
) -> Unit raise McpError {
  if self.resource_templates.contains(template.uri_template) {
    raise InvalidParams(
      "resource template already registered: \{template.uri_template}",
    )
  }
  self.resource_templates[template.uri_template] = { template, }
}

///|
fn Server::register_prompt(
  self : Server,
  prompt : Prompt,
  handler : PromptHandler,
) -> Unit raise McpError {
  if self.prompts.contains(prompt.name) {
    raise InvalidParams("prompt already registered: \{prompt.name}")
  }
  self.prompts[prompt.name] = { prompt, handler }
}

///|
fn Server::register_tool(
  self : Server,
  tool : Tool,
  handler : ToolHandler,
) -> Unit raise McpError {
  if self.tools.contains(tool.name) {
    raise InvalidParams("tool already registered: \{tool.name}")
  }
  self.tools[tool.name] = { tool, handler }
}

///|
/// Register a tool that decodes arguments through `FromJson`.
///
/// If `input_schema` is omitted, the schema comes from `A::json_schema()`.
pub fn[A : FromJson + @schema.JsonSchema] Server::tool(
  self : Server,
  name~ : String,
  title? : String,
  description? : String,
  input_schema? : Json,
  output_schema? : Json,
  annotations? : ToolAnnotations,
  handler : (A) -> CallToolResult raise McpError,
) -> Unit raise McpError {
  let schema = match input_schema {
    Some(schema) => schema
    None => A::json_schema()
  }
  self.json_tool(
    name~,
    title?,
    description?,
    input_schema=schema,
    output_schema?,
    annotations?,
    fn(arguments) raise McpError {
      let json = match arguments {
        Some(value) => value
        None => Json::null()
      }
      let input : A = @json.from_json(json) catch {
        error => raise InvalidParams(error.to_string())
      }
      handler(input)
    },
  )
}

///|
/// Register a resource by URI.
pub fn Server::resource(
  self : Server,
  uri~ : String,
  name? : String,
  title? : String,
  description? : String,
  mime_type? : String,
  handler : ResourceHandler,
) -> Unit raise McpError {
  let resource_name = match name {
    Some(name) => name
    None => uri
  }
  self.register_resource(
    Resource(uri~, name=resource_name, title?, description?, mime_type?),
    handler,
  )
}

///|
/// Register a resource template descriptor for `resources/templates/list`.
pub fn Server::resource_template(
  self : Server,
  uri_template~ : String,
  name? : String,
  title? : String,
  description? : String,
  mime_type? : String,
) -> Unit raise McpError {
  let template_name = match name {
    Some(name) => name
    None => uri_template
  }
  self.register_resource_template(
    ResourceTemplate(
      uri_template~,
      name=template_name,
      title?,
      description?,
      mime_type?,
    ),
  )
}

///|
/// Register a prompt whose arguments are exposed as strings.
pub fn Server::string_prompt(
  self : Server,
  name~ : String,
  title? : String,
  description? : String,
  arguments? : Array[PromptArgument] = [],
  handler : (Map[String, String]) -> GetPromptResult raise McpError,
) -> Unit raise McpError {
  self.register_prompt(Prompt(name~, title?, description?, arguments~), fn(
    arguments,
  ) raise McpError {
    handler(arguments).to_json()
  })
}

///|
/// Register a prompt that decodes string arguments through `FromJson`.
///
/// If `arguments` is omitted, the descriptors come from
/// `A::prompt_arguments()`.
pub fn[A : FromJson + PromptArguments] Server::prompt(
  self : Server,
  name~ : String,
  title? : String,
  description? : String,
  arguments? : Array[PromptArgument],
  handler : (A) -> GetPromptResult raise McpError,
) -> Unit raise McpError {
  let prompt_arguments = match arguments {
    Some(arguments) => arguments
    None => A::prompt_arguments()
  }
  self.string_prompt(name~, title?, description?, arguments=prompt_arguments, fn(
    arguments,
  ) raise McpError {
    let input : A = @json.from_json(prompt_arguments_json(arguments)) catch {
      error => raise InvalidParams(error.to_string())
    }
    handler(input)
  })
}

///|
/// Register a completion handler for one prompt or resource-template reference.
pub fn Server::completion(
  self : Server,
  reference~ : CompletionReference,
  handler : CompletionHandler,
) -> Unit raise McpError {
  let key = completion_key(reference)
  if self.completions.contains(key) {
    raise InvalidParams("completion already registered: \{key}")
  }
  self.completions[key] = handler
}

///|
fn parse_string_array(
  value : Json,
  context : String,
) -> Array[String] raise McpError {
  match value {
    Array(values) => {
      let strings : Array[String] = []
      for value in values {
        match value {
          String(value) => strings.push(value)
          _ => raise InvalidParams("\{context} items must be strings")
        }
      }
      strings
    }
    _ => raise InvalidParams("\{context} must be an array")
  }
}

///|
fn parse_icon(value : Json, context : String) -> Icon raise McpError {
  let fields = expect_object(value, context)
  let sizes = match fields.get("sizes") {
    Some(value) => parse_string_array(value, "\{context}.sizes")
    None => []
  }
  Icon(
    src=get_string(fields, "src", context),
    mime_type?=get_optional_string(fields, "mimeType", context),
    sizes~,
  )
}

///|
fn parse_icons(
  fields : Map[String, Json],
  context : String,
) -> Array[Icon] raise McpError {
  match fields.get("icons") {
    Some(Array(values)) => {
      let icons : Array[Icon] = []
      for i, value in values {
        icons.push(parse_icon(value, "\{context}.icons[\{i}]"))
      }
      icons
    }
    Some(Null) | None => []
    Some(_) => raise InvalidParams("\{context}.icons must be an array")
  }
}

///|
fn parse_implementation(
  value : Json,
  context : String,
) -> Implementation raise McpError {
  let fields = expect_object(value, context)
  Implementation(
    name=get_string(fields, "name", context),
    version=get_string(fields, "version", context),
    title?=get_optional_string(fields, "title", context),
    description?=get_optional_string(fields, "description", context),
    icons=parse_icons(fields, context),
    website_url?=get_optional_string(fields, "websiteUrl", context),
  )
}

///|
fn parse_initialize_params(params : Json?) -> InitializeParams raise McpError {
  let value = match params {
    Some(value) => value
    None => raise InvalidParams("initialize params are required")
  }
  let fields = expect_object(value, "initialize params")
  {
    protocol_version: get_string(fields, "protocolVersion", "initialize params"),
    capabilities: match fields.get("capabilities") {
      Some(value) => parse_client_capabilities(value)
      None => ClientCapabilities::empty()
    },
    client_info: match fields.get("clientInfo") {
      Some(value) => parse_implementation(value, "initialize params.clientInfo")
      None => raise InvalidParams("initialize params.clientInfo is required")
    },
    meta: match fields.get("_meta") {
      Some(value) => Some(value)
      None => None
    },
  }
}

///|
/// Handle MCP `initialize` params and return the negotiated server capabilities.
///
/// Lifecycle source:
/// https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle
pub fn Server::initialize(
  self : Server,
  params : Json?,
) -> InitializeResult raise McpError {
  match self.state {
    Created => ()
    InitializeResponded | Ready =>
      raise InvalidRequest("initialize must only be sent once")
  }
  let params = parse_initialize_params(params)
  let protocol_version = if params.protocol_version == latest_protocol_version {
    params.protocol_version
  } else {
    latest_protocol_version
  }
  self.protocol_version = Some(protocol_version)
  self.client_capabilities = Some(params.capabilities)
  self.client_info = Some(params.client_info)
  self.state = InitializeResponded
  {
    protocol_version,
    capabilities: self.capabilities,
    server_info: self.info,
    instructions: self.instructions,
    meta: None,
  }
}

///|
pub fn Server::notify_initialized(self : Server) -> Unit raise McpError {
  match self.state {
    InitializeResponded => self.state = Ready
    Created =>
      raise InvalidRequest(
        "notifications/initialized received before initialize",
      )
    Ready => ()
  }
}

///|
pub fn Server::is_initialized(self : Server) -> Bool {
  self.state is Ready
}

///|
pub fn Server::negotiated_protocol_version(self : Server) -> String? {
  self.protocol_version
}

///|
pub fn Server::client_capabilities(self : Server) -> ClientCapabilities? {
  self.client_capabilities
}

///|
pub fn Server::client_info(self : Server) -> Implementation? {
  self.client_info
}

///|
pub fn Server::logging_level(self : Server) -> LoggingLevel {
  self.logging_level
}

///|
fn Server::list_tools(self : Server, params : Json?) -> Json raise McpError {
  let cursor = get_cursor(params, "tools/list params")
  let page = paginate(
    Array::from_iter(
      self.tools.values().map(fn(registered) { registered.tool }),
    ),
    cursor?,
  )
  let fields : Map[String, Json] = {
    "tools": page.items.map(fn(tool) { tool.to_json() }).to_json(),
  }
  put_next_cursor(fields, page.next_cursor)
  Json::object(fields)
}

///|
fn Server::list_resources(self : Server, params : Json?) -> Json raise McpError {
  let cursor = get_cursor(params, "resources/list params")
  let page = paginate(
    Array::from_iter(
      self.resources.values().map(fn(registered) { registered.resource }),
    ),
    cursor?,
  )
  let fields : Map[String, Json] = {
    "resources": page.items.map(fn(resource) { resource.to_json() }).to_json(),
  }
  put_next_cursor(fields, page.next_cursor)
  Json::object(fields)
}

///|
fn Server::list_resource_templates(
  self : Server,
  params : Json?,
) -> Json raise McpError {
  let cursor = get_cursor(params, "resources/templates/list params")
  let page = paginate(
    Array::from_iter(
      self.resource_templates
      .values()
      .map(fn(registered) { registered.template }),
    ),
    cursor?,
  )
  let fields : Map[String, Json] = {
    "resourceTemplates": page.items
    .map(fn(template) { template.to_json() })
    .to_json(),
  }
  put_next_cursor(fields, page.next_cursor)
  Json::object(fields)
}

///|
fn Server::read_resource(
  self : Server,
  params : Json?,
) -> ReadResourceResult raise McpError {
  let value = match params {
    Some(value) => value
    None => raise InvalidParams("resources/read params are required")
  }
  let fields = expect_object(value, "resources/read params")
  let uri = get_string(fields, "uri", "resources/read params")
  match self.resources.get(uri) {
    Some(registered) => (registered.handler)(uri)
    None => raise ResourceNotFound(uri)
  }
}

///|
fn Server::resource_subscribe_supported(self : Server) -> Bool {
  if self.capabilities.resources is Some(resources) {
    resources.subscribe == Some(true)
  } else {
    false
  }
}

///|
fn parse_resource_uri_params(
  params : Json?,
  context : String,
) -> String raise McpError {
  let value = match params {
    Some(value) => value
    None => raise InvalidParams("\{context} params are required")
  }
  get_string(
    expect_object(value, "\{context} params"),
    "uri",
    "\{context} params",
  )
}

///|
fn Server::subscribe_resource(
  self : Server,
  params : Json?,
) -> Unit raise McpError {
  if !self.resource_subscribe_supported() {
    raise MethodNotFound("resources/subscribe")
  }
  let uri = parse_resource_uri_params(params, "resources/subscribe")
  if !self.resources.contains(uri) {
    raise ResourceNotFound(uri)
  }
  self.resource_subscriptions[uri] = true
}

///|
fn Server::unsubscribe_resource(
  self : Server,
  params : Json?,
) -> Unit raise McpError {
  if !self.resource_subscribe_supported() {
    raise MethodNotFound("resources/unsubscribe")
  }
  let uri = parse_resource_uri_params(params, "resources/unsubscribe")
  self.resource_subscriptions.remove(uri)
}

///|
pub fn Server::is_resource_subscribed(self : Server, uri~ : String) -> Bool {
  self.resource_subscriptions.contains(uri)
}

///|
pub fn Server::resource_updated_notification(
  self : Server,
  uri~ : String,
) -> Json? {
  if self.is_resource_subscribed(uri~) {
    Some(resource_updated_notification(uri~))
  } else {
    None
  }
}

///|
fn Server::list_prompts(self : Server, params : Json?) -> Json raise McpError {
  let cursor = get_cursor(params, "prompts/list params")
  let page = paginate(
    Array::from_iter(
      self.prompts.values().map(fn(registered) { registered.prompt }),
    ),
    cursor?,
  )
  let fields : Map[String, Json] = {
    "prompts": page.items.map(fn(prompt) { prompt.to_json() }).to_json(),
  }
  put_next_cursor(fields, page.next_cursor)
  Json::object(fields)
}

///|
fn get_prompt_arguments(
  params : Map[String, Json],
) -> Map[String, String] raise McpError {
  let arguments : Map[String, String] = {}
  match params.get("arguments") {
    Some(Object(raw)) =>
      for key, value in raw {
        match value {
          String(value) => arguments[key] = value
          _ => raise InvalidParams("prompts/get arguments must be strings")
        }
      }
    Some(Null) | None => ()
    Some(_) => raise InvalidParams("prompts/get arguments must be an object")
  }
  arguments
}

///|
fn prompt_arguments_json(arguments : Map[String, String]) -> Json {
  let fields : Map[String, Json] = {}
  for key, value in arguments {
    fields[key] = Json::string(value)
  }
  Json::object(fields)
}

///|
fn Server::get_prompt(self : Server, params : Json?) -> Json raise McpError {
  let value = match params {
    Some(value) => value
    None => raise InvalidParams("prompts/get params are required")
  }
  let fields = expect_object(value, "prompts/get params")
  let name = get_string(fields, "name", "prompts/get params")
  let arguments = get_prompt_arguments(fields)
  match self.prompts.get(name) {
    Some(registered) => (registered.handler)(arguments)
    None => raise InvalidParams("unknown prompt: \{name}")
  }
}

///|
fn Server::call_tool(
  self : Server,
  params : Json?,
) -> CallToolResult raise McpError {
  let value = match params {
    Some(value) => value
    None => raise InvalidParams("tools/call params are required")
  }
  let fields = expect_object(value, "tools/call params")
  let name = get_string(fields, "name", "tools/call params")
  let arguments = get_optional_object(fields, "arguments", "tools/call params")
  match self.tools.get(name) {
    Some(registered) => (registered.handler)(arguments)
    None => raise InvalidParams("unknown tool: \{name}")
  }
}

///|
fn completion_key(reference : CompletionReference) -> String {
  match reference {
    PromptRef(name~) => "prompt:\{name}"
    ResourceRef(uri~) => "resource:\{uri}"
  }
}

///|
fn Server::complete(
  self : Server,
  params : Json?,
) -> CompleteResult raise McpError {
  let request = parse_completion_request(params)
  let key = completion_key(request.reference)
  match self.completions.get(key) {
    Some(handler) => handler(request)
    None => raise InvalidParams("no completion handler registered for \{key}")
  }
}

///|
fn Server::set_logging_level(
  self : Server,
  params : Json?,
) -> Unit raise McpError {
  let value = match params {
    Some(value) => value
    None => raise InvalidParams("logging/setLevel params are required")
  }
  let fields = expect_object(value, "logging/setLevel params")
  self.logging_level = parse_logging_level(
    match fields.get("level") {
      Some(value) => value
      None => raise InvalidParams("logging/setLevel params.level is required")
    },
  )
}

///|
fn Server::ensure_method_allowed(
  self : Server,
  method_name : String,
) -> Unit raise McpError {
  match self.state {
    Created =>
      match method_name {
        "initialize" | "ping" => ()
        _ => raise InvalidRequest("initialize must be the first MCP request")
      }
    InitializeResponded =>
      match method_name {
        "notifications/initialized" | "ping" => ()
        _ =>
          raise InvalidRequest(
            "notifications/initialized is required before normal operation",
          )
      }
    Ready =>
      match method_name {
        "initialize" =>
          raise InvalidRequest("initialize must only be sent once")
        _ => ()
      }
  }
}

///|
/// Dispatch an MCP method and return the JSON result, if the method has one.
fn Server::dispatch(
  self : Server,
  method_name : String,
  params : Json?,
) -> Json? raise McpError {
  self.ensure_method_allowed(method_name)
  match method_name {
    "initialize" => Some(self.initialize(params).to_json())
    "notifications/initialized" => {
      self.notify_initialized()
      None
    }
    "notifications/cancelled" => None
    "ping" => Some(empty_result())
    "logging/setLevel" => {
      self.set_logging_level(params)
      Some(empty_result())
    }
    "tools/list" => Some(self.list_tools(params))
    "tools/call" => Some(self.call_tool(params).to_json())
    "resources/list" => Some(self.list_resources(params))
    "resources/templates/list" => Some(self.list_resource_templates(params))
    "resources/read" => Some(self.read_resource(params).to_json())
    "resources/subscribe" => {
      self.subscribe_resource(params)
      Some(empty_result())
    }
    "resources/unsubscribe" => {
      self.unsubscribe_resource(params)
      Some(empty_result())
    }
    "prompts/list" => Some(self.list_prompts(params))
    "prompts/get" => Some(self.get_prompt(params))
    "completion/complete" => Some(self.complete(params).to_json())
    _ => raise MethodNotFound(method_name)
  }
}
