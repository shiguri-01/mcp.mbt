///|
fn append_unique(values : Array[String], value : String) -> Unit {
  if !values.contains(value) {
    values.push(value)
  }
}

///|
/// Choose initial authorization scopes. A challenge scope is authoritative;
/// otherwise every protected-resource scope is used. `offline_access` is
/// added only when refresh tokens are desired and the authorization server
/// advertises it.
pub fn initial_scopes(
  challenge_scope? : String,
  resource_scopes? : Array[String],
  authorization_server_scopes? : Array[String],
  wants_refresh_token? : Bool = false,
) -> Array[String] {
  let selected = match challenge_scope {
    Some(scope) => scope_words(scope)
    None => resource_scopes.unwrap_or([]).copy()
  }
  if wants_refresh_token &&
    authorization_server_scopes.unwrap_or([]).contains("offline_access") {
    append_unique(selected, "offline_access")
  }
  selected
}

///|
/// Step-up authorization preserves every previously granted/requested scope
/// and adds the current operation's challenge scopes.
pub fn step_up_scopes(
  previous : Array[String],
  challenge_scope : String,
) -> Array[String] {
  let combined = previous.copy()
  for scope in scope_words(challenge_scope) {
    append_unique(combined, scope)
  }
  combined
}

///|
pub struct RetryPolicy {
  priv maximum_attempts : Int
  priv attempts : Map[String, Int]
}

///|
pub fn RetryPolicy::RetryPolicy(
  maximum_attempts? : Int = 3,
) -> RetryPolicy raise AuthError {
  if maximum_attempts <= 0 || maximum_attempts > 3 {
    raise AuthorizationFailed("authorization retry limit must be 1 to 3")
  }
  { maximum_attempts, attempts: Map([]) }
}

///|
pub fn RetryPolicy::record_attempt(
  self : RetryPolicy,
  resource : String,
  operation : String,
) -> Unit raise AuthError {
  let key = resource + "\n" + operation
  let attempts = self.attempts.get(key).unwrap_or(0) + 1
  if attempts > self.maximum_attempts {
    raise RetryLimitExceeded("authorization retry limit exceeded")
  }
  self.attempts[key] = attempts
}

///|
pub fn RetryPolicy::clear(
  self : RetryPolicy,
  resource : String,
  operation : String,
) -> Unit {
  self.attempts.remove(resource + "\n" + operation)
}

///|
pub(all) enum TokenEndpointAuthMethod {
  ClientSecretBasic
  ClientSecretPost
  None
} derive(Debug, Eq)

///|
pub struct ClientCredentials {
  priv client_id : String
  priv client_secret : String?
  priv token_endpoint_auth_method : TokenEndpointAuthMethod
} derive(Eq)

///|
pub fn ClientCredentials::ClientCredentials(
  client_id~ : String,
  client_secret? : String,
  token_endpoint_auth_method? : TokenEndpointAuthMethod = None,
) -> ClientCredentials raise AuthError {
  if client_id.is_empty() {
    raise AuthorizationFailed("client_id must not be empty")
  }
  if token_endpoint_auth_method is (ClientSecretBasic | ClientSecretPost) &&
    client_secret is None {
    raise AuthorizationFailed(
      "confidential token authentication needs a secret",
    )
  }
  { client_id, client_secret, token_endpoint_auth_method }
}

///|
pub fn ClientCredentials::client_id(self : ClientCredentials) -> String {
  self.client_id
}

///|
pub fn ClientCredentials::client_secret(self : ClientCredentials) -> String? {
  self.client_secret
}

///|
pub fn ClientCredentials::token_endpoint_auth_method(
  self : ClientCredentials,
) -> TokenEndpointAuthMethod {
  self.token_endpoint_auth_method
}

///|
/// Credentials are issuer-bound. Looking up a different issuer never falls
/// back to credentials registered with a previous authorization server.
pub struct CredentialCache {
  priv by_issuer : Map[String, ClientCredentials]
}

///|
pub fn CredentialCache::CredentialCache() -> CredentialCache {
  { by_issuer: Map([]) }
}

///|
pub fn CredentialCache::put(
  self : CredentialCache,
  issuer~ : String,
  credentials : ClientCredentials,
) -> Unit {
  self.by_issuer[issuer] = credentials
}

///|
pub fn CredentialCache::get(
  self : CredentialCache,
  issuer : String,
) -> ClientCredentials? {
  self.by_issuer.get(issuer)
}

///|
pub struct OAuthTokens {
  priv access_token : String
  priv token_type : String
  priv refresh_token : String?
  priv scope : Array[String]
  priv expires_in : Int?
}

///|
pub fn OAuthTokens::OAuthTokens(
  access_token~ : String,
  token_type? : String = "Bearer",
  refresh_token? : String,
  scope? : Array[String] = [],
  expires_in? : Int,
) -> OAuthTokens raise AuthError {
  if access_token.is_empty() || !token_type.equal_ignore_ascii_case("Bearer") {
    raise AuthorizationFailed(
      "MCP authorization requires a Bearer access token",
    )
  }
  if expires_in is Some(seconds) && seconds <= 0 {
    raise AuthorizationFailed("expires_in must be positive")
  }
  {
    access_token,
    token_type: "Bearer",
    refresh_token,
    scope: scope.copy(),
    expires_in,
  }
}

///|
pub fn OAuthTokens::authorization_header(self : OAuthTokens) -> String {
  self.token_type + " " + self.access_token
}

///|
pub fn OAuthTokens::access_token(self : OAuthTokens) -> String {
  self.access_token
}

///|
pub fn OAuthTokens::refresh_token(self : OAuthTokens) -> String? {
  self.refresh_token
}

///|
pub fn OAuthTokens::scope(self : OAuthTokens) -> Array[String] {
  self.scope.copy()
}

///|
pub fn OAuthTokens::expires_in(self : OAuthTokens) -> Int? {
  self.expires_in
}

///|
pub struct TokenCache {
  priv values : Map[String, OAuthTokens]
}

///|
pub fn TokenCache::TokenCache() -> TokenCache {
  { values: Map([]) }
}

///|
fn token_cache_key(issuer : String, resource : String) -> String {
  issuer + "\n" + resource
}

///|
pub fn TokenCache::put(
  self : TokenCache,
  issuer~ : String,
  resource~ : String,
  tokens : OAuthTokens,
) -> Unit {
  self.values[token_cache_key(issuer, resource)] = tokens
}

///|
pub fn TokenCache::get(
  self : TokenCache,
  issuer~ : String,
  resource~ : String,
) -> OAuthTokens? {
  self.values.get(token_cache_key(issuer, resource))
}

///|
pub(all) enum RegistrationChoice {
  ClientIdMetadataDocument(String)
  PreRegistered(ClientCredentials)
  Dynamic(String)
} derive(Eq)

///|
pub fn choose_registration(
  metadata : AuthorizationServerMetadata,
  client_id_metadata_url? : String,
  pre_registered? : ClientCredentials,
  allow_insecure_loopback? : Bool = false,
) -> RegistrationChoice raise AuthError {
  if pre_registered is Some(credentials) {
    return PreRegistered(credentials)
  }
  if metadata.client_id_metadata_document_supported() &&
    client_id_metadata_url is Some(url) {
    let document = validate_secure_uri(
      url,
      allow_loopback_http=allow_insecure_loopback,
    )
    if document.path().is_empty() || document.path() == "/" {
      raise UnsupportedRegistration(
        "client metadata document URL must have a non-root path",
      )
    }
    return ClientIdMetadataDocument(url)
  }
  match metadata.registration_endpoint() {
    Some(endpoint) => Dynamic(endpoint)
    None =>
      raise UnsupportedRegistration("no supported client registration method")
  }
}
