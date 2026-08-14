///|
pub(all) suberror HttpHeaderError {
  InvalidHeaderSchema(String)
  InvalidHeaderValue(String)
  HeaderMismatch(String)
} derive(Debug, Eq)

///|
priv enum HeaderPrimitive {
  HeaderString
  HeaderInteger
  HeaderBoolean
}

///|
priv struct HeaderBinding {
  name : String
  path : Array[String]
  primitive : HeaderPrimitive
}

///|
fn header_entries(
  headers : Map[String, String],
  name : String,
) -> Array[String] {
  let expected = name.to_lower()
  [
    for key, value in headers if key.to_lower() == expected => value
  ]
}

///|
fn header(headers : Map[String, String], name : String) -> String? {
  header_entries(headers, name).get(0)
}

///|
fn unique_header(
  headers : Map[String, String],
  name : String,
) -> Result[String?, String] {
  match header_entries(headers, name) {
    [] => Ok(None)
    [value] => Ok(Some(value.trim(chars=" \t").to_owned()))
    _ => Err("Header mismatch: duplicate \{name} headers")
  }
}

///|
fn has_media_type(value : String, media_type : String) -> Bool {
  let expected = media_type.to_lower()
  for part in value.split(",") {
    let media = part.trim().to_lower()
    let token = match media.find(";") {
      Some(parameter_start) => media[:parameter_start].trim()
      None => media
    }
    if token == expected[:] {
      return true
    }
  }
  false
}

///|
fn plain_header_value_is_safe(value : String) -> Bool {
  if value.has_prefix("=?base64?"[:]) && value.has_suffix("?="[:]) {
    return false
  }
  if value.length() > 0 {
    let first = value[0]
    let last = value[value.length() - 1]
    if first is (' ' | '\t') || last is (' ' | '\t') {
      return false
    }
  }
  for char in value {
    let code = char.to_int()
    if code != 0x09 && (code < 0x20 || code > 0x7e) {
      return false
    }
  }
  true
}

///|
/// Encode an MCP HTTP metadata value using the 2026-07-28 Base64 sentinel
/// format when it cannot be carried as a safe plain HTTP field value.
pub fn encode_mcp_header_value(value : String) -> String {
  if plain_header_value_is_safe(value) {
    value
  } else {
    "=?base64?\{@base64.encode(@utf8.encode(value))}?="
  }
}

///|
/// Decode an MCP Base64 sentinel value, or return a safe plain value unchanged.
pub fn decode_mcp_header_value(value : String) -> String raise HttpHeaderError {
  if value.has_prefix("=?base64?"[:]) && value.has_suffix("?="[:]) {
    guard value.length() >= 11 else {
      raise InvalidHeaderValue("malformed MCP Base64 header value")
    }
    let payload = value[9:value.length() - 2]
    let bytes = @base64.decode(payload) catch {
      _ => raise InvalidHeaderValue("malformed MCP Base64 header value")
    }
    @utf8.decode(bytes) catch {
      _ => raise InvalidHeaderValue("MCP Base64 header value is not UTF-8")
    }
  } else if plain_header_value_is_safe(value) {
    value
  } else {
    raise InvalidHeaderValue("unsafe plain MCP header value")
  }
}

///|
fn is_http_token_char(char : Char) -> Bool {
  match char {
    'a'..='z'
    | 'A'..='Z'
    | '0'..='9'
    | '!'
    | '#'
    | '$'
    | '%'
    | '&'
    | '\''
    | '*'
    | '+'
    | '-'
    | '.'
    | '^'
    | '_'
    | '`'
    | '|'
    | '~' => true
    _ => false
  }
}

///|
fn valid_http_token(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  for char in value {
    if !is_http_token_char(char) {
      return false
    }
  }
  true
}

///|
fn schema_primitive(fields : Map[String, Json]) -> HeaderPrimitive? {
  match fields.get("type") {
    Some(String("string")) => Some(HeaderString)
    Some(String("integer")) => Some(HeaderInteger)
    Some(String("boolean")) => Some(HeaderBoolean)
    _ => None
  }
}

///|
fn scan_header_schema_node(
  node : Json,
  path : Array[String],
  reachable : Bool,
  names : Set[String],
  bindings : Array[HeaderBinding],
) -> Unit raise HttpHeaderError {
  guard node is Object(fields) else { return }
  if fields.get("x-mcp-header") is Some(annotation) {
    guard reachable && !path.is_empty() else {
      raise InvalidHeaderSchema(
        "x-mcp-header is only allowed on properties-chain parameters",
      )
    }
    guard annotation is String(name) && valid_http_token(name) else {
      raise InvalidHeaderSchema("x-mcp-header must be a non-empty HTTP token")
    }
    let folded = name.to_lower()
    if names.contains(folded) {
      raise InvalidHeaderSchema(
        "duplicate case-insensitive x-mcp-header value: \{name}",
      )
    }
    guard schema_primitive(fields) is Some(primitive) else {
      raise InvalidHeaderSchema(
        "x-mcp-header requires type string, integer, or boolean",
      )
    }
    names.add(folded)
    bindings.push({ name, path: path.copy(), primitive })
  }
  for keyword, child in fields {
    if keyword == "x-mcp-header" {
      continue
    }
    if keyword == "properties" && reachable {
      match child {
        Object(properties) =>
          for property_name, property_schema in properties {
            let property_path = path.copy()
            property_path.push(property_name)
            scan_header_schema_node(
              property_schema, property_path, true, names, bindings,
            )
          }
        _ => scan_header_schema_node(child, path, false, names, bindings)
      }
    } else {
      scan_header_schema_value(child, path, names, bindings)
    }
  }
}

///|
fn scan_header_schema_value(
  node : Json,
  path : Array[String],
  names : Set[String],
  bindings : Array[HeaderBinding],
) -> Unit raise HttpHeaderError {
  match node {
    Object(_) => scan_header_schema_node(node, path, false, names, bindings)
    Array(values) =>
      for value in values {
        scan_header_schema_value(value, path, names, bindings)
      }
    _ => ()
  }
}

///|
fn scan_header_bindings(
  input_schema : Json,
) -> Array[HeaderBinding] raise HttpHeaderError {
  let bindings : Array[HeaderBinding] = []
  scan_header_schema_node(input_schema, [], true, Set([]), bindings)
  bindings
}

///|
/// Validate every `x-mcp-header` annotation in a tool input schema.
///
/// HTTP clients can use this while processing `tools/list` and exclude a tool
/// when this function raises `InvalidHeaderSchema`.
pub fn validate_tool_header_schema(
  input_schema : Json,
) -> Unit raise HttpHeaderError {
  ignore(scan_header_bindings(input_schema))
}

///|
fn value_at_path(arguments : Json, path : Array[String]) -> Json? {
  let mut current = arguments
  for segment in path {
    match current {
      Object(fields) =>
        match fields.get(segment) {
          Some(value) => current = value
          None => return None
        }
      _ => return None
    }
  }
  Some(current)
}

///|
fn primitive_header_value(
  value : Json,
  primitive : HeaderPrimitive,
) -> String? raise HttpHeaderError {
  if value is Null {
    return None
  }
  match (primitive, value) {
    (HeaderString, String(value)) => Some(value)
    (HeaderBoolean, True) => Some("true")
    (HeaderBoolean, False) => Some("false")
    (HeaderInteger, Number(number, ..)) => {
      let max_safe = 9007199254740991.0
      guard number >= -max_safe &&
        number <= max_safe &&
        number == number.to_int64().to_double() else {
        raise InvalidHeaderValue(
          "MCP header integer must be an integer in the JavaScript safe range",
        )
      }
      Some(number.to_string())
    }
    _ =>
      raise InvalidHeaderValue("MCP header argument does not match schema type")
  }
}

///|
/// Extract all annotated tool arguments as `Mcp-Param-*` request headers.
pub fn tool_argument_headers(
  input_schema : Json,
  arguments : Json,
) -> Map[String, String] raise HttpHeaderError {
  let headers : Map[String, String] = Map([])
  for binding in scan_header_bindings(input_schema) {
    match value_at_path(arguments, binding.path) {
      Some(value) =>
        match primitive_header_value(value, binding.primitive) {
          Some(value) =>
            headers["Mcp-Param-\{binding.name}"] = encode_mcp_header_value(
              value,
            )
          None => ()
        }
      None => ()
    }
  }
  headers
}

///|
fn header_value_matches(
  actual : String,
  expected : String,
  primitive : HeaderPrimitive,
) -> Bool {
  match primitive {
    HeaderInteger =>
      try @string.parse_double(actual) catch {
        _ => false
      } noraise {
        parsed =>
          try @string.parse_double(expected) catch {
            _ => false
          } noraise {
            expected_number => parsed == expected_number
          }
      }
    _ => actual == expected
  }
}

///|
/// Validate recognized `Mcp-Param-*` headers against a tool schema and call
/// arguments. Unknown extension headers are deliberately ignored.
pub fn validate_tool_argument_headers(
  headers : Map[String, String],
  input_schema : Json,
  arguments : Json,
) -> Unit raise HttpHeaderError {
  for binding in scan_header_bindings(input_schema) {
    let field_name = "Mcp-Param-\{binding.name}"
    let supplied = match unique_header(headers, field_name) {
      Ok(value) => value
      Err(message) => raise HeaderMismatch(message)
    }
    let expected = match value_at_path(arguments, binding.path) {
      Some(value) => primitive_header_value(value, binding.primitive)
      None => None
    }
    match (supplied, expected) {
      (None, None) => ()
      (Some(_), None) =>
        raise HeaderMismatch(
          "Header mismatch: \{field_name} is present but body value is absent or null",
        )
      (None, Some(_)) =>
        raise HeaderMismatch(
          "Header mismatch: required \{field_name} is missing",
        )
      (Some(encoded), Some(expected)) => {
        let decoded = decode_mcp_header_value(encoded) catch {
          InvalidHeaderSchema(message)
          | InvalidHeaderValue(message)
          | HeaderMismatch(message) => raise HeaderMismatch(message)
        }
        if !header_value_matches(decoded, expected, binding.primitive) {
          raise HeaderMismatch(
            "Header mismatch: \{field_name} does not match body value",
          )
        }
      }
    }
  }
}

///|
fn request_method_name(message : Json) -> String? {
  match message {
    Object({ "method": String(method_name), .. }) => Some(method_name)
    _ => None
  }
}

///|
fn request_id(message : Json) -> Json? {
  match decode_jsonrpc_message(message) {
    Some(@jsonrpc.Message::Request(request)) => Some(request.id.as_json())
    Some(@jsonrpc.Message::Response(@jsonrpc.Response::Success(id~, ..)))
    | Some(@jsonrpc.Message::Response(@jsonrpc.Response::Failure(id~, ..))) =>
      Some(id.as_json())
    Some(@jsonrpc.Message::Notification(_)) | None => None
  }
}

///|
fn is_jsonrpc_request(message : Json) -> Bool {
  match decode_jsonrpc_message(message) {
    Some(@jsonrpc.Message::Request(_)) => true
    _ => false
  }
}

///|
fn is_jsonrpc_notification(message : Json) -> Bool {
  match decode_jsonrpc_message(message) {
    Some(@jsonrpc.Message::Notification(_)) => true
    _ => false
  }
}

///|
fn is_jsonrpc_response(message : Json) -> Bool {
  match decode_jsonrpc_message(message) {
    Some(@jsonrpc.Message::Response(_)) => true
    _ => false
  }
}

///|
fn decode_jsonrpc_message(message : Json) -> @jsonrpc.Message? {
  Some(@jsonrpc.decode(message)) catch {
    _ => None
  }
}

///|
fn jsonrpc_error_code(message : Json) -> Double? {
  match message {
    Object({ "error": Object({ "code": Number(code, ..), .. }), .. }) =>
      Some(code)
    _ => None
  }
}

///|
fn named_request_value(message : Json) -> String? {
  match message {
    Object(
      {
        "method": String("tools/call"),
        "params": Object({ "name": String(name), .. }),
        ..
      }
    ) => Some(name)
    Object(
      {
        "method": String("prompts/get"),
        "params": Object({ "name": String(name), .. }),
        ..
      }
    ) => Some(name)
    Object(
      {
        "method": String("resources/read"),
        "params": Object({ "uri": String(uri), .. }),
        ..
      }
    ) => Some(uri)
    _ => None
  }
}

///|
fn protocol_version_from_message(message : Json) -> String? {
  match message {
    Object(
      {
        "params": Object(
          {
            "_meta": Object(
              { "io.modelcontextprotocol/protocolVersion": String(version), .. }
            ),
            ..
          }
        ),
        ..
      }
    ) => Some(version)
    _ => None
  }
}

///|
fn standard_request_headers(
  message : Json,
  protocol_version : String,
) -> Map[String, String] {
  let headers : Map[String, String] = {
    "MCP-Protocol-Version": protocol_version,
  }
  if request_method_name(message) is Some(method_name) {
    headers["Mcp-Method"] = method_name
  }
  if named_request_value(message) is Some(name) {
    headers["Mcp-Name"] = encode_mcp_header_value(name)
  }
  headers
}

///|
fn validate_standard_headers(
  request : @async_http.Request,
  message : Json,
  supported_versions? : Array[String] = [@mcp.latest_protocol_version],
) -> Unit raise @mcp.McpError {
  let header_version = match
    unique_header(request.headers, "MCP-Protocol-Version") {
    Ok(Some(value)) => value
    Ok(None) => raise @mcp.HeaderMismatch("MCP-Protocol-Version is required")
    Err(message) => raise @mcp.HeaderMismatch(message)
  }
  if !plain_header_value_is_safe(header_version) {
    raise @mcp.HeaderMismatch("MCP-Protocol-Version is malformed")
  }
  match protocol_version_from_message(message) {
    Some(body_version) =>
      if header_version != body_version {
        raise @mcp.HeaderMismatch(
          "MCP-Protocol-Version does not match request metadata",
        )
      }
    None if is_jsonrpc_request(message) =>
      raise @mcp.HeaderMismatch(
        "request metadata must include MCP protocol version",
      )
    None => ()
  }
  if !supported_versions.is_empty() &&
    !supported_versions.contains(header_version) {
    raise @mcp.UnsupportedProtocolVersion(
      requested=header_version,
      supported=supported_versions,
    )
  }
  let header_method = match unique_header(request.headers, "Mcp-Method") {
    Ok(Some(value)) => value
    Ok(None) => raise @mcp.HeaderMismatch("Mcp-Method is required")
    Err(message) => raise @mcp.HeaderMismatch(message)
  }
  if !plain_header_value_is_safe(header_method) {
    raise @mcp.HeaderMismatch("Mcp-Method is malformed")
  }
  match request_method_name(message) {
    Some(method_name) if method_name == header_method => ()
    _ => raise @mcp.HeaderMismatch("Mcp-Method does not match body method")
  }
  let supplied_name = match unique_header(request.headers, "Mcp-Name") {
    Ok(value) => value
    Err(message) => raise @mcp.HeaderMismatch(message)
  }
  match (named_request_value(message), supplied_name) {
    (Some(_), None) => raise @mcp.HeaderMismatch("Mcp-Name is required")
    (None, Some(_)) =>
      raise @mcp.HeaderMismatch("Mcp-Name has no corresponding body value")
    (None, None) => ()
    (Some(expected), Some(encoded)) => {
      let decoded = decode_mcp_header_value(encoded) catch {
        _ => raise @mcp.HeaderMismatch("Mcp-Name is malformed")
      }
      if decoded != expected {
        raise @mcp.HeaderMismatch("Mcp-Name does not match body value")
      }
    }
  }
}
