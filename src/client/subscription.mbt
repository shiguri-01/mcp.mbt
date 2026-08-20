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
  requested : @mcp.SubscriptionFilter
  mut acknowledged : Bool
  mut subscription_id : Json
  mut honored : @mcp.SubscriptionFilter
}

///|
pub fn SubscriptionStreamState::SubscriptionStreamState(
  expected_id~ : Json,
  requested~ : @mcp.SubscriptionFilter,
) -> SubscriptionStreamState {
  {
    expected_id,
    requested,
    acknowledged: false,
    subscription_id: Json::null(),
    honored: @mcp.SubscriptionFilter(),
  }
}

///|
fn subscription_filter_is_subset(
  honored : @mcp.SubscriptionFilter,
  requested : @mcp.SubscriptionFilter,
) -> Bool {
  (!honored.tools_list_changed || requested.tools_list_changed) &&
  (!honored.prompts_list_changed || requested.prompts_list_changed) &&
  (!honored.resources_list_changed || requested.resources_list_changed) &&
  honored.resource_subscriptions.all(uri => {
    requested.resource_subscriptions.contains(uri)
  })
}

///|
fn subscription_notification_allowed(
  subscription_id : Json,
  filter : @mcp.SubscriptionFilter,
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
) -> SubscriptionStreamEvent raise @mcp.McpError {
  let decoded = @jsonrpc.decode(message) catch {
    _ =>
      raise @mcp.InvalidRequest(
        "subscription stream received invalid JSON-RPC message",
      )
  }
  if !self.acknowledged {
    let notification = match decoded {
      @jsonrpc.Message::Notification(notification) if notification.method_name ==
        "notifications/subscriptions/acknowledged" => notification
      _ =>
        raise @mcp.InvalidRequest(
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
        raise @mcp.InvalidRequest(
          "subscription acknowledgement is missing subscriptionId",
        )
      Object(_) =>
        raise @mcp.InvalidRequest(
          "subscription acknowledgement is missing _meta or notifications",
        )
      _ =>
        raise @mcp.InvalidRequest(
          "subscription acknowledgement params must be an object",
        )
    }
    let honored : @mcp.SubscriptionFilter = @json.from_json(notifications) catch {
      error => raise @mcp.InvalidRequest(error.to_string())
    }
    if subscription_id != self.expected_id {
      raise @mcp.InvalidRequest(
        "subscription acknowledgement id does not match request id",
      )
    }
    if !subscription_filter_is_subset(honored, self.requested) {
      raise @mcp.InvalidRequest(
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
        raise @mcp.InvalidRequest(
          "subscription notification does not match the acknowledged subscription",
        )
      }
      Notification(message)
    }
    @jsonrpc.Message::Response(@jsonrpc.Response::Failure(id~, ..)) => {
      if id.map(fn(id) { id.as_json() }) != Some(self.expected_id) {
        raise @mcp.InvalidRequest(
          "subscription error response id does not match request id",
        )
      }
      Final(message)
    }
    @jsonrpc.Message::Response(@jsonrpc.Response::Success(id~, result~)) => {
      if id.as_json() != self.expected_id {
        raise @mcp.InvalidRequest(
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
        raise @mcp.InvalidRequest(
          "subscription final response does not match the active subscription",
        )
      }
      Final(message)
    }
    @jsonrpc.Message::Request(_) =>
      raise @mcp.InvalidRequest("unexpected request on subscription stream")
  }
}
