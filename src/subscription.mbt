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
  let tools_list_changed = match fields {
    { "toolsListChanged": True, .. } => true
    { "toolsListChanged": False | Null, .. } => false
    { "toolsListChanged": _, .. } =>
      raise @json.JsonDecodeError(
        (
          path.add_key("toolsListChanged"),
          "subscription filter flag must be boolean",
        ),
      )
    _ => false
  }
  let prompts_list_changed = match fields {
    { "promptsListChanged": True, .. } => true
    { "promptsListChanged": False | Null, .. } => false
    { "promptsListChanged": _, .. } =>
      raise @json.JsonDecodeError(
        (
          path.add_key("promptsListChanged"),
          "subscription filter flag must be boolean",
        ),
      )
    _ => false
  }
  let resources_list_changed = match fields {
    { "resourcesListChanged": True, .. } => true
    { "resourcesListChanged": False | Null, .. } => false
    { "resourcesListChanged": _, .. } =>
      raise @json.JsonDecodeError(
        (
          path.add_key("resourcesListChanged"),
          "subscription filter flag must be boolean",
        ),
      )
    _ => false
  }
  let resource_subscriptions : Array[String] = match fields {
    { "resourceSubscriptions": Array(values), .. } =>
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
    { "resourceSubscriptions": Null, .. } => []
    { "resourceSubscriptions": _, .. } =>
      raise @json.JsonDecodeError(
        (
          path.add_key("resourceSubscriptions"),
          "resourceSubscriptions must be an array",
        ),
      )
    _ => []
  }
  SubscriptionFilter(
    tools_list_changed~,
    prompts_list_changed~,
    resources_list_changed~,
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
  try {
    guard @jsonrpc.decode(event)
      is Notification(
        {
          method_name,
          params: Object(
            {
              "_meta": Object(
                { "io.modelcontextprotocol/subscriptionId": sub_id, .. }
              ),
              ..
            } as params
          ),
        }
      ) &&
      sub_id == self.id else {
      return false
    }
    let filter = self.notifications
    match method_name {
      "notifications/tools/list_changed" => filter.tools_list_changed
      "notifications/prompts/list_changed" => filter.prompts_list_changed
      "notifications/resources/list_changed" => filter.resources_list_changed
      "notifications/resources/updated" =>
        match params {
          { "uri": String(uri), .. } =>
            filter.resource_subscriptions.contains(uri)
          _ => false
        }
      _ => false
    }
  } catch {
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
  let decoded = decode_message(message)
  let request = match decoded {
    @jsonrpc.Message::Request(request) => request
    _ => raise InvalidRequest("expected subscriptions/listen request")
  }
  if request.method_name != "subscriptions/listen" {
    raise InvalidRequest("expected subscriptions/listen request")
  }
  let context = parse_context(request)
  self.ensure_supported_version(context)
  guard request.params is Object(fields) else {
    raise InvalidParams("subscriptions/listen params must be an object")
  }
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

///|
/// Extract the subscriptionId from a notification's `params._meta`.
pub fn extract_subscription_id(message : Json) -> Json? {
  try {
    guard @jsonrpc.decode(message)
      is Notification(
        {
          params: Object(
            {
              "_meta": Object(
                { "io.modelcontextprotocol/subscriptionId": sub_id, .. }
              ),
              ..
            }
          ),
          ..,
        }
      ) else {
      return None
    }
    Some(sub_id)
  } catch {
    _ => None
  }
}

///|
/// Events observed on a `subscriptions/listen` transport stream.
pub(all) enum SubscriptionStreamEvent {
  Acknowledged
  Notification(Json)
  Final(Json)
} derive(Debug, Eq)

///|
/// Tracks client-side subscription state on a long-lived listen stream.
pub struct SubscriptionStreamState {
  expected_id : Json
  requested : SubscriptionFilter
  mut acknowledged : Bool
  mut subscription_id : Json
  mut honored : SubscriptionFilter
}

///|
pub fn SubscriptionStreamState::new(
  expected_id : Json,
  requested : SubscriptionFilter,
) -> SubscriptionStreamState {
  {
    expected_id,
    requested,
    acknowledged: false,
    subscription_id: Json::null(),
    honored: SubscriptionFilter(),
  }
}

///|
pub fn SubscriptionStreamState::is_acknowledged(
  self : SubscriptionStreamState,
) -> Bool {
  self.acknowledged
}

///|
pub fn SubscriptionStreamState::honored_filter(
  self : SubscriptionStreamState,
) -> SubscriptionFilter {
  self.honored
}

///|
pub fn subscription_filter_is_subset(
  honored : SubscriptionFilter,
  requested : SubscriptionFilter,
) -> Bool {
  (!honored.tools_list_changed || requested.tools_list_changed) &&
  (!honored.prompts_list_changed || requested.prompts_list_changed) &&
  (!honored.resources_list_changed || requested.resources_list_changed) &&
  honored.resource_subscriptions.all(uri => {
    requested.resource_subscriptions.contains(uri)
  })
}

///|
pub fn subscription_notification_allowed(
  subscription_id : Json,
  filter : SubscriptionFilter,
  message : Json,
) -> Bool {
  let decoded = @jsonrpc.decode(message) catch { _ => return false }
  let notification = match decoded {
    @jsonrpc.Message::Notification(notification) => notification
    _ => return false
  }
  let params = match notification.params {
    Object(params) => params
    _ => return false
  }
  let meta = match params {
    { "_meta": Object(meta), .. } => meta
    _ => return false
  }
  guard meta is { "io.modelcontextprotocol/subscriptionId": sub_id, .. } &&
    sub_id == subscription_id else {
    return false
  }
  match notification.method_name {
    "notifications/tools/list_changed" => filter.tools_list_changed
    "notifications/prompts/list_changed" => filter.prompts_list_changed
    "notifications/resources/list_changed" => filter.resources_list_changed
    "notifications/resources/updated" =>
      match params {
        { "uri": String(uri), .. } =>
          filter.resource_subscriptions.contains(uri)
        _ => false
      }
    _ => false
  }
}

///|
/// Consume one incoming frame from a subscription stream and advance its state machine.
pub fn SubscriptionStreamState::consume(
  self : SubscriptionStreamState,
  message : Json,
) -> SubscriptionStreamEvent raise McpError {
  let decoded = @jsonrpc.decode(message) catch {
    _ =>
      raise InvalidRequest(
        "subscription stream received invalid JSON-RPC message",
      )
  }
  if !self.acknowledged {
    let notification = match decoded {
      @jsonrpc.Message::Notification(notification) if notification.method_name ==
        "notifications/subscriptions/acknowledged" => notification
      _ =>
        raise InvalidRequest(
          "subscription stream must start with an acknowledgement",
        )
    }
    let (subscription_id, notifications) = match notification.params {
      Object(
        {
          "_meta": Object(
            { "io.modelcontextprotocol/subscriptionId": sub_id, .. }
          ),
          "notifications": notifications,
          ..
        }
      ) => (sub_id, notifications)
      Object({ "_meta": Object(_), "notifications": _, .. }) =>
        raise InvalidRequest(
          "subscription acknowledgement is missing subscriptionId",
        )
      Object(_) =>
        raise InvalidRequest(
          "subscription acknowledgement is missing _meta or notifications",
        )
      _ =>
        raise InvalidRequest(
          "subscription acknowledgement params must be an object",
        )
    }
    let honored : SubscriptionFilter = @json.from_json(notifications) catch {
      error => raise InvalidRequest(error.to_string())
    }
    if subscription_id != self.expected_id {
      raise InvalidRequest(
        "subscription acknowledgement id does not match request id",
      )
    }
    if !subscription_filter_is_subset(honored, self.requested) {
      raise InvalidRequest(
        "subscription acknowledgement honors an unrequested filter",
      )
    }
    self.acknowledged = true
    self.subscription_id = subscription_id
    self.honored = honored
    return Acknowledged
  }
  match decoded {
    @jsonrpc.Message::Notification(_) => {
      if !subscription_notification_allowed(
          self.subscription_id,
          self.honored,
          message,
        ) {
        raise InvalidRequest(
          "subscription notification does not match the acknowledged subscription",
        )
      }
      Notification(message)
    }
    @jsonrpc.Message::Response(@jsonrpc.Response::Failure(id~, ..)) => {
      if id.map(fn(id) { id.as_json() }) != Some(self.expected_id) {
        raise InvalidRequest(
          "subscription error response id does not match request id",
        )
      }
      Final(message)
    }
    @jsonrpc.Message::Response(@jsonrpc.Response::Success(id~, result~)) => {
      if id.as_json() != self.expected_id {
        raise InvalidRequest(
          "subscription final response does not match the active subscription",
        )
      }
      let sub_id = match result {
        Object(
          {
            "_meta": Object(
              { "io.modelcontextprotocol/subscriptionId": sub_id, .. }
            ),
            ..
          }
        ) => Some(sub_id)
        _ => None
      }
      if sub_id != Some(self.subscription_id) {
        raise InvalidRequest(
          "subscription final response does not match the active subscription",
        )
      }
      Final(message)
    }
    @jsonrpc.Message::Request(_) =>
      raise InvalidRequest("unexpected request on subscription stream")
  }
}
