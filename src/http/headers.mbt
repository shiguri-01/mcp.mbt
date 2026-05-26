///|
const HEADER_MISMATCH_CODE : Int = -32001

///|
fn header(headers : Map[String, String], name : String) -> String? {
  let name = name.to_lower()
  let mut found : String? = None
  for key, value in headers {
    if key.to_lower() == name {
      found = Some(value)
    }
  }
  found
}

///|
fn has_media_type(value : String, media_type : String) -> Bool {
  value.to_lower().contains(media_type)
}

///|
fn visible_ascii(value : String) -> Bool {
  for char in value {
    let code = char.to_int()
    if code < 0x21 || code > 0x7e {
      return false
    }
  }
  true
}

///|
fn request_context(request : @async_http.Request) -> RequestContext {
  {
    http_method: request.meth,
    path: request.path,
    headers: request.headers,
    session_id: header(request.headers, "MCP-Session-Id"),
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
  match message {
    Object(fields) => fields.get("id")
    _ => None
  }
}

///|
fn is_jsonrpc_request(message : Json) -> Bool {
  request_method_name(message) is Some(_) && request_id(message) is Some(_)
}

///|
fn is_jsonrpc_notification(message : Json) -> Bool {
  request_method_name(message) is Some(_) && request_id(message) is None
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
    Object({ "params": Object({ "protocolVersion": String(version), .. }), .. }) =>
      Some(version)
    _ => None
  }
}

///|
fn validate_standard_headers(
  request : @async_http.Request,
  message : Json,
  protocol_version? : String,
) -> String? {
  if header(request.headers, "MCP-Protocol-Version") is Some(header_version) {
    if protocol_version is Some(version) && version != header_version {
      return Some(
        "Header mismatch: MCP-Protocol-Version does not match request metadata",
      )
    }
    if header_version != @mcp.latest_protocol_version {
      return Some("Unsupported MCP protocol version: \{header_version}")
    }
  }
  if header(request.headers, "Mcp-Method") is Some(header_method) {
    if request_method_name(message) is Some(method_name) &&
      method_name != header_method {
      return Some("Header mismatch: Mcp-Method does not match body method")
    }
  }
  if header(request.headers, "Mcp-Name") is Some(header_name) {
    if named_request_value(message) is Some(name) && name != header_name {
      return Some("Header mismatch: Mcp-Name does not match body value")
    }
  }
  None
}
