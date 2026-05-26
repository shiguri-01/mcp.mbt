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
pub fn Server::new(
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
pub fn Server::add_tool_raw(
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
pub fn[A : FromJson, B : ToJson] Server::add_tool(
  self : Server,
  tool : Tool,
  handler : (A) -> B raise McpError,
) -> Unit raise McpError {
  self.add_tool_raw(tool, fn(arguments) raise McpError {
    let json = match arguments {
      Some(value) => value
      None => Json::null()
    }
    let input : A = @json.from_json(json) catch {
      error => raise InvalidParams(error.to_string())
    }
    CallToolResult::json(handler(input).to_json())
  })
}

///|
pub fn[A : FromJson, B : ToJson] Server::tool_json(
  self : Server,
  name~ : String,
  title? : String,
  description? : String,
  input_schema? : Json = empty_object_schema(),
  output_schema? : Json,
  annotations? : ToolAnnotations,
  handler : (A) -> B raise McpError,
) -> Unit raise McpError {
  self.add_tool(
    {
      name,
      title,
      description,
      input_schema,
      output_schema,
      annotations,
      meta: None,
    },
    handler,
  )
}

///|
pub fn Server::add_text_tool(
  self : Server,
  tool : Tool,
  handler : (Json?) -> String raise McpError,
) -> Unit raise McpError {
  self.add_tool_raw(tool, fn(arguments) raise McpError {
    CallToolResult::text(handler(arguments))
  })
}

///|
pub fn Server::tool_text(
  self : Server,
  name~ : String,
  title? : String,
  description? : String,
  input_schema? : Json = empty_object_schema(),
  annotations? : ToolAnnotations,
  handler : (Json?) -> String raise McpError,
) -> Unit raise McpError {
  self.add_text_tool(
    {
      name,
      title,
      description,
      input_schema,
      output_schema: None,
      annotations,
      meta: None,
    },
    handler,
  )
}

///|
pub fn Server::add_resource(
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
pub fn Server::add_text_resource(
  self : Server,
  resource : Resource,
  handler : (String) -> String raise McpError,
) -> Unit raise McpError {
  self.add_resource(resource, fn(uri) raise McpError {
    {
      contents: [
        ResourceText(uri~, text=handler(uri), mime_type=resource.mime_type),
      ],
      meta: None,
    }
  })
}

///|
pub fn Server::resource_text(
  self : Server,
  uri~ : String,
  name? : String,
  title? : String,
  description? : String,
  mime_type? : String = "text/plain",
  handler : (String) -> String raise McpError,
) -> Unit raise McpError {
  let resource_name = match name {
    Some(name) => name
    None => uri
  }
  self.add_text_resource(
    {
      uri,
      name: resource_name,
      title,
      description,
      mime_type: Some(mime_type),
      meta: None,
    },
    handler,
  )
}

///|
pub fn Server::add_prompt_raw(
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
pub fn Server::add_prompt_result(
  self : Server,
  prompt : Prompt,
  handler : (Map[String, String]) -> GetPromptResult raise McpError,
) -> Unit raise McpError {
  self.add_prompt_raw(prompt, fn(arguments) raise McpError {
    handler(arguments).to_json()
  })
}

///|
pub fn Server::add_prompt(
  self : Server,
  prompt : Prompt,
  handler : (Map[String, String]) -> String raise McpError,
) -> Unit raise McpError {
  self.add_prompt_raw(prompt, fn(arguments) raise McpError {
    let description = match prompt.description {
      Some(description) => description
      None => ""
    }
    Json::object({
      "description": Json::string(description),
      "messages": Json::array([
        Json::object({
          "role": Json::string("user"),
          "content": ContentBlock::Text(handler(arguments)).to_json(),
        }),
      ]),
    })
  })
}

///|
pub fn Server::prompt_text(
  self : Server,
  name~ : String,
  title? : String,
  description? : String,
  arguments? : Array[PromptArgument] = [],
  handler : (Map[String, String]) -> String raise McpError,
) -> Unit raise McpError {
  self.add_prompt({ name, title, description, arguments, meta: None }, handler)
}

///|
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
pub fn Server::list_tools(self : Server) -> Json {
  Json::object({
    "tools": self.tools
    .values()
    .map(fn(registered) { registered.tool.to_json() })
    .to_json(),
  })
}

///|
pub fn Server::list_resources(self : Server) -> Json {
  Json::object({
    "resources": self.resources
    .values()
    .map(fn(registered) { registered.resource.to_json() })
    .to_json(),
  })
}

///|
pub fn Server::read_resource(
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
pub fn Server::list_prompts(self : Server) -> Json {
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
pub fn Server::get_prompt(self : Server, params : Json?) -> Json raise McpError {
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
pub fn Server::call_tool(
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
pub fn Server::handle(
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
