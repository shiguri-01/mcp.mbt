///|
/// Parameters for `notifications/cancelled`.
pub struct CancelledNotificationParams {
  request_id : Json
  reason : String?
} derive(Debug, Eq)

///|
pub fn CancelledNotificationParams::CancelledNotificationParams(
  request_id~ : Json,
  reason? : String,
) -> CancelledNotificationParams raise McpError {
  guard request_id is (String(_) | Number(_)) else {
    raise InvalidParams(
      "cancelled notification requestId must be a string or number",
    )
  }
  { request_id, reason }
}

///|
pub impl @json.FromJson for CancelledNotificationParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> CancelledNotificationParams raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let request_id = match fields.get("requestId") {
    Some(String(_) | Number(_) as id) => id
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("requestId"), "expected string or number"),
      )
    None =>
      raise JsonDecodeError(
        (path.add_key("requestId"), "requestId is required"),
      )
  }
  let reason = match fields.get("reason") {
    Some(String(reason)) => Some(reason)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("reason"), "expected string"))
  }
  CancelledNotificationParams(request_id~, reason?) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub impl ToJson for CancelledNotificationParams with fn to_json(
  self : CancelledNotificationParams,
) -> Json {
  let fields : Map[String, Json] = { "requestId": self.request_id }
  if self.reason is Some(reason) {
    fields["reason"] = Json::string(reason)
  }
  Json::object(fields)
}

///|
pub fn CancelledNotificationParams::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> CancelledNotificationParams raise McpError {
  decode_json(value, path?)
}

///|
/// Notification sent by client to cancel an in-flight request.
pub struct CancelledNotification {
  params : CancelledNotificationParams
} derive(Debug, Eq)

///|
pub fn CancelledNotification::CancelledNotification(
  request_id~ : Json,
  reason? : String,
) -> CancelledNotification raise McpError {
  let params = CancelledNotificationParams(request_id~, reason?)
  { params, }
}

///|
pub fn CancelledNotification::to_jsonrpc(
  self : CancelledNotification,
) -> @jsonrpc.Notification[CancelledNotificationParams] {
  try! @jsonrpc.Notification(
    method_name="notifications/cancelled",
    params=self.params,
  )
}

///|
pub fn CancelledNotification::to_json(self : CancelledNotification) -> Json {
  self.to_jsonrpc().to_json()
}

///|
pub impl ToJson for CancelledNotification with fn to_json(
  self : CancelledNotification,
) -> Json {
  self.to_json()
}

///|
/// Parameters for `notifications/progress`.
pub struct ProgressNotificationParams {
  progress_token : Json
  progress : Double
  total : Double?
  message : String?
} derive(Debug, Eq)

///|
pub fn ProgressNotificationParams::ProgressNotificationParams(
  progress_token~ : Json,
  progress~ : Double,
  total? : Double,
  message? : String,
) -> ProgressNotificationParams raise McpError {
  validate_progress_token(progress_token, "progress notification")
  guard progress >= 0.0 else {
    raise InvalidParams("progress notification progress must be non-negative")
  }
  if total is Some(total_val) && total_val < progress {
    raise InvalidParams("progress notification total must be >= progress")
  }
  { progress_token, progress, total, message }
}

///|
pub impl @json.FromJson for ProgressNotificationParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ProgressNotificationParams raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let progress_token = match fields.get("progressToken") {
    Some(String(_) | Number(_) as token) => token
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("progressToken"), "expected string or number"),
      )
    None =>
      raise JsonDecodeError(
        (path.add_key("progressToken"), "progressToken is required"),
      )
  }
  let progress = match fields.get("progress") {
    Some(Number(num, ..)) => num
    Some(_) =>
      raise JsonDecodeError((path.add_key("progress"), "expected number"))
    None =>
      raise JsonDecodeError((path.add_key("progress"), "progress is required"))
  }
  let total = match fields.get("total") {
    Some(Number(num, ..)) => Some(num)
    Some(Null) | None => None
    Some(_) => raise JsonDecodeError((path.add_key("total"), "expected number"))
  }
  let message = match fields.get("message") {
    Some(String(msg)) => Some(msg)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("message"), "expected string"))
  }
  ProgressNotificationParams(progress_token~, progress~, total?, message?) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub impl ToJson for ProgressNotificationParams with fn to_json(
  self : ProgressNotificationParams,
) -> Json {
  let fields : Map[String, Json] = {
    "progressToken": self.progress_token,
    "progress": Json::number(self.progress),
  }
  if self.total is Some(total) {
    fields["total"] = Json::number(total)
  }
  if self.message is Some(message) {
    fields["message"] = Json::string(message)
  }
  Json::object(fields)
}

///|
pub fn ProgressNotificationParams::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ProgressNotificationParams raise McpError {
  decode_json(value, path?)
}

///|
/// Notification reporting progress on a long-running request.
pub struct ProgressNotification {
  params : ProgressNotificationParams
} derive(Debug, Eq)

///|
pub fn ProgressNotification::ProgressNotification(
  progress_token~ : Json,
  progress~ : Double,
  total? : Double,
  message? : String,
) -> ProgressNotification raise McpError {
  let params = ProgressNotificationParams(
    progress_token~,
    progress~,
    total?,
    message?,
  )
  { params, }
}

///|
pub fn ProgressNotification::to_jsonrpc(
  self : ProgressNotification,
) -> @jsonrpc.Notification[ProgressNotificationParams] {
  try! @jsonrpc.Notification(
    method_name="notifications/progress",
    params=self.params,
  )
}

///|
pub fn ProgressNotification::to_json(self : ProgressNotification) -> Json {
  self.to_jsonrpc().to_json()
}

///|
pub impl ToJson for ProgressNotification with fn to_json(
  self : ProgressNotification,
) -> Json {
  self.to_json()
}

///|
/// Notification indicating available tools have changed.
pub struct ToolsListChangedNotification {
  params : SubscriptionNotificationParams
} derive(Debug, Eq)

///|
pub fn ToolsListChangedNotification::ToolsListChangedNotification(
  subscription_id~ : Json,
) -> ToolsListChangedNotification raise McpError {
  let params = SubscriptionNotificationParams(subscription_id~)
  { params, }
}

///|
pub fn ToolsListChangedNotification::to_jsonrpc(
  self : ToolsListChangedNotification,
) -> @jsonrpc.Notification[SubscriptionNotificationParams] {
  try! @jsonrpc.Notification(
    method_name="notifications/tools/list_changed",
    params=self.params,
  )
}

///|
pub fn ToolsListChangedNotification::to_json(
  self : ToolsListChangedNotification,
) -> Json {
  self.to_jsonrpc().to_json()
}

///|
pub impl ToJson for ToolsListChangedNotification with fn to_json(
  self : ToolsListChangedNotification,
) -> Json {
  self.to_json()
}

///|
/// Notification indicating available resources have changed.
pub struct ResourcesListChangedNotification {
  params : SubscriptionNotificationParams
} derive(Debug, Eq)

///|
pub fn ResourcesListChangedNotification::ResourcesListChangedNotification(
  subscription_id~ : Json,
) -> ResourcesListChangedNotification raise McpError {
  let params = SubscriptionNotificationParams(subscription_id~)
  { params, }
}

///|
pub fn ResourcesListChangedNotification::to_jsonrpc(
  self : ResourcesListChangedNotification,
) -> @jsonrpc.Notification[SubscriptionNotificationParams] {
  try! @jsonrpc.Notification(
    method_name="notifications/resources/list_changed",
    params=self.params,
  )
}

///|
pub fn ResourcesListChangedNotification::to_json(
  self : ResourcesListChangedNotification,
) -> Json {
  self.to_jsonrpc().to_json()
}

///|
pub impl ToJson for ResourcesListChangedNotification with fn to_json(
  self : ResourcesListChangedNotification,
) -> Json {
  self.to_json()
}

///|
/// Notification indicating available prompts have changed.
pub struct PromptsListChangedNotification {
  params : SubscriptionNotificationParams
} derive(Debug, Eq)

///|
pub fn PromptsListChangedNotification::PromptsListChangedNotification(
  subscription_id~ : Json,
) -> PromptsListChangedNotification raise {
  let params = SubscriptionNotificationParams(subscription_id~)
  { params, }
}

///|
pub fn PromptsListChangedNotification::to_jsonrpc(
  self : PromptsListChangedNotification,
) -> @jsonrpc.Notification[SubscriptionNotificationParams] {
  try! @jsonrpc.Notification(
    method_name="notifications/prompts/list_changed",
    params=self.params,
  )
}

///|
pub fn PromptsListChangedNotification::to_json(
  self : PromptsListChangedNotification,
) -> Json {
  self.to_jsonrpc().to_json()
}

///|
pub impl ToJson for PromptsListChangedNotification with fn to_json(
  self : PromptsListChangedNotification,
) -> Json {
  self.to_json()
}

///|
/// Parameters for `notifications/resources/updated`.
pub struct ResourceUpdatedNotificationParams {
  uri : String
  subscription_id : Json
} derive(Debug, Eq)

///|
pub fn ResourceUpdatedNotificationParams::ResourceUpdatedNotificationParams(
  uri~ : String,
  subscription_id~ : Json,
) -> ResourceUpdatedNotificationParams raise McpError {
  guard !uri.is_empty() else {
    raise InvalidParams("resource uri must not be empty")
  }
  guard subscription_id is (String(_) | Number(_)) else {
    raise InvalidParams(
      "resource updated notification subscriptionId must be a string or number",
    )
  }
  { uri, subscription_id }
}

///|
pub impl @json.FromJson for ResourceUpdatedNotificationParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ResourceUpdatedNotificationParams raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let uri = match fields.get("uri") {
    Some(String(s)) if !s.is_empty() => s
    Some(String(_)) =>
      raise JsonDecodeError(
        (path.add_key("uri"), "resource uri must not be empty"),
      )
    Some(_) => raise JsonDecodeError((path.add_key("uri"), "expected string"))
    None => raise JsonDecodeError((path.add_key("uri"), "uri is required"))
  }
  let meta = match fields.get("_meta") {
    Some(Object(m)) => m
    Some(_) => raise JsonDecodeError((path.add_key("_meta"), "expected object"))
    None => raise JsonDecodeError((path.add_key("_meta"), "_meta is required"))
  }
  let subscription_id = match
    meta.get("io.modelcontextprotocol/subscriptionId") {
    Some(String(_) | Number(_) as id) => id
    Some(_) =>
      raise JsonDecodeError(
        (
          path
          .add_key("_meta")
          .add_key("io.modelcontextprotocol/subscriptionId"),
          "expected string or number",
        ),
      )
    None =>
      raise JsonDecodeError(
        (
          path
          .add_key("_meta")
          .add_key("io.modelcontextprotocol/subscriptionId"),
          "subscriptionId is required",
        ),
      )
  }
  ResourceUpdatedNotificationParams(uri~, subscription_id~) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub impl ToJson for ResourceUpdatedNotificationParams with fn to_json(
  self : ResourceUpdatedNotificationParams,
) -> Json {
  Json::object({
    "uri": Json::string(self.uri),
    "_meta": Json::object({
      "io.modelcontextprotocol/subscriptionId": self.subscription_id,
    }),
  })
}

///|
pub fn ResourceUpdatedNotificationParams::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ResourceUpdatedNotificationParams raise McpError {
  decode_json(value, path?)
}

///|
/// Notification indicating a specific resource content has updated.
pub struct ResourceUpdatedNotification {
  params : ResourceUpdatedNotificationParams
} derive(Debug, Eq)

///|
pub fn ResourceUpdatedNotification::ResourceUpdatedNotification(
  uri~ : String,
  subscription_id~ : Json,
) -> ResourceUpdatedNotification raise McpError {
  let params = ResourceUpdatedNotificationParams(uri~, subscription_id~)
  { params, }
}

///|
pub fn ResourceUpdatedNotification::to_jsonrpc(
  self : ResourceUpdatedNotification,
) -> @jsonrpc.Notification[ResourceUpdatedNotificationParams] {
  try! @jsonrpc.Notification(
    method_name="notifications/resources/updated",
    params=self.params,
  )
}

///|
pub fn ResourceUpdatedNotification::to_json(
  self : ResourceUpdatedNotification,
) -> Json {
  self.to_jsonrpc().to_json()
}

///|
pub impl ToJson for ResourceUpdatedNotification with fn to_json(
  self : ResourceUpdatedNotification,
) -> Json {
  self.to_json()
}

///|
/// Parameters for `notifications/message` (logging).
pub struct LoggingMessageNotificationParams {
  level : LoggingLevel
  data : Json
  logger : String?
} derive(Debug, Eq)

///|
pub fn LoggingMessageNotificationParams::LoggingMessageNotificationParams(
  level~ : LoggingLevel,
  data~ : Json,
  logger? : String,
) -> LoggingMessageNotificationParams {
  { level, data, logger }
}

///|
pub impl @json.FromJson for LoggingMessageNotificationParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> LoggingMessageNotificationParams raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let level = match fields.get("level") {
    Some(v) => @json.from_json(v, path=path.add_key("level"))
    None => raise JsonDecodeError((path.add_key("level"), "level is required"))
  }
  let data = match fields.get("data") {
    Some(v) => v
    None => raise JsonDecodeError((path.add_key("data"), "data is required"))
  }
  let logger = match fields.get("logger") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("logger"), "expected string"))
  }
  LoggingMessageNotificationParams(level~, data~, logger?)
}

///|
pub impl ToJson for LoggingMessageNotificationParams with fn to_json(
  self : LoggingMessageNotificationParams,
) -> Json {
  let fields : Map[String, Json] = {
    "level": ToJson::to_json(self.level),
    "data": self.data,
  }
  if self.logger is Some(logger) {
    fields["logger"] = Json::string(logger)
  }
  Json::object(fields)
}

///|
pub fn LoggingMessageNotificationParams::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> LoggingMessageNotificationParams raise McpError {
  decode_json(value, path?)
}

///|
/// Deprecated request-scoped log notification.
pub struct LoggingMessageNotification {
  params : LoggingMessageNotificationParams
} derive(Debug, Eq)

///|
pub fn LoggingMessageNotification::LoggingMessageNotification(
  level~ : LoggingLevel,
  data~ : Json,
  logger? : String,
) -> LoggingMessageNotification {
  let params = LoggingMessageNotificationParams(level~, data~, logger?)
  { params, }
}

///|
pub fn LoggingMessageNotification::to_jsonrpc(
  self : LoggingMessageNotification,
) -> @jsonrpc.Notification[LoggingMessageNotificationParams] {
  try! @jsonrpc.Notification(
    method_name="notifications/message",
    params=self.params,
  )
}

///|
pub fn LoggingMessageNotification::to_json(
  self : LoggingMessageNotification,
) -> Json {
  self.to_jsonrpc().to_json()
}

///|
pub impl ToJson for LoggingMessageNotification with fn to_json(
  self : LoggingMessageNotification,
) -> Json {
  self.to_json()
}
