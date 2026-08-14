///|
let conformance_client_metadata_url : String = "https://conformance-test.local/client-metadata.json"

///|
fn frozen_auth_scenario(scenario : String) -> Bool {
  match scenario {
    "auth/metadata-default"
    | "auth/metadata-var1"
    | "auth/metadata-var2"
    | "auth/metadata-var3"
    | "auth/basic-cimd"
    | "auth/scope-from-www-authenticate"
    | "auth/scope-from-scopes-supported"
    | "auth/scope-omitted-when-undefined"
    | "auth/scope-step-up"
    | "auth/scope-retry-limit"
    | "auth/token-endpoint-auth-basic"
    | "auth/token-endpoint-auth-post"
    | "auth/token-endpoint-auth-none"
    | "auth/pre-registration"
    | "auth/resource-mismatch"
    | "auth/offline-access-scope"
    | "auth/offline-access-not-supported"
    | "auth/authorization-server-migration"
    | "auth/iss-supported"
    | "auth/iss-not-advertised"
    | "auth/iss-supported-missing"
    | "auth/iss-wrong-issuer"
    | "auth/iss-unexpected"
    | "auth/iss-normalized"
    | "auth/metadata-issuer-mismatch" => true
    _ => false
  }
}

///|
async fn pre_registered_credentials(
  provider : @auth.AuthorizationProvider,
  endpoint : String,
) -> Map[String, @auth.ClientCredentials] raise @mcp.McpError {
  let context = parse_pre_registration_context(
    @env.get_env_var("MCP_CONFORMANCE_CONTEXT"),
  )
  let resource = @auth.canonical_resource_uri(endpoint) catch {
    error => raise @mcp.InvalidParams(auth_error_message(error))
  }
  let metadata = @auth.discover_protected_resource_metadata(provider, resource) catch {
    error => raise @mcp.InvalidRequest(auth_error_message(error))
  }
  guard metadata.authorization_servers is [issuer, ..] else {
    raise @mcp.InvalidRequest(
      "pre-registration resource metadata has no authorization server",
    )
  }
  let credentials = @auth.ClientCredentials(
    client_id=context.client_id,
    client_secret=context.client_secret,
    token_endpoint_auth_method=@auth.ClientSecretBasic,
  ) catch {
    error => raise @mcp.InvalidParams(auth_error_message(error))
  }
  Map([(issuer, credentials)])
}

///|
async fn make_auth_client(
  scenario : String,
  endpoint : String,
  protocol_version : String,
) -> @mcp_http.Client raise @mcp.McpError {
  let provider = conformance_authorization_provider()
  let pre_registered = if scenario == "auth/pre-registration" {
    pre_registered_credentials(provider, endpoint)
  } else {
    Map([])
  }
  let authorization = @mcp_http.AuthorizationOptions(
    provider~,
    redirect_uri="http://localhost:3000/callback",
    client_name="moonbit-mcp-conformance-client",
    client_id_metadata_url=conformance_client_metadata_url,
    pre_registered~,
    wants_refresh_token=scenario == "auth/offline-access-scope",
  )
  @mcp_http.Client(
    endpoint,
    name="moonbit-mcp-conformance-client",
    version="2026.7.28",
    capabilities=conformance_capabilities(),
    supported_protocol_versions=[protocol_version, @mcp.latest_protocol_version],
    authorization~,
  )
}

///|
async fn run_auth_scenario(
  scenario : String,
  endpoint : String,
  protocol_version : String,
) -> Unit raise @mcp.McpError {
  if !frozen_auth_scenario(scenario) {
    abort("Unsupported authorization conformance scenario: \{scenario}")
  }
  let client = make_auth_client(scenario, endpoint, protocol_version)
  ignore(client.list_tools())
  ignore(client.call_tool(name="test-tool", arguments=Json::object({})))
}
