///|
/// Deprecated logging level retained for wire compatibility with MCP
/// 2026-07-28. New integrations should not expose connection-wide logging APIs.
pub(all) enum LoggingLevel {
  Debug
  Info
  Notice
  Warning
  Error
  Critical
  Alert
  Emergency
} derive(Debug, Eq)

///|
pub fn LoggingLevel::to_string(self : LoggingLevel) -> String {
  match self {
    Debug => "debug"
    Info => "info"
    Notice => "notice"
    Warning => "warning"
    Error => "error"
    Critical => "critical"
    Alert => "alert"
    Emergency => "emergency"
  }
}

///|
pub impl ToJson for LoggingLevel with fn to_json(self : LoggingLevel) -> Json {
  Json::string(self.to_string())
}

///|
fn parse_logging_level(value : Json) -> LoggingLevel raise McpError {
  match value {
    String("debug") => Debug
    String("info") => Info
    String("notice") => Notice
    String("warning") => Warning
    String("error") => Error
    String("critical") => Critical
    String("alert") => Alert
    String("emergency") => Emergency
    String(other) => raise InvalidParams("unknown logging level: \{other}")
    _ => raise InvalidParams("request logLevel must be a string")
  }
}

///|
/// Deprecated request-scoped log notification retained only for peers that
/// negotiated the legacy logging capability.
pub fn logging_message_notification(
  level~ : LoggingLevel,
  data~ : Json,
  logger? : String,
) -> Json {
  let params : Map[String, Json] = { "level": level.to_json(), "data": data }
  put_optional_string(params, "logger", logger)
  @jsonrpc.Notification(
    method_name="notifications/message",
    params=Json::object(params),
  ).to_json() catch {
    _ => Json::null()
  }
}
