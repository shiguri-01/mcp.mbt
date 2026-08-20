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
  expected_id : @jsonrpc.RequestId
  requested : @mcp.SubscriptionFilter
  mut acknowledged : Bool
  mut subscription_id : @jsonrpc.RequestId?
  mut honored : @mcp.SubscriptionFilter
}

///|
pub fn SubscriptionStreamState::SubscriptionStreamState(
  expected_id~ : @jsonrpc.RequestId,
  requested~ : @mcp.SubscriptionFilter,
) -> SubscriptionStreamState {
  {
    expected_id,
    requested,
    acknowledged: false,
    subscription_id: None,
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
  subscription_id : @jsonrpc.RequestId,
  filter : @mcp.SubscriptionFilter,
  message : Json,
) -> Bool {
  let decoded = @jsonrpc.decode(message) catch { _ => return false }
  let notification = match decoded {
    @jsonrpc.Message::Notification(notification) => notification
    _ => return false
  }
  match notification.method_name {
    "notifications/tools/list_changed" => {
      let params = @mcp.SubscriptionNotificationParams::from_json(
        notification.params,
      ) catch {
        _ => return false
      }
      params.subscription_id == subscription_id && filter.tools_list_changed
    }
    "notifications/prompts/list_changed" => {
      let params = @mcp.SubscriptionNotificationParams::from_json(
        notification.params,
      ) catch {
        _ => return false
      }
      params.subscription_id == subscription_id && filter.prompts_list_changed
    }
    "notifications/resources/list_changed" => {
      let params = @mcp.SubscriptionNotificationParams::from_json(
        notification.params,
      ) catch {
        _ => return false
      }
      params.subscription_id == subscription_id && filter.resources_list_changed
    }
    "notifications/resources/updated" => {
      let params = @mcp.ResourceUpdatedNotificationParams::from_json(
        notification.params,
      ) catch {
        _ => return false
      }
      params.subscription_id == subscription_id &&
      filter.resource_subscriptions.contains(params.uri)
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
    let ack = @mcp.SubscriptionsAcknowledgedNotificationParams::from_json(
      notification.params,
    ) catch {
      error => raise @mcp.InvalidRequest(error.message())
    }
    if ack.subscription_id != self.expected_id {
      raise @mcp.InvalidRequest(
        "subscription acknowledgement id does not match request id",
      )
    }
    if !subscription_filter_is_subset(ack.notifications, self.requested) {
      raise @mcp.InvalidRequest(
        "subscription acknowledgement honors an unrequested filter",
      )
    }
    self.acknowledged = true
    self.subscription_id = Some(ack.subscription_id)
    self.honored = ack.notifications
    return Acknowledged
  }
  let sub_id = match self.subscription_id {
    Some(id) => id
    None =>
      raise @mcp.InvalidRequest(
        "subscription stream received event before acknowledgement",
      )
  }
  match decoded {
    @jsonrpc.Message::Notification(_) => {
      if !subscription_notification_allowed(sub_id, self.honored, message) {
        raise @mcp.InvalidRequest(
          "subscription notification does not match the acknowledged subscription",
        )
      }
      Notification(message)
    }
    @jsonrpc.Message::Response(@jsonrpc.Response::Failure(id~, ..)) => {
      if id != Some(self.expected_id) {
        raise @mcp.InvalidRequest(
          "subscription error response id does not match request id",
        )
      }
      Final(message)
    }
    @jsonrpc.Message::Response(@jsonrpc.Response::Success(id~, result~)) => {
      if id != self.expected_id {
        raise @mcp.InvalidRequest(
          "subscription final response id does not match request id",
        )
      }
      let meta = match result {
        Object(fields) =>
          match fields.get("_meta") {
            Some(Object(m)) => m
            _ =>
              raise @mcp.InvalidRequest(
                "subscription final response is missing _meta",
              )
          }
        _ =>
          raise @mcp.InvalidRequest(
            "subscription final response result must be an object",
          )
      }
      let sub_json = match meta.get("io.modelcontextprotocol/subscriptionId") {
        Some(v) => v
        None =>
          raise @mcp.InvalidRequest(
            "subscription final response is missing subscriptionId",
          )
      }
      let final_sub_id : @jsonrpc.RequestId = @json.from_json(sub_json) catch {
        _ =>
          raise @mcp.InvalidRequest(
            "subscription final response subscriptionId is invalid",
          )
      }
      if final_sub_id != sub_id {
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
