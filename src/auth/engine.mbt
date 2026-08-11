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
) -> OAuthTokens raise AuthError {
  let pkce = self.provider.new_pkce_session()
  let authorization_url = authorization_request_url(
    metadata,
    credentials,
    redirect_uri~,
    resource~,
    pkce~,
    scopes~,
  )
  let callback_uri = self.provider.authorize(authorization_url)
  let code = validate_authorization_response(
    callback_uri,
    expected_state=pkce.state(),
    expected_issuer=metadata.issuer(),
    issuer_parameter_required=metadata.authorization_response_iss_parameter_supported(),
  )
  let response = self.provider.send(
    authorization_code_token_request(
      metadata,
      credentials,
      code=code.code(),
      redirect_uri~,
      code_verifier=pkce.code_verifier(),
      resource~,
    ),
  )
  if response.status() != 200 {
    raise AuthorizationFailed(
      "token endpoint returned HTTP " + response.status().to_string(),
    )
  }
  parse_token_response(response_json(response))
}
