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
    ParseError(_) => @jsonrpc.PARSE_ERROR
    InvalidRequest(_) => @jsonrpc.INVALID_REQUEST
    MethodNotFound(_) => @jsonrpc.METHOD_NOT_FOUND
    InvalidParams(_) => @jsonrpc.INVALID_PARAMS
    InvalidParamsWithData(_, _) => @jsonrpc.INVALID_PARAMS
    InternalError(_) => @jsonrpc.INTERNAL_ERROR
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
pub fn McpError::to_string(self : McpError) -> String {
  self.message()
}

///|
pub impl Show for McpError with fn output(self : McpError, logger : &Logger) -> Unit {
  logger.write_string(self.message())
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
pub fn McpError::to_error_object(self : McpError) -> @jsonrpc.ErrorObject {
  @jsonrpc.ErrorObject(
    code=self.code(),
    message=self.message(),
    data?=self.data(),
  )
}

///|
pub impl ToJson for McpError with fn to_json(self : McpError) -> Json {
  self.to_error_object().to_json()
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
  ClientCapabilities::from_json(value)
}

///|
fn parse_unsupported_version_data(
  data : Json?,
) -> (String, Array[String]) raise McpError {
  guard data is Some(Object(fields)) else {
    raise InvalidRequest("-32022 error data must be an object")
  }
  let requested = match fields.get("requested") {
    Some(String(s)) => s
    Some(_) => raise InvalidRequest("error data.requested must be a string")
    None => raise InvalidRequest("error data.requested is required")
  }
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
/// Decode an MCP error object from a JSON-RPC error structure.
pub fn McpError::from_error_object(
  error : @jsonrpc.ErrorObject,
) -> McpError raise McpError {
  McpError::from_rpc_parts(error.code, error.message, data?=error.data)
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
    @jsonrpc.PARSE_ERROR => ParseError(message)
    @jsonrpc.INVALID_REQUEST => InvalidRequest(message)
    @jsonrpc.METHOD_NOT_FOUND => MethodNotFound(message)
    @jsonrpc.INVALID_PARAMS =>
      match data {
        Some(data) => InvalidParamsWithData(message, data)
        None => InvalidParams(message)
      }
    @jsonrpc.INTERNAL_ERROR => InternalError(message)
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
