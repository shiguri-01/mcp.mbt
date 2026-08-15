///|
/// Configuration for the stateless MCP Streamable HTTP endpoint.
pub struct ServerOptions {
  /// Endpoint path that accepts MCP POST requests. Defaults to `/mcp`.
  endpoint_path : String
  /// Allowed `Origin` values. An empty set accepts only a loopback Origin that
  /// exactly matches the request Host authority.
  allowed_origins : Set[String]
  /// Return ordinary requests as request-scoped SSE and forward progress
  /// notifications before the final JSON-RPC response.
  stream_responses : Bool
  /// Maximum UTF-8 byte length of one POST body. Bodies over this limit receive
  /// HTTP 413 before JSON-RPC dispatch.
  max_request_body_bytes : Int
  /// Publish notifications for a validated subscription. The adapter sends
  /// the acknowledgement before invoking this callback and the final response
  /// after it returns.
  on_subscription : async (@server.Subscription, async (Json) -> Unit) -> Unit
  /// Observe a client notification. Notifications are always acknowledged
  /// with HTTP 202 and never receive a JSON-RPC response.
  on_notification : async (Json) -> Unit
}

///|
pub fn ServerOptions::ServerOptions(
  endpoint_path? : String = "/mcp",
  allowed_origins? : Set[String] = Set([]),
  stream_responses? : Bool = false,
  max_request_body_bytes? : Int = default_max_request_body_bytes,
  on_subscription? : async (@server.Subscription, async (Json) -> Unit) -> Unit = (
    _,
    _,
  ) => (),
  on_notification? : async (Json) -> Unit = _ => (),
) -> ServerOptions raise @mcp.McpError {
  if max_request_body_bytes <= 0 {
    raise @mcp.InvalidParams("max_request_body_bytes must be positive")
  }
  {
    endpoint_path,
    allowed_origins,
    stream_responses,
    max_request_body_bytes,
    on_subscription,
    on_notification,
  }
}
