///|
pub(all) suberror McpError {
  ParseError(String)
  InvalidRequest(String)
  MethodNotFound(String)
  InvalidParams(String)
  InternalError(String)
} derive(Debug, Eq)

///|
pub fn McpError::code(self : McpError) -> Int {
  match self {
    ParseError(_) => -32700
    InvalidRequest(_) => -32600
    MethodNotFound(_) => -32601
    InvalidParams(_) => -32602
    InternalError(_) => -32603
  }
}

///|
pub fn McpError::message(self : McpError) -> String {
  match self {
    ParseError(message) => message
    InvalidRequest(message) => message
    MethodNotFound(method_name) => "Method not found: \{method_name}"
    InvalidParams(message) => message
    InternalError(message) => message
  }
}

///|
pub impl ToJson for McpError with fn to_json(self : McpError) -> Json {
  Json::object({
    "code": Json::number(self.code().to_double(), repr="\{self.code()}"),
    "message": Json::string(self.message()),
  })
}
