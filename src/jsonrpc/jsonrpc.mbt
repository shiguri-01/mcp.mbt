///|
/// JSON-RPC 2.0 wire types used by MCP.
///
/// This package deliberately knows nothing about MCP methods, transports, or
/// HTTP headers.  It only validates the JSON-RPC envelope and preserves the
/// payload for the protocol layer.
pub const JSON_RPC_VERSION : String = "2.0"

///|
pub const PARSE_ERROR : Int = -32700

///|
pub const INVALID_REQUEST : Int = -32600

///|
pub const METHOD_NOT_FOUND : Int = -32601

///|
pub const INVALID_PARAMS : Int = -32602

///|
pub const INTERNAL_ERROR : Int = -32603

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
  guard !(value.is_nan() || value.is_inf()) else {
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
pub fn RequestId::to_routing_key(self : RequestId) -> String {
  match self {
    String(value) => "string:\{value}"
    Number(repr~, ..) => "number:\{repr}"
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
} derive(Debug, Eq)

///|
pub fn[Params] Request::Request(
  id~ : RequestId,
  method_name~ : String,
  params~ : Params,
) -> Request[Params] raise JsonRpcValidationError {
  guard !method_name.is_empty() else {
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
    "id": ToJson::to_json(self.id),
    "method": Json::string(self.method_name),
    "params": ToJson::to_json(self.params),
  })
}

///|
/// A JSON-RPC notification envelope. Notifications never carry an id.
pub struct Notification[Params] {
  method_name : String
  params : Params
} derive(Debug, Eq)

///|
pub fn[Params] Notification::Notification(
  method_name~ : String,
  params~ : Params,
) -> Notification[Params] raise JsonRpcValidationError {
  guard !method_name.is_empty() else {
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
    "params": ToJson::to_json(self.params),
  })
}

///|
pub struct ErrorObject {
  code : Int
  message : String
  data : Json?
} derive(Debug, Eq)

///|
pub fn ErrorObject::ErrorObject(
  code~ : Int,
  message~ : String,
  data? : Json,
) -> ErrorObject {
  { code, message, data }
}

///|
pub impl ToJson for ErrorObject with fn to_json(self) -> Json {
  let fields : Map[String, Json] = {
    "code": Json::number(self.code.to_double(), repr="\{self.code}"),
    "message": Json::string(self.message),
  }
  if self.data is Some(data) {
    fields["data"] = data
  }
  Json::object(fields)
}

///|
pub impl FromJson for ErrorObject with fn from_json(value, path) -> ErrorObject {
  guard value is Json::Object(fields) else {
    raise @json.JsonDecodeError((path, "JSON-RPC error must be an object"))
  }
  guard fields.get("code") is Some(Json::Number(code_num, ..)) &&
    code_num.to_int().to_double() == code_num else {
    raise @json.JsonDecodeError(
      (path.add_key("code"), "error code must be an integer"),
    )
  }
  guard fields.get("message") is Some(Json::String(message)) else {
    raise @json.JsonDecodeError(
      (path.add_key("message"), "error message must be a string"),
    )
  }
  let code = code_num.to_int()
  let data = fields.get("data")
  ErrorObject(code~, message~, data?)
}

///|
pub(all) enum Response[Result] {
  Success(id~ : RequestId, result~ : Result)
  Failure(id~ : RequestId?, error~ : ErrorObject)
} derive(Debug, Eq)

///|
pub impl[Result : ToJson] ToJson for Response[Result] with fn to_json(self) -> Json {
  match self {
    Success(id~, result~) =>
      Json::object({
        "jsonrpc": Json::string(JSON_RPC_VERSION),
        "id": ToJson::to_json(id),
        "result": ToJson::to_json(result),
      })
    Failure(id~, error~) =>
      Json::object({
        "jsonrpc": Json::string(JSON_RPC_VERSION),
        "id": id.map(fn(i) { ToJson::to_json(i) }).unwrap_or(Json::null()),
        "error": ToJson::to_json(error),
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
pub fn decode(value : Json) -> Message raise JsonRpcDecodeError {
  guard value is Json::Object(fields) else {
    raise JsonRpcDecodeError::InvalidMessage(
      "JSON-RPC message must be an object",
    )
  }
  guard fields.get("jsonrpc") is Some(Json::String(v)) && v == JSON_RPC_VERSION else {
    raise JsonRpcDecodeError::InvalidMessage("jsonrpc must be \"2.0\"")
  }
  match fields.get("method") {
    Some(Json::String(method_name)) => {
      let params : Json = match fields.get("params") {
        Some(Json::Object(params)) => Json::object(params)
        Some(Json::Array(params)) => Json::array(params)
        Some(_) =>
          raise JsonRpcDecodeError::InvalidMessage(
            "params must be structured JSON",
          )
        None => Json::object({})
      }
      match fields.get("id") {
        Some(id_val) => {
          let id : RequestId = @json.from_json(id_val) catch {
            _ =>
              raise JsonRpcDecodeError::InvalidMessage(
                "id must be a string or number",
              )
          }
          let request = Request::Request(id~, method_name~, params~) catch {
            InvalidEnvelope(msg) =>
              raise JsonRpcDecodeError::InvalidMessage(msg)
          }
          Message::Request(request)
        }
        None => {
          let notification = Notification::Notification(method_name~, params~) catch {
            InvalidEnvelope(msg) =>
              raise JsonRpcDecodeError::InvalidMessage(msg)
          }
          Message::Notification(notification)
        }
      }
    }
    Some(_) =>
      raise JsonRpcDecodeError::InvalidMessage("method must be a string")
    None => {
      let id : RequestId? = match fields.get("id") {
        Some(Json::Null) | None => None
        Some(id_val) =>
          Some(
            @json.from_json(id_val) catch {
              _ =>
                raise JsonRpcDecodeError::InvalidMessage(
                  "id must be a string or number",
                )
            },
          )
      }
      match (fields.get("result"), fields.get("error")) {
        (Some(_), Some(_)) | (None, None) =>
          raise JsonRpcDecodeError::InvalidMessage(
            "response must contain result or error",
          )
        (Some(result), None) => {
          guard id is Some(id) else {
            raise JsonRpcDecodeError::InvalidMessage(
              "success response id is required",
            )
          }
          Message::Response(Success(id~, result~))
        }
        (None, Some(error_val)) => {
          let error : ErrorObject = @json.from_json(error_val) catch {
            @json.JsonDecodeError((_, msg)) =>
              raise JsonRpcDecodeError::InvalidMessage(
                if msg.contains("code") {
                  "error code must be an integer"
                } else if msg.contains("message") {
                  "error message must be a string"
                } else {
                  "error must be an object"
                },
              )
          }
          Message::Response(Failure(id~, error~))
        }
      }
    }
  }
}

///|
pub(all) suberror JsonRpcValidationError {
  InvalidEnvelope(String)
} derive(Debug, Eq)
