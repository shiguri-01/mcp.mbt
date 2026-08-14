///|
/// JSON-RPC 2.0 wire types used by MCP.
///
/// This package deliberately knows nothing about MCP methods, transports, or
/// HTTP headers.  It only validates the JSON-RPC envelope and preserves the
/// payload for the protocol layer.
const JSON_RPC_VERSION : String = "2.0"

///|
pub enum RequestId {
  String(String)
  Number(value~ : Double, repr~ : String)
} derive(Eq, Debug)

///|
pub fn RequestId::string(value : String) -> RequestId {
  String(value)
}

///|
pub fn RequestId::number(
  value : Double,
  repr? : String,
) -> RequestId raise JsonRpcValidationError {
  if value.is_nan() || value.is_inf() {
    raise JsonRpcValidationError::InvalidEnvelope("JSON-RPC id must be finite")
  }
  Number(value~, repr=repr.unwrap_or(value.to_string()))
}

///|
pub fn RequestId::as_json(self : RequestId) -> Json {
  match self {
    String(value) => Json::string(value)
    Number(value~, repr~) => Json::number(value, repr~)
  }
}

///|
pub impl ToJson for RequestId with fn to_json(self) -> Json {
  self.as_json()
}

///|
pub impl FromJson for RequestId with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> RequestId {
  match value {
    Json::String(value) => String(value)
    Json::Number(value, repr~) =>
      Number(value~, repr=repr.unwrap_or(value.to_string()))
    _ =>
      raise @json.JsonDecodeError(
        (path, "JSON-RPC id must be a string or number"),
      )
  }
}

///|
/// A JSON-RPC request envelope.  `Params` is intentionally unconstrained at
/// this layer; the MCP protocol package supplies the method-specific type.
pub struct Request[Params] {
  id : RequestId
  method_name : String
  params : Params
}

///|
pub fn[Params] Request::Request(
  id~ : RequestId,
  method_name~ : String,
  params~ : Params,
) -> Request[Params] raise JsonRpcValidationError {
  if method_name.is_empty() {
    raise JsonRpcValidationError::InvalidEnvelope(
      "JSON-RPC request method must not be empty",
    )
  }
  { id, method_name, params }
}

///|
pub impl[Params : ToJson] ToJson for Request[Params] with fn to_json(self) -> Json {
  Json::object({
    "jsonrpc": Json::string(JSON_RPC_VERSION),
    "id": self.id.to_json(),
    "method": Json::string(self.method_name),
    "params": self.params.to_json(),
  })
}

///|
/// A JSON-RPC notification envelope. Notifications never carry an id.
pub struct Notification[Params] {
  method_name : String
  params : Params
}

///|
pub fn[Params] Notification::Notification(
  method_name~ : String,
  params~ : Params,
) -> Notification[Params] raise JsonRpcValidationError {
  if method_name.is_empty() {
    raise JsonRpcValidationError::InvalidEnvelope(
      "JSON-RPC notification method must not be empty",
    )
  }
  { method_name, params }
}

///|
pub impl[Params : ToJson] ToJson for Notification[Params] with fn to_json(self) -> Json {
  Json::object({
    "jsonrpc": Json::string(JSON_RPC_VERSION),
    "method": Json::string(self.method_name),
    "params": self.params.to_json(),
  })
}

///|
pub struct ErrorObject {
  code : Int
  message : String
  data : Json?
}

///|
pub fn ErrorObject::ErrorObject(
  code~ : Int,
  message~ : String,
  data? : Json,
) -> ErrorObject {
  { code, message, data }
}

///|

///|
pub impl ToJson for ErrorObject with fn to_json(self) -> Json {
  let fields : Map[String, Json] = {
    "code": Json::number(self.code.to_double(), repr="\{self.code}"),
    "message": Json::string(self.message),
  }
  match self.data {
    Some(data) => fields["data"] = data
    None => ()
  }
  Json::object(fields)
}

///|
pub impl FromJson for ErrorObject with fn from_json(value, path) -> ErrorObject {
  match value {
    Json::Object(fields) => {
      let code = match fields.get("code") {
        Some(Json::Number(value, ..)) if value.to_int().to_double() == value =>
          value.to_int()
        _ =>
          raise @json.JsonDecodeError(
            (path.add_key("code"), "error code must be an integer"),
          )
      }
      let message = match fields.get("message") {
        Some(Json::String(value)) => value
        _ =>
          raise @json.JsonDecodeError(
            (path.add_key("message"), "error message must be a string"),
          )
      }
      { code, message, data: fields.get("data") }
    }
    _ => raise @json.JsonDecodeError((path, "JSON-RPC error must be an object"))
  }
}

///|
pub enum Response[Result] {
  Success(id~ : RequestId, result~ : Result)
  Failure(id~ : RequestId, error~ : ErrorObject)
}

///|
pub fn[Result] response_success(
  id~ : RequestId,
  result~ : Result,
) -> Response[Result] {
  Success(id~, result~)
}

///|
pub fn[Result] response_failure(
  id~ : RequestId,
  error~ : ErrorObject,
) -> Response[Result] {
  Failure(id~, error~)
}

///|
pub impl[Result : ToJson] ToJson for Response[Result] with fn to_json(self) -> Json {
  match self {
    Success(id~, result~) =>
      Json::object({
        "jsonrpc": Json::string(JSON_RPC_VERSION),
        "id": id.to_json(),
        "result": result.to_json(),
      })
    Failure(id~, error~) =>
      Json::object({
        "jsonrpc": Json::string(JSON_RPC_VERSION),
        "id": id.to_json(),
        "error": error.to_json(),
      })
  }
}

///|
pub enum Message {
  Request(Request[Json])
  Notification(Notification[Json])
  Response(Response[Json])
}

///|
/// Decode the JSON-RPC envelope only.  MCP semantic errors are intentionally
/// handled by the caller after this syntax boundary.
pub(all) suberror JsonRpcDecodeError {
  InvalidMessage(String)
} derive(Debug, Eq)

///|
fn decode_id(value : Json) -> RequestId raise JsonRpcDecodeError {
  match value {
    Json::String(value) => RequestId::String(value)
    Json::Number(value, repr~) =>
      RequestId::Number(value~, repr=repr.unwrap_or(value.to_string()))
    _ =>
      raise JsonRpcDecodeError::InvalidMessage("id must be a string or number")
  }
}

///|
pub fn decode(value : Json) -> Message raise JsonRpcDecodeError {
  guard value is Json::Object(fields) else {
    raise JsonRpcDecodeError::InvalidMessage(
      "JSON-RPC message must be an object",
    )
  }
  guard fields.get("jsonrpc") == Some(Json::string(JSON_RPC_VERSION)) else {
    raise JsonRpcDecodeError::InvalidMessage("jsonrpc must be \"2.0\"")
  }
  match fields.get("method") {
    Some(Json::String(method_name)) => {
      let params : Json = match fields.get("params") {
        Some(Json::Object(params)) => Json::object(params)
        Some(Json::Array(params)) => Json::array(params)
        None => Json::object({})
        _ =>
          raise JsonRpcDecodeError::InvalidMessage(
            "params must be structured JSON",
          )
      }
      match fields.get("id") {
        Some(id) =>
          Message::Request(
            make_request(id=decode_id(id), method_name~, params~),
          )
        None => Message::Notification(make_notification(method_name~, params~))
      }
    }
    None => {
      let id = match fields.get("id") {
        Some(id) => decode_id(id)
        None =>
          raise JsonRpcDecodeError::InvalidMessage("response id is required")
      }
      match (fields.get("result"), fields.get("error")) {
        (Some(result), None) => Message::Response(Success(id~, result~))
        (None, Some(error)) =>
          Message::Response(Failure(id~, error=decode_error(error)))
        _ =>
          raise JsonRpcDecodeError::InvalidMessage(
            "response must contain result or error",
          )
      }
    }
    _ => raise JsonRpcDecodeError::InvalidMessage("method must be a string")
  }
}

///|
fn make_request(
  id~ : RequestId,
  method_name~ : String,
  params~ : Json,
) -> Request[Json] raise JsonRpcDecodeError {
  Request(id~, method_name~, params~) catch {
    _ =>
      raise JsonRpcDecodeError::InvalidMessage(
        "request method must not be empty",
      )
  }
}

///|
fn make_notification(
  method_name~ : String,
  params~ : Json,
) -> Notification[Json] raise JsonRpcDecodeError {
  Notification(method_name~, params~) catch {
    _ =>
      raise JsonRpcDecodeError::InvalidMessage(
        "notification method must not be empty",
      )
  }
}

///|
fn decode_error(value : Json) -> ErrorObject raise JsonRpcDecodeError {
  match value {
    Json::Object(fields) => {
      let code = match fields.get("code") {
        Some(Json::Number(value, ..)) if value.to_int().to_double() == value =>
          value.to_int()
        _ =>
          raise JsonRpcDecodeError::InvalidMessage(
            "error code must be an integer",
          )
      }
      let message = match fields.get("message") {
        Some(Json::String(value)) => value
        _ =>
          raise JsonRpcDecodeError::InvalidMessage(
            "error message must be a string",
          )
      }
      ErrorObject(code~, message~, data?=fields.get("data"))
    }
    _ => raise JsonRpcDecodeError::InvalidMessage("error must be an object")
  }
}

///|
pub(all) suberror JsonRpcValidationError {
  InvalidEnvelope(String)
} derive(Debug, Eq)
