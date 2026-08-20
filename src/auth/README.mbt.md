# shiguri-01/mcp/auth

Native MCP Authorization (RFC 9728, PKCE S256, Dynamic Client Registration).

## Integrating with HTTP Transport

Pass `@http.AuthorizationOptions` to `@http.Transport`:

```moonbit nocheck
let auth_options = try! @http.AuthorizationOptions(
  provider=@auth.AuthorizationProvider::new(...),
  redirect_uri="http://127.0.0.1:8080/callback",
  client_name="My Client",
  wants_refresh_token=true,
)

let transport = try! @http.Transport(
  "https://api.example.com/mcp",
  authorization=Some(auth_options),
)
```
