///|
/// Authorization policy engine independent of any concrete HTTP client or UI.
pub struct AuthorizationEngine {
  priv provider : AuthorizationProvider
}

///|
pub fn AuthorizationEngine::AuthorizationEngine(
  provider : AuthorizationProvider,
) -> AuthorizationEngine {
  { provider, }
}

///|
/// Run authorization-code + PKCE and exchange the code. The host provider is
/// responsible only for HTTP delivery, user interaction, and secure entropy.
pub async fn AuthorizationEngine::authorize(
  self : AuthorizationEngine,
  metadata : AuthorizationServerMetadata,
  credentials : ClientCredentials,
  redirect_uri~ : String,
  resource~ : String,
  scopes? : Array[String] = [],
  exact_resource? : Bool = false,
) -> OAuthTokens raise AuthError {
  let pkce = self.provider.new_pkce_session()
  let authorization_url = authorization_request_url(
    metadata,
    credentials,
    redirect_uri~,
    resource~,
    pkce~,
    scopes~,
    allow_insecure_loopback=self.provider.allows_insecure_loopback(),
    exact_resource~,
  )
  let callback_uri = self.provider.authorize(authorization_url)
  let code = validate_authorization_response(
    callback_uri,
    expected_state=pkce.state,
    expected_issuer=metadata.issuer,
    issuer_parameter_required=metadata.authorization_response_iss_parameter_supported,
    expected_redirect_uri=redirect_uri,
  )
  let response = self.provider.send(
    authorization_code_token_request(
      metadata,
      credentials,
      code=code.code,
      redirect_uri~,
      code_verifier=pkce.code_verifier,
      resource~,
      exact_resource~,
    ),
  )
  if response.status != 200 {
    raise AuthorizationFailed(
      "token endpoint returned HTTP " + response.status.to_string(),
    )
  }
  let tokens = parse_token_response(response_json(response))
  if !tokens.scope.is_empty() || scopes.is_empty() {
    tokens
  } else {
    match (tokens.refresh_token, tokens.expires_in) {
      (Some(refresh_token), Some(expires_in)) =>
        OAuthTokens(
          access_token=tokens.access_token,
          refresh_token~,
          scope=scopes,
          expires_in~,
        )
      (Some(refresh_token), None) =>
        OAuthTokens(
          access_token=tokens.access_token,
          refresh_token~,
          scope=scopes,
        )
      (None, Some(expires_in)) =>
        OAuthTokens(access_token=tokens.access_token, scope=scopes, expires_in~)
      (None, None) =>
        OAuthTokens(access_token=tokens.access_token, scope=scopes)
    }
  }
}

///|
/// Exchange an issuer- and resource-bound refresh token without reopening the
/// authorization user-agent.
pub async fn AuthorizationEngine::refresh(
  self : AuthorizationEngine,
  metadata : AuthorizationServerMetadata,
  credentials : ClientCredentials,
  refresh_token~ : String,
  resource~ : String,
  scopes? : Array[String] = [],
  exact_resource? : Bool = false,
) -> OAuthTokens raise AuthError {
  let response = self.provider.send(
    refresh_token_request(
      metadata,
      credentials,
      refresh_token~,
      resource~,
      scopes~,
      exact_resource~,
    ),
  )
  if response.status != 200 {
    raise AuthorizationFailed(
      "token endpoint returned HTTP " + response.status.to_string(),
    )
  }
  let refreshed = parse_token_response(response_json(response))
  // RFC 6749 permits omission of refresh_token in a refresh response; keep
  // the bound token instead of silently discarding refresh capability.
  if refreshed.refresh_token is Some(_) && !refreshed.scope.is_empty() {
    refreshed
  } else {
    OAuthTokens(
      access_token=refreshed.access_token,
      refresh_token=refreshed.refresh_token.unwrap_or(refresh_token),
      scope=if refreshed.scope.is_empty() { scopes } else { refreshed.scope },
      expires_in?=refreshed.expires_in,
    )
  }
}
