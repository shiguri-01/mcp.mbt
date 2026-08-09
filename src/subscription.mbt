///|
/// Notification kinds requested by a `subscriptions/listen` stream.
///
/// Every field is opt-in. False booleans and an empty resource list are
/// omitted from the wire representation.
pub(all) struct SubscriptionFilter {
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
    resource_subscriptions,
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
pub fn SubscriptionFilter::from_json(
  value : Json,
) -> SubscriptionFilter raise McpError {
  let fields = expect_object(value, "subscription filter")
  let resource_subscriptions = match fields.get("resourceSubscriptions") {
    None | Some(Null) => []
    Some(Array(values)) =>
      values.map(fn(value) raise McpError {
        match value {
          String(uri) => uri
          _ =>
            raise InvalidParams(
              "subscription filter.resourceSubscriptions must contain strings",
            )
        }
      })
    Some(_) =>
      raise InvalidParams(
        "subscription filter.resourceSubscriptions must be an array",
      )
  }
  {
    tools_list_changed: get_optional_bool(
      fields, "toolsListChanged", "subscription filter",
    ).unwrap_or(false),
    prompts_list_changed: get_optional_bool(
      fields, "promptsListChanged", "subscription filter",
    ).unwrap_or(false),
    resources_list_changed: get_optional_bool(
      fields, "resourcesListChanged", "subscription filter",
    ).unwrap_or(false),
    resource_subscriptions,
  }
}

///|
/// Domain payload for a gracefully closed subscription stream.
///
/// The dispatcher adds `resultType` and the result `_meta`, including the
/// required `io.modelcontextprotocol/subscriptionId`.
pub(all) struct SubscriptionsListenResult {} derive(Debug, Eq)

///|
pub impl ToJson for SubscriptionsListenResult with fn to_json(
  self : SubscriptionsListenResult,
) -> Json {
  ignore(self)
  Json::object({})
}

///|
/// Build `subscriptions/listen` params with the required request metadata.
pub fn subscriptions_listen_params(
  notifications~ : SubscriptionFilter,
  meta~ : Json,
) -> Json {
  Json::object({ "_meta": meta, "notifications": notifications.to_json() })
}

///|
/// Build the mandatory first notification on a subscription stream.
pub fn subscriptions_acknowledged_notification(
  subscription_id~ : Json,
  notifications~ : SubscriptionFilter,
) -> Json {
  jsonrpc_notification(
    "notifications/subscriptions/acknowledged",
    params=Json::object({
      "_meta": Json::object({
        "io.modelcontextprotocol/subscriptionId": subscription_id,
      }),
      "notifications": notifications.to_json(),
    }),
  )
}

///|
/// A validated long-lived subscription request. Transports own the stream;
/// this value supplies the required acknowledgement and graceful final reply.
pub struct Subscription {
  priv id : Json
  priv notifications : SubscriptionFilter
  priv server_info : Implementation
}

///|
pub fn Subscription::id(self : Subscription) -> Json {
  self.id
}

///|
pub fn Subscription::notifications(self : Subscription) -> SubscriptionFilter {
  self.notifications
}

///|
pub fn Subscription::acknowledgement(self : Subscription) -> Json {
  subscriptions_acknowledged_notification(
    subscription_id=self.id,
    notifications=self.notifications,
  )
}

///|
pub fn Subscription::close_response(self : Subscription) -> Json {
  let meta = Map::from_array([
    ("io.modelcontextprotocol/subscriptionId", self.id),
  ])
  let result = try! complete_result(
    SubscriptionsListenResult::{  }.to_json(),
    server_info=self.server_info,
    meta~,
  )
  rpc_result_response(self.id, result)
}

///|
/// Validate a listen request and reduce its filter to notifications this
/// server explicitly configured. The transport must send `acknowledgement()`
/// before publishing any other event.
pub fn Server::accept_subscription(
  self : Server,
  message : Json,
) -> Subscription raise McpError {
  self.registry_frozen = true
  let request = parse_rpc_request(message)
  if request.method_name != "subscriptions/listen" {
    raise InvalidRequest("expected subscriptions/listen request")
  }
  let context = parse_context(request)
  self.ensure_supported_version(context)
  let fields = expect_object(request.params, "subscriptions/listen params")
  guard fields.get("notifications") is Some(value) else {
    raise InvalidParams("subscriptions/listen params.notifications is required")
  }
  let requested = SubscriptionFilter::from_json(value)
  let honored = SubscriptionFilter(
    tools_list_changed=requested.tools_list_changed && self.tool_list_changed,
    prompts_list_changed=requested.prompts_list_changed &&
      self.prompt_list_changed,
    resources_list_changed=requested.resources_list_changed &&
      self.resource_list_changed,
    resource_subscriptions=if self.resource_subscriptions {
      requested.resource_subscriptions
    } else {
      []
    },
  )
  { id: request.id, notifications: honored, server_info: self.info }
}
