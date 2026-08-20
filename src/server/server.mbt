///|
fn Json::copy(self : Json) -> Json {
  match self {
    Object(fields) => {
      let copied : Map[String, Json] = Map([])
      for key, value in fields {
        copied[key] = value.copy()
      }
      Json::object(copied)
    }
    Array(values) => Json::array(values.map(fn(v) { v.copy() }))
    _ => self
  }
}

///|
fn Map::copy_json(self : Map[String, Json]) -> Map[String, Json] {
  let copied : Map[String, Json] = Map([])
  for key, value in self {
    copied[key] = value.copy()
  }
  copied
}

///|
fn[K : Eq + Hash, V] Map::set_opt(
  self : Map[K, V],
  key : K,
  value : V?,
) -> Unit {
  if value is Some(v) {
    self[key] = v
  }
}

///|
/// A transport-neutral, stateless MCP 2026-07-28 server builder.
pub struct ServerBuilder {
  priv info : @mcp.Implementation
  priv instructions : String?
  priv cache_policy : @mcp.CachePolicy
  priv supported_versions : Array[String]
  priv tools : Map[String, RegisteredTool]
  priv tool_schemas : Map[String, @mcp.Tool]
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
pub fn ServerBuilder::ServerBuilder(
  name~ : String,
  version~ : String,
  title? : String,
  description? : String,
  icons? : Array[@mcp.Icon] = [],
  website_url? : String,
  instructions? : String,
  cache_policy? : @mcp.CachePolicy,
  supported_versions? : Array[String] = [@mcp.PROTOCOL_VERSION],
  tool_list_changed? : Bool = false,
  resource_list_changed? : Bool = false,
  prompt_list_changed? : Bool = false,
  resource_subscriptions? : Bool = false,
  extensions? : Map[String, Json] = Map([]),
  extension_result_types? : Map[String, String] = Map([]),
  experimental? : Map[String, Json] = Map([]),
) -> ServerBuilder raise @mcp.McpError {
  if name.is_empty() || version.is_empty() {
    raise @mcp.InvalidParams("server name and version must not be empty")
  }
  if supported_versions.is_empty() ||
    supported_versions.any(fn(value) { value.is_empty() }) {
    raise @mcp.InvalidParams("supported_versions must not be empty")
  }
  validate_extension_map(extensions)
  validate_extension_result_types(extension_result_types, extensions)
  {
    info: @mcp.Implementation(
      name~,
      version~,
      title?,
      description?,
      icons~,
      website_url?,
    ),
    instructions,
    cache_policy: cache_policy.unwrap_or(
      @mcp.CachePolicy(ttl_ms=0L, scope=@mcp.Private),
    ),
    supported_versions: supported_versions.copy(),
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
/// Finalize configuration and construct an immutable Server.
pub fn ServerBuilder::build(self : ServerBuilder) -> Server {
  {
    info: self.info,
    instructions: self.instructions,
    cache_policy: self.cache_policy,
    supported_versions: self.supported_versions.copy(),
    tools: self.tools,
    tool_schemas: self.tool_schemas,
    resources: self.resources,
    resource_templates: self.resource_templates,
    prompts: self.prompts,
    completions: self.completions,
    raw_handlers: self.raw_handlers,
    tool_list_changed: self.tool_list_changed,
    resource_list_changed: self.resource_list_changed,
    prompt_list_changed: self.prompt_list_changed,
    resource_subscriptions: self.resource_subscriptions,
    extensions: self.extensions.copy_json(),
    extension_result_types: self.extension_result_types.copy(),
    experimental: self.experimental.copy_json(),
  }
}

///|
/// A transport-neutral, stateless MCP 2026-07-28 server.
///
/// Per-client protocol state is carried exclusively by `RequestContext`
/// and is never stored on this value.
pub struct Server {
  priv info : @mcp.Implementation
  priv instructions : String?
  priv cache_policy : @mcp.CachePolicy
  priv supported_versions : Array[String]
  priv tools : Map[String, RegisteredTool]
  priv tool_schemas : Map[String, @mcp.Tool]
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
fn Server::capabilities(self : Server) -> @mcp.ServerCapabilities {
  @mcp.ServerCapabilities(
    tools?=if self.tools.is_empty() {
      None
    } else {
      Some(@mcp.ToolsCapability(list_changed=self.tool_list_changed))
    },
    resources?=if self.resources.is_empty() &&
      self.resource_templates.is_empty() {
      None
    } else {
      Some(
        @mcp.ResourcesCapability(
          subscribe=self.resource_subscriptions,
          list_changed=self.resource_list_changed,
        ),
      )
    },
    prompts?=if self.prompts.is_empty() {
      None
    } else {
      Some(@mcp.PromptsCapability(list_changed=self.prompt_list_changed))
    },
    completions=!self.completions.is_empty(),
    extensions=self.extensions,
    experimental=self.experimental,
  )
}

///|
fn Server::ensure_supported_version(
  self : Server,
  context : @mcp.RequestContext,
) -> Unit raise @mcp.McpError {
  let requested = context.meta.protocol_version
  if !self.supported_versions.contains(requested) {
    raise @mcp.UnsupportedProtocolVersion(
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
fn valid_extension_identifier(identifier : String) -> Bool {
  let length = identifier.length()
  if length < 3 || length > 255 {
    return false
  }
  let mut slash_index = -1
  for index in 0..<length {
    let char = identifier[index]
    if char == '/' {
      if slash_index != -1 {
        return false
      }
      slash_index = index
    }
  }
  if slash_index <= 0 || slash_index == length - 1 {
    return false
  }
  let vendor = identifier[0:slash_index].to_owned()
  let name = identifier[slash_index + 1:].to_owned()
  let valid_segment = fn(seg : String) {
    if seg.is_empty() {
      return false
    }
    for c in seg {
      let ok = (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') ||
        c == '-' ||
        c == '.'
      if !ok {
        return false
      }
    }
    true
  }
  valid_segment(vendor) && valid_segment(name)
}

///|
fn validate_extension_map(
  values : Map[String, Json],
) -> Unit raise @mcp.McpError {
  for key, _ in values {
    if !valid_extension_identifier(key) {
      raise @mcp.InvalidParams(
        "extension '\{key}': not a valid extension identifier",
      )
    }
  }
}

///|
fn validate_extension_result_types(
  result_types : Map[String, String],
  extensions : Map[String, Json],
) -> Unit raise @mcp.McpError {
  for result_type, extension in result_types {
    if !extensions.contains(extension) {
      raise @mcp.InvalidParams(
        "extension resultType '\{result_type}' requires declared extension capability '\{extension}'",
      )
    }
  }
}
