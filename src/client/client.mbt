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
/// Transport-neutral MCP 2026-07-28 request builder and response decoder.
///
/// The client keeps only defaults and a request-id counter. Every request is
/// self-contained and receives a fresh copy of protocol metadata.
pub struct Client {
  transport : &ClientTransport
  info : @mcp.Implementation
  capabilities : @mcp.ClientCapabilities
  extension_result_types : Map[String, String]
  protocol_version : String
  priv mut next_request_id : Int
}

///|
pub fn Client::Client(
  name~ : String,
  version~ : String,
  transport~ : &ClientTransport,
  title? : String,
  description? : String,
  icons? : Array[@mcp.Icon] = [],
  website_url? : String,
  capabilities? : @mcp.ClientCapabilities = @mcp.ClientCapabilities::empty(),
  extension_result_types? : Map[String, String] = Map([]),
  protocol_version? : String = @mcp.LATEST_PROTOCOL_VERSION,
) -> Client raise @mcp.McpError {
  if name.is_empty() || version.is_empty() || protocol_version.is_empty() {
    raise @mcp.InvalidParams(
      "client name, version, and protocol version must not be empty",
    )
  }
  validate_extension_map(capabilities.extensions)
  validate_extension_result_types(
    extension_result_types,
    capabilities.extensions,
  )
  {
    transport,
    info: @mcp.Implementation(
      name~,
      version~,
      title?,
      description?,
      icons~,
      website_url?,
    ),
    capabilities: capabilities.copy(),
    extension_result_types: extension_result_types.copy(),
    protocol_version,
    next_request_id: 1,
  }
}

///|
pub fn Client::close(self : Client) -> Unit {
  self.transport.close()
}

///|
fn Client::fresh_id(self : Client) -> @jsonrpc.RequestId {
  let id = self.next_request_id
  self.next_request_id += 1
  try! @jsonrpc.RequestId::number(id.to_double(), repr="\{id}")
}

///|
/// Decode a modern JSON-RPC response without treating unknown result types as
/// successful core results.
pub fn Client::decode_response(
  self : Client,
  message : Json,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  let outcome = @mcp.HandlerOutcome::decode_response(message)
  if outcome is ExtensionResult(result_type, _) &&
    !self.extension_result_types.contains(result_type) {
    raise @mcp.InvalidRequest("unknown resultType: \{result_type}")
  }
  outcome
}

///|
pub fn Client::decode_discover(
  self : Client,
  message : Json,
) -> @mcp.DiscoverResult raise @mcp.McpError {
  let outcome = self.decode_response(message)
  @mcp.DiscoverResult::from_json(
    outcome.require_complete(context="server/discover"),
  )
}

///|
fn validate_max_rounds(max_rounds : Int) -> Unit raise @mcp.McpError {
  if max_rounds <= 0 {
    raise @mcp.InvalidRequest("max_rounds must be positive")
  }
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
