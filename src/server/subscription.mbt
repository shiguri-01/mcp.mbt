///|
/// A validated long-lived subscription request. Transports own the stream;
/// this value supplies the required acknowledgement and graceful final reply.
pub struct Subscription {
  id : @jsonrpc.RequestId
  notifications : @mcp.SubscriptionFilter
  priv server_info : @mcp.Implementation
}

///|
pub fn Subscription::acknowledgement(self : Subscription) -> Json {
  @mcp.SubscriptionsAcknowledgedNotification(
    subscription_id=self.id,
    notifications=self.notifications,
  ).to_json()
}

///|
pub fn Subscription::close_response(self : Subscription) -> Json {
  let meta = Map::from_array([
    ("io.modelcontextprotocol/subscriptionId", self.id.as_json()),
  ])
  let result = try! @mcp.ResultMeta(server_info=self.server_info, extra=meta).stamp_complete(
    @mcp.SubscriptionsListenResult().to_json(),
  )
  @jsonrpc.Response::Success(id=self.id, result~).to_json()
}

///|
/// Check whether a notification event is targeted at this subscription and
/// allowed by its negotiated notification filter.
pub fn Subscription::allows_event(self : Subscription, event : Json) -> Bool {
  try {
    let decoded = @jsonrpc.decode(event)
    let notification = match decoded {
      Notification(notification) => notification
      _ => return false
    }
    match notification.method_name {
      "notifications/tools/list_changed" => {
        let params = @mcp.SubscriptionNotificationParams::from_json(
          notification.params,
        )
        params.subscription_id == self.id &&
        self.notifications.tools_list_changed
      }
      "notifications/prompts/list_changed" => {
        let params = @mcp.SubscriptionNotificationParams::from_json(
          notification.params,
        )
        params.subscription_id == self.id &&
        self.notifications.prompts_list_changed
      }
      "notifications/resources/list_changed" => {
        let params = @mcp.SubscriptionNotificationParams::from_json(
          notification.params,
        )
        params.subscription_id == self.id &&
        self.notifications.resources_list_changed
      }
      "notifications/resources/updated" => {
        let params = @mcp.ResourceUpdatedNotificationParams::from_json(
          notification.params,
        )
        params.subscription_id == self.id &&
        self.notifications.resource_subscriptions.contains(params.uri)
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
) -> Subscription raise @mcp.McpError {
  let decoded = @mcp.decode_message(message)
  let request = match decoded {
    @jsonrpc.Message::Request(request) => request
    _ => raise @mcp.InvalidRequest("expected subscriptions/listen request")
  }
  if request.method_name != "subscriptions/listen" {
    raise @mcp.InvalidRequest("expected subscriptions/listen request")
  }
  let context = decode_request_context(request)
  self.ensure_supported_version(context)
  guard request.params is Object(fields) else {
    raise @mcp.InvalidParams("subscriptions/listen params must be an object")
  }
  guard fields.get("notifications") is Some(value) else {
    raise @mcp.InvalidParams(
      "subscriptions/listen params.notifications is required",
    )
  }
  let requested : @mcp.SubscriptionFilter = @json.from_json(value) catch {
    error => raise @mcp.InvalidRequest(error.to_string())
  }
  let honored = @mcp.SubscriptionFilter(
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
