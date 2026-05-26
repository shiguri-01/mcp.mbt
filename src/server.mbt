///|
type ToolHandler = (Json?) -> CallToolResult raise McpError

///|
type ResourceHandler = (String) -> ReadResourceResult raise McpError

///|
type PromptHandler = (Map[String, String]) -> Json raise McpError

///|
struct RegisteredTool {
  tool : Tool
  handler : ToolHandler
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
  priv prompts : Map[String, RegisteredPrompt]
  priv mut initialized : Bool
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
    prompts: {},
    initialized: false,
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
fn Server::list_tools(self : Server) -> Json {
  Json::object({
    "tools": self.tools
    .values()
    .map(fn(registered) { registered.tool.to_json() })
    .to_json(),
  })
}

///|
fn Server::list_resources(self : Server) -> Json {
  Json::object({
    "resources": self.resources
    .values()
    .map(fn(registered) { registered.resource.to_json() })
    .to_json(),
  })
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
fn Server::list_prompts(self : Server) -> Json {
  Json::object({
    "prompts": self.prompts
    .values()
    .map(fn(registered) { registered.prompt.to_json() })
    .to_json(),
  })
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
    "tools/list" => Some(self.list_tools())
    "tools/call" => Some(self.call_tool(params).to_json())
    "resources/list" => Some(self.list_resources())
    "resources/read" => Some(self.read_resource(params).to_json())
    "prompts/list" => Some(self.list_prompts())
    "prompts/get" => Some(self.get_prompt(params))
    _ => raise MethodNotFound(method_name)
  }
}
