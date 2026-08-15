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

///|
pub impl @json.FromJson for SubscriptionFilter with fn from_json(value, path) -> SubscriptionFilter {
  guard value is Object(fields) else {
    raise @json.JsonDecodeError((path, "subscription filter must be an object"))
  }
  let read_bool = fn(key : String) -> Bool raise @json.JsonDecodeError {
    match fields.get(key) {
      Some(True) => true
      Some(False | Null) | None => false
      Some(_) =>
        raise @json.JsonDecodeError(
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
            raise @json.JsonDecodeError(
              (
                path.add_key("resourceSubscriptions"),
                "resource subscription must be a string",
              ),
            )
        }
      })
    Some(Null) | None => []
    Some(_) =>
      raise @json.JsonDecodeError(
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
/// Build the mandatory first notification on a subscription stream.
pub fn subscriptions_acknowledged_notification(
  subscription_id~ : Json,
  notifications~ : SubscriptionFilter,
) -> Json {
  try! @jsonrpc.Notification(
    method_name="notifications/subscriptions/acknowledged",
    params=Json::object({
      "_meta": Json::object({
        "io.modelcontextprotocol/subscriptionId": subscription_id,
      }),
      "notifications": notifications.to_json(),
    }),
  ).to_json()
}
