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
  let fields = match value {
    Object(fields) => fields
    _ =>
      raise @json.JsonDecodeError(
        (path, "subscription filter must be an object"),
      )
  }
  let read_bool = fn(key : String) -> Bool raise @json.JsonDecodeError {
    match fields.get(key) {
      None | Some(Null) => false
      Some(True) => true
      Some(False) => false
      Some(_) =>
        raise @json.JsonDecodeError(
          (path.add_key(key), "subscription filter flag must be boolean"),
        )
    }
  }
  let resource_subscriptions : Array[String] = match
    fields.get("resourceSubscriptions") {
    None | Some(Null) => []
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
    Some(_) =>
      raise @json.JsonDecodeError(
        (
          path.add_key("resourceSubscriptions"),
          "resourceSubscriptions must be an array",
        ),
      )
  }
  {
    tools_list_changed: read_bool("toolsListChanged"),
    prompts_list_changed: read_bool("promptsListChanged"),
    resources_list_changed: read_bool("resourcesListChanged"),
    resource_subscriptions,
  }
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

///|
/// A validated long-lived subscription request. Transports own the stream;
/// this value supplies the required acknowledgement and graceful final reply.
pub struct Subscription {
  id : Json
  notifications : SubscriptionFilter
  priv server_info : Implementation
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
    SubscriptionsListenResult::SubscriptionsListenResult().to_json(),
    server_info=self.server_info,
    meta~,
  )
  let request_id : @jsonrpc.RequestId = try! @json.from_json(self.id)
  @jsonrpc.response_success(id=request_id, result~).to_json()
}

///|
/// Check whether a notification event is targeted at this subscription and
/// allowed by its negotiated notification filter.
pub fn Subscription::allows_event(self : Subscription, event : Json) -> Bool {
  match decode_message_opt(event) {
    Some(Notification({ method_name, params: Object(params) })) => {
      guard params.get("_meta")
        is Some(
          Object({ "io.modelcontextprotocol/subscriptionId": sub_id, .. })
        ) &&
        sub_id == self.id else {
        false
      }
      let filter = self.notifications
      match method_name {
        "notifications/tools/list_changed" => filter.tools_list_changed
        "notifications/prompts/list_changed" => filter.prompts_list_changed
        "notifications/resources/list_changed" => filter.resources_list_changed
        "notifications/resources/updated" =>
          match params.get("uri") {
            Some(String(uri)) => filter.resource_subscriptions.contains(uri)
            _ => false
          }
        _ => false
      }
    }
    _ => false
  }
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
  let decoded = @jsonrpc.decode(message) catch {
    error => raise jsonrpc_error(error)
  }
  let request = match decoded {
    @jsonrpc.Message::Request(request) => request
    _ => raise InvalidRequest("expected subscriptions/listen request")
  }
  if request.method_name != "subscriptions/listen" {
    raise InvalidRequest("expected subscriptions/listen request")
  }
  let context = parse_context(request)
  self.ensure_supported_version(context)
  let fields = expect_object(request.params, "subscriptions/listen params")
  guard fields.get("notifications") is Some(value) else {
    raise InvalidParams("subscriptions/listen params.notifications is required")
  }
  let requested : SubscriptionFilter = @json.from_json(value) catch {
    error => raise InvalidRequest(error.to_string())
  }
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
  { id: request.id.as_json(), notifications: honored, server_info: self.info }
}
