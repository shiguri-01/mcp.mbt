///|
type ToolHandler = (Json?) -> CallToolResult raise McpError

///|
type ResourceHandler = (String) -> ReadResourceResult raise McpError

///|
type PromptHandler = (Map[String, String]) -> Json raise McpError

///|
type CompletionHandler = (CompletionRequest) -> CompleteResult raise McpError

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
  priv tools : Map[String, RegisteredTool]
  priv resources : Map[String, RegisteredResource]
  priv resource_templates : Map[String, RegisteredResourceTemplate]
  priv prompts : Map[String, RegisteredPrompt]
  priv completions : Map[String, CompletionHandler]
  priv mut initialized : Bool
  priv mut logging_level : LoggingLevel
}

///|
/// Create a transport-neutral MCP server dispatcher.
pub fn Server::Server(
  name~ : String,
  version~ : String,
  instructions? : String,
  capabilities? : ServerCapabilities = ServerCapabilities::full(),
) -> Server {
  {
    info: { name, version },
    capabilities,
    instructions,
    tools: {},
    resources: {},
    resource_templates: {},
    prompts: {},
    completions: {},
    initialized: false,
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
/// Handle MCP `initialize` params and return the server capabilities.
pub fn Server::initialize(self : Server, _params : Json?) -> InitializeResult {
  self.initialized = true
  {
    protocol_version: latest_protocol_version,
    capabilities: self.capabilities,
    server_info: self.info,
    instructions: self.instructions,
    meta: None,
  }
}

///|
pub fn Server::notify_initialized(self : Server) -> Unit {
  self.initialized = true
}

///|
pub fn Server::is_initialized(self : Server) -> Bool {
  self.initialized
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
    None => raise InvalidParams("unknown resource: \{uri}")
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
/// Dispatch an MCP method and return the JSON result, if the method has one.
fn Server::dispatch(
  self : Server,
  method_name : String,
  params : Json?,
) -> Json? raise McpError {
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
    "prompts/list" => Some(self.list_prompts(params))
    "prompts/get" => Some(self.get_prompt(params))
    "completion/complete" => Some(self.complete(params).to_json())
    _ => raise MethodNotFound(method_name)
  }
}
