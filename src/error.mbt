///|
/// Protocol and SDK errors. Application-level tool failures remain ordinary
/// `CallToolResult` values and are not represented here.
pub(all) suberror McpError {
  ParseError(String)
  InvalidRequest(String)
  MethodNotFound(String)
  InvalidParams(String)
  InvalidParamsWithData(String, Json)
  InternalError(String)
  HeaderMismatch(String)
  MissingRequiredClientCapability(String, ClientCapabilities)
  UnsupportedProtocolVersion(requested~ : String, supported~ : Array[String])
  RemoteError(code~ : Int, message~ : String, data~ : Json?)
} derive(Debug, Eq)

///|
pub fn McpError::code(self : McpError) -> Int {
  match self {
    ParseError(_) => -32700
    InvalidRequest(_) => -32600
    MethodNotFound(_) => -32601
    InvalidParams(_) => -32602
    InvalidParamsWithData(_, _) => -32602
    InternalError(_) => -32603
    HeaderMismatch(_) => -32020
    MissingRequiredClientCapability(_, _) => -32021
    UnsupportedProtocolVersion(_) => -32022
    RemoteError(code~, ..) => code
  }
}

///|
pub fn McpError::message(self : McpError) -> String {
  match self {
    ParseError(message) => message
    InvalidRequest(message) => message
    MethodNotFound(method_name) => "Method not found: \{method_name}"
    InvalidParams(message) => message
    InvalidParamsWithData(message, _) => message
    InternalError(message) => message
    HeaderMismatch(message) => message
    MissingRequiredClientCapability(message, _) => message
    UnsupportedProtocolVersion(_) => "Unsupported protocol version"
    RemoteError(message~, ..) => message
  }
}

///|
pub fn McpError::data(self : McpError) -> Json? {
  match self {
    MissingRequiredClientCapability(_, required) =>
      Some(Json::object({ "requiredCapabilities": required.to_json() }))
    UnsupportedProtocolVersion(requested~, supported~) =>
      Some(
        Json::object({
          "supported": supported.to_json(),
          "requested": Json::string(requested),
        }),
      )
    InvalidParamsWithData(_, data) => Some(data)
    RemoteError(data~, ..) => data
    _ => None
  }
}

///|
pub impl ToJson for McpError with fn to_json(self : McpError) -> Json {
  let fields : Map[String, Json] = {
    "code": Json::number(self.code().to_double(), repr="\{self.code()}"),
    "message": Json::string(self.message()),
  }
  put_optional_json(fields, "data", self.data())
  Json::object(fields)
}

///|
fn parse_required_capabilities(
  data : Json?,
) -> ClientCapabilities raise McpError {
  guard data is Some(Object(fields)) else {
    raise InvalidRequest("-32021 error data must be an object")
  }
  guard fields.get("requiredCapabilities") is Some(value) else {
    raise InvalidRequest("-32021 error data.requiredCapabilities is required")
  }
  parse_client_capabilities(value, context="error data.requiredCapabilities")
}

///|
fn parse_unsupported_version_data(
  data : Json?,
) -> (String, Array[String]) raise McpError {
  guard data is Some(Object(fields)) else {
    raise InvalidRequest("-32022 error data must be an object")
  }
  let requested = get_string(fields, "requested", "error data")
  let supported = match fields.get("supported") {
    Some(Array(values)) =>
      values.map(value => {
        match value {
          String(version) => version
          _ => raise InvalidRequest("error data.supported must contain strings")
        }
      })
    Some(_) => raise InvalidRequest("error data.supported must be an array")
    None => raise InvalidRequest("error data.supported is required")
  }
  (requested, supported)
}

///|
/// Decode an MCP error object after a JSON-RPC implementation has separated
/// its `code`, `message`, and optional `data` members.
pub fn McpError::from_rpc_parts(
  code : Int,
  message : String,
  data? : Json,
) -> McpError raise McpError {
  match code {
    -32700 => ParseError(message)
    -32600 => InvalidRequest(message)
    -32601 => MethodNotFound(message)
    -32602 =>
      match data {
        Some(data) => InvalidParamsWithData(message, data)
        None => InvalidParams(message)
      }
    -32603 => InternalError(message)
    -32020 => HeaderMismatch(message)
    -32021 =>
      MissingRequiredClientCapability(
        message,
        parse_required_capabilities(data),
      )
    -32022 => {
      let (requested, supported) = parse_unsupported_version_data(data)
      UnsupportedProtocolVersion(requested~, supported~)
    }
    _ => RemoteError(code~, message~, data~)
  }
}
