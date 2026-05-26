///|
type ToolHandler = (Json?) -> CallToolResult raise McpError

///|
struct RegisteredTool {
  tool : Tool
  handler : ToolHandler
}

///|
pub struct Server {
  priv info : Implementation
  priv capabilities : ServerCapabilities
  priv instructions : String?
  priv tools : Map[String, RegisteredTool]
  priv mut initialized : Bool
}

///|
pub fn Server::new(
  name~ : String,
  version~ : String,
  instructions? : String,
  capabilities? : ServerCapabilities = ServerCapabilities::tools_only(),
) -> Server {
  {
    info: { name, version },
    capabilities,
    instructions,
    tools: {},
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
    _ => raise MethodNotFound(method_name)
  }
}
