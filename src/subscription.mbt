///|
/// Notification kinds requested by a `subscriptions/listen` stream.
///
/// Every field is opt-in. False booleans and an empty resource list are
/// omitted from the wire representation.
pub struct SubscriptionFilter {
  tools_list_changed : Bool
  prompts_list_changed : Bool
  resources_list_changed : Bool
  resource_subscriptions : Array[String]
} derive(Debug, Eq)

///|
pub fn SubscriptionFilter::SubscriptionFilter(
  tools_list_changed? : Bool = false,
  prompts_list_changed? : Bool = false,
  resources_list_changed? : Bool = false,
  resource_subscriptions? : Array[String] = [],
) -> SubscriptionFilter {
  {
    tools_list_changed,
    prompts_list_changed,
    resources_list_changed,
    resource_subscriptions: resource_subscriptions.copy(),
  }
}

///|
pub impl ToJson for SubscriptionFilter with fn to_json(
  self : SubscriptionFilter,
) -> Json {
  let fields : Map[String, Json] = Map([])
  if self.tools_list_changed {
    fields["toolsListChanged"] = Json::boolean(true)
  }
  if self.prompts_list_changed {
    fields["promptsListChanged"] = Json::boolean(true)
  }
  if self.resources_list_changed {
    fields["resourcesListChanged"] = Json::boolean(true)
  }
  if !self.resource_subscriptions.is_empty() {
    fields["resourceSubscriptions"] = self.resource_subscriptions.to_json()
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for SubscriptionFilter with fn from_json(value, path) -> SubscriptionFilter {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "subscription filter must be an object"))
  }
  let read_bool = fn(key : String) -> Bool raise @json.JsonDecodeError {
    match fields.get(key) {
      Some(True) => true
      Some(False | Null) | None => false
      Some(_) =>
        raise JsonDecodeError(
          (path.add_key(key), "subscription filter flag must be boolean"),
        )
    }
  }
  let resource_subscriptions : Array[String] = match
    fields.get("resourceSubscriptions") {
    Some(Array(values)) =>
      values.map(fn(value) -> String raise @json.JsonDecodeError {
        match value {
          String(uri) => uri
          _ =>
            raise JsonDecodeError(
              (
                path.add_key("resourceSubscriptions"),
                "resource subscription must be a string",
              ),
            )
        }
      })
    Some(Null) | None => []
    Some(_) =>
      raise JsonDecodeError(
        (
          path.add_key("resourceSubscriptions"),
          "resourceSubscriptions must be an array",
        ),
      )
  }
  SubscriptionFilter(
    tools_list_changed=read_bool("toolsListChanged"),
    prompts_list_changed=read_bool("promptsListChanged"),
    resources_list_changed=read_bool("resourcesListChanged"),
    resource_subscriptions~,
  )
}

///|
/// Domain payload for a gracefully closed subscription stream.
///
/// The dispatcher adds `resultType` and the result `_meta`, including the
/// required `io.modelcontextprotocol/subscriptionId`.
pub struct SubscriptionsListenResult {} derive(Debug, Eq)

///|
/// Construct the empty completion value for a closed subscription stream.
pub fn SubscriptionsListenResult::SubscriptionsListenResult() -> SubscriptionsListenResult {
  SubscriptionsListenResult::{  }
}

///|
pub impl ToJson for SubscriptionsListenResult with fn to_json(
  self : SubscriptionsListenResult,
) -> Json {
  ignore(self)
  Json::object({})
}

///|
/// Parameters for list-changed notifications carrying a subscriptionId.
pub struct SubscriptionNotificationParams {
  subscription_id : Json
} derive(Debug, Eq)

///|
pub fn SubscriptionNotificationParams::SubscriptionNotificationParams(
  subscription_id~ : Json,
) -> SubscriptionNotificationParams raise McpError {
  guard subscription_id is (String(_) | Number(_)) else {
    raise InvalidParams(
      "subscription notification subscriptionId must be a string or number",
    )
  }
  { subscription_id, }
}

///|
pub impl @json.FromJson for SubscriptionNotificationParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> SubscriptionNotificationParams raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
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
  SubscriptionNotificationParams(subscription_id~) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub impl ToJson for SubscriptionNotificationParams with fn to_json(
  self : SubscriptionNotificationParams,
) -> Json {
  Json::object({
    "_meta": Json::object({
      "io.modelcontextprotocol/subscriptionId": self.subscription_id,
    }),
  })
}

///|
pub fn SubscriptionNotificationParams::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> SubscriptionNotificationParams raise McpError {
  decode_json(value, path?)
}

///|
/// Parameters for `notifications/subscriptions/acknowledged`.
pub struct SubscriptionsAcknowledgedNotificationParams {
  subscription_id : Json
  notifications : SubscriptionFilter
} derive(Debug, Eq)

///|
pub fn SubscriptionsAcknowledgedNotificationParams::SubscriptionsAcknowledgedNotificationParams(
  subscription_id~ : Json,
  notifications~ : SubscriptionFilter,
) -> SubscriptionsAcknowledgedNotificationParams raise McpError {
  guard subscription_id is (String(_) | Number(_)) else {
    raise InvalidParams(
      "subscriptions acknowledged notification subscriptionId must be a string or number",
    )
  }
  { subscription_id, notifications }
}

///|
pub impl @json.FromJson for SubscriptionsAcknowledgedNotificationParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> SubscriptionsAcknowledgedNotificationParams raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
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
  let notifications = match fields.get("notifications") {
    Some(v) => @json.from_json(v, path=path.add_key("notifications"))
    None =>
      raise JsonDecodeError(
        (path.add_key("notifications"), "notifications is required"),
      )
  }
  SubscriptionsAcknowledgedNotificationParams(subscription_id~, notifications~) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub impl ToJson for SubscriptionsAcknowledgedNotificationParams with fn to_json(
  self : SubscriptionsAcknowledgedNotificationParams,
) -> Json {
  Json::object({
    "_meta": Json::object({
      "io.modelcontextprotocol/subscriptionId": self.subscription_id,
    }),
    "notifications": ToJson::to_json(self.notifications),
  })
}

///|
pub fn SubscriptionsAcknowledgedNotificationParams::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> SubscriptionsAcknowledgedNotificationParams raise McpError {
  decode_json(value, path?)
}

///|
/// Notification sent by server to acknowledge active subscription stream.
pub struct SubscriptionsAcknowledgedNotification {
  params : SubscriptionsAcknowledgedNotificationParams
} derive(Debug, Eq)

///|
pub fn SubscriptionsAcknowledgedNotification::SubscriptionsAcknowledgedNotification(
  subscription_id~ : Json,
  notifications~ : SubscriptionFilter,
) -> SubscriptionsAcknowledgedNotification raise McpError {
  let params = SubscriptionsAcknowledgedNotificationParams(
    subscription_id~,
    notifications~,
  )
  { params, }
}

///|
pub fn SubscriptionsAcknowledgedNotification::to_jsonrpc(
  self : SubscriptionsAcknowledgedNotification,
) -> @jsonrpc.Notification[SubscriptionsAcknowledgedNotificationParams] {
  try! @jsonrpc.Notification(
    method_name="notifications/subscriptions/acknowledged",
    params=self.params,
  )
}

///|
pub fn SubscriptionsAcknowledgedNotification::to_json(
  self : SubscriptionsAcknowledgedNotification,
) -> Json {
  self.to_jsonrpc().to_json()
}

///|
pub impl ToJson for SubscriptionsAcknowledgedNotification with fn to_json(
  self : SubscriptionsAcknowledgedNotification,
) -> Json {
  self.to_json()
}
