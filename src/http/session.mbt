///|
/// Configuration for the stateless MCP Streamable HTTP endpoint.
pub(all) struct ServerOptions {
  /// Endpoint path that accepts MCP POST requests. Defaults to `/mcp`.
  endpoint_path : String
  /// Allowed `Origin` values. An empty set rejects any present Origin.
  allowed_origins : Set[String]
  /// Return ordinary requests as request-scoped SSE and forward progress
  /// notifications before the final JSON-RPC response.
  stream_responses : Bool
  /// Publish notifications for a validated subscription. The adapter sends
  /// the acknowledgement before invoking this callback and the final response
  /// after it returns.
  on_subscription : async (@mcp.Subscription, async (Json) -> Unit) -> Unit
  /// Observe a client notification. Notifications are always acknowledged
  /// with HTTP 202 and never receive a JSON-RPC response.
  on_notification : async (Json) -> Unit
}

///|
pub fn ServerOptions::ServerOptions(
  endpoint_path? : String = "/mcp",
  allowed_origins? : Set[String] = Set([]),
  stream_responses? : Bool = false,
  on_subscription? : async (@mcp.Subscription, async (Json) -> Unit) -> Unit = (
    _,
    _,
  ) => (),
  on_notification? : async (Json) -> Unit = _ => (),
) -> ServerOptions {
  {
    endpoint_path,
    allowed_origins,
    stream_responses,
    on_subscription,
    on_notification,
  }
}
