///|
struct PreRegistrationContext {
  client_id : String
  client_secret : String
}

///|
fn parse_pre_registration_context(
  raw : String?,
) -> PreRegistrationContext raise @mcp.McpError {
  guard raw is Some(raw) else {
    raise @mcp.InvalidParams(
      "MCP_CONFORMANCE_CONTEXT is required for auth/pre-registration",
    )
  }
  let context : Json = @json.parse(raw) catch {
    error => raise @mcp.InvalidParams(error.to_string())
  }
  guard context
    is Object(
      {
        "name": String("auth/pre-registration"),
        "client_id": String(client_id),
        "client_secret": String(client_secret),
        ..
      }
    ) &&
    !client_id.is_empty() &&
    !client_secret.is_empty() else {
    raise @mcp.InvalidParams(
      "auth/pre-registration context needs matching name, client_id, and client_secret",
    )
  }
  { client_id, client_secret }
}
