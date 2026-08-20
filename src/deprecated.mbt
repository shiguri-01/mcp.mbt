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
pub impl @json.FromJson for LoggingLevel with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> LoggingLevel raise {
  match value {
    String("debug") => Debug
    String("info") => Info
    String("notice") => Notice
    String("warning") => Warning
    String("error") => Error
    String("critical") => Critical
    String("alert") => Alert
    String("emergency") => Emergency
    String(other) =>
      raise JsonDecodeError((path, "unknown logging level: \{other}"))
    _ => raise JsonDecodeError((path, "expected string"))
  }
}

///|
pub fn LoggingLevel::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> LoggingLevel raise McpError {
  decode_json(value, path?)
}
