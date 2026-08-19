///|
pub type ToolHandler = async (@mcp.RequestContext, Json) -> @mcp.HandlerOutcome[
  @mcp.CallToolResult,
] raise @mcp.McpError

///|
pub type ResourceHandler = async (@mcp.RequestContext, String) -> @mcp.HandlerOutcome[
  @mcp.ReadResourceResult,
] raise @mcp.McpError

///|
pub type PromptHandler = async (@mcp.RequestContext, Map[String, String]) -> @mcp.HandlerOutcome[
  @mcp.GetPromptResult,
] raise @mcp.McpError

///|
pub type CompletionHandler = async (@mcp.RequestContext, @mcp.CompletionRequest) -> @mcp.CompleteResult raise @mcp.McpError

///|
pub type RawHandler = async (@mcp.RequestContext, Json) -> @mcp.HandlerOutcome[
  Json,
] raise @mcp.McpError

///|
priv struct RegisteredTool {
  tool : @mcp.Tool
  handler : ToolHandler
  input_validator : @schema.Schema
  output_validator : @schema.Schema?
}

///|
fn compile_tool_schema(value : Json) -> @schema.Schema raise @mcp.McpError {
  @schema.Schema::from_json(value) catch {
    _ => raise @mcp.InvalidParams("invalid JSON Schema document")
  }
}

///|
fn schema_validation_error(validator : @schema.Schema, value : Json) -> String? {
  try {
    validator.validate(value)
    None
  } catch {
    ValidationIssues(issues) => Some(issues.to_json().stringify())
  }
}

///|
priv struct RegisteredResource {
  resource : @mcp.Resource
  handler : ResourceHandler
}

///|
priv struct RegisteredResourceTemplate {
  template : @mcp.ResourceTemplate
  matcher : Regex
  variables : Array[String]
  handler : async (@mcp.RequestContext, String, Map[String, String]) -> @mcp.HandlerOutcome[
    @mcp.ReadResourceResult,
  ] raise @mcp.McpError
}

///|
let template_var_segment_regex : Regex = re"[^/?#]+"

///|
let template_placeholder_regex : Regex = re"[{]([a-zA-Z0-9_]+)[}]"

///|
fn compile_resource_template(
  template : String,
) -> (Regex, Array[String]) raise @mcp.McpError {
  let remaining = template_placeholder_regex.replace_by(template, _ => "")
  if remaining.contains("{") || remaining.contains("}") {
    raise @mcp.InvalidParams(
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
      raise @mcp.InvalidParams(
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
priv struct RegisteredPrompt {
  prompt : @mcp.Prompt
  handler : PromptHandler
}

///|
fn[A : @schema.JsonSchema] schema_for(
  _witness : A?,
) -> Json raise @mcp.McpError {
  let schema = A::json_schema() catch {
    _ => raise @mcp.InvalidParams("typed tool produced an invalid JSON Schema")
  }
  schema.to_json()
}

///|
fn Server::install_tool(
  self : Server,
  tool : @mcp.Tool,
  handler : ToolHandler,
) -> Unit raise @mcp.McpError {
  self.ensure_registering()
  if self.tools.contains(tool.name) {
    raise @mcp.InvalidParams("tool already registered: \{tool.name}")
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
pub fn Server::tool_descriptor(self : Server, name : String) -> @mcp.Tool? {
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
  annotations? : @mcp.ToolAnnotations,
  icons? : Array[@mcp.Icon] = [],
  meta? : Map[String, Json] = {},
  handler : async (@mcp.RequestContext, A) -> @mcp.HandlerOutcome[
    @mcp.CallToolResult,
  ] raise @mcp.McpError,
) -> Unit raise @mcp.McpError {
  let schema = match input_schema {
    Some(value) => value
    None => schema_for((None : A?))
  }
  let tool = @mcp.Tool(
    name~,
    title?,
    description?,
    input_schema=schema,
    output_schema?,
    annotations?,
    icons~,
    meta~,
  )
  self.install_tool(tool, async fn(
    context,
    arguments,
  ) -> @mcp.HandlerOutcome[@mcp.CallToolResult] raise @mcp.McpError {
    let decoded : A = @json.from_json(arguments) catch {
      error =>
        return @mcp.Complete(
          @mcp.CallToolResult::error_text("Invalid tool arguments: \{error}"),
        )
    }
    handler(context, decoded)
  })
}

///|
/// Register a tool whose arguments and result are handled as raw JSON.
/// This is the explicit escape hatch; typed tools should use `tool`.
pub fn Server::tool_raw(
  self : Server,
  name~ : String,
  title? : String,
  description? : String,
  input_schema? : Json = Json::object({ "type": Json::string("object") }),
  output_schema? : Json,
  annotations? : @mcp.ToolAnnotations,
  icons? : Array[@mcp.Icon] = [],
  meta? : Map[String, Json] = {},
  handler : ToolHandler,
) -> Unit raise @mcp.McpError {
  self.install_tool(
    @mcp.Tool(
      name~,
      title?,
      description?,
      input_schema~,
      output_schema?,
      annotations?,
      icons~,
      meta~,
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
  icons? : Array[@mcp.Icon] = [],
  annotations? : @mcp.Annotations,
  size? : Int64,
  meta? : Map[String, Json] = {},
  handler : async (@mcp.RequestContext, String) -> @mcp.HandlerOutcome[
    @mcp.ReadResourceResult,
  ] raise @mcp.McpError,
) -> Unit raise @mcp.McpError {
  self.ensure_registering()
  if self.resources.contains(uri) {
    raise @mcp.InvalidParams("resource already registered: \{uri}")
  }
  self.resources[uri] = {
    resource: @mcp.Resource(
      uri~,
      name=name.unwrap_or(uri),
      title?,
      description?,
      mime_type?,
      icons~,
      annotations?,
      size?,
      meta~,
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
  icons? : Array[@mcp.Icon] = [],
  annotations? : @mcp.Annotations,
  meta? : Map[String, Json] = {},
  handler : async (@mcp.RequestContext, String, Map[String, String]) -> @mcp.HandlerOutcome[
    @mcp.ReadResourceResult,
  ] raise @mcp.McpError,
) -> Unit raise @mcp.McpError {
  self.ensure_registering()
  if self.resource_templates.contains(uri_template) {
    raise @mcp.InvalidParams(
      "resource template already registered: \{uri_template}",
    )
  }
  let (matcher, variables) = compile_resource_template(uri_template)
  self.resource_templates[uri_template] = {
    template: @mcp.ResourceTemplate(
      uri_template~,
      name=name.unwrap_or(uri_template),
      title?,
      description?,
      mime_type?,
      icons~,
      annotations?,
      meta~,
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
  arguments? : Array[@mcp.PromptArgument] = [],
  icons? : Array[@mcp.Icon] = [],
  meta? : Map[String, Json] = {},
  handler : async (@mcp.RequestContext, Map[String, String]) -> @mcp.HandlerOutcome[
    @mcp.GetPromptResult,
  ] raise @mcp.McpError,
) -> Unit raise @mcp.McpError {
  self.ensure_registering()
  if self.prompts.contains(name) {
    raise @mcp.InvalidParams("prompt already registered: \{name}")
  }
  self.prompts[name] = {
    prompt: @mcp.Prompt(name~, title?, description?, arguments~, icons~, meta~),
    handler,
  }
}

///|
fn completion_key(reference : @mcp.CompletionReference) -> String {
  match reference {
    @mcp.PromptRef(name~, ..) => "prompt:\{name}"
    @mcp.ResourceRef(uri~) => "resource:\{uri}"
  }
}

///|
pub fn Server::completion(
  self : Server,
  reference~ : @mcp.CompletionReference,
  handler : CompletionHandler,
) -> Unit raise @mcp.McpError {
  self.ensure_registering()
  let key = completion_key(reference)
  if self.completions.contains(key) {
    raise @mcp.InvalidParams("completion already registered: \{key}")
  }
  self.completions[key] = handler
}

///|
/// Register a negotiated extension method.
pub fn Server::on(
  self : Server,
  method_name~ : String,
  handler : RawHandler,
) -> Unit raise @mcp.McpError {
  self.ensure_registering()
  if self.raw_handlers.contains(method_name) {
    raise @mcp.InvalidParams("method already registered: \{method_name}")
  }
  self.raw_handlers[method_name] = handler
}
