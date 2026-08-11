///|
pub fn authorization_request_url(
  metadata : AuthorizationServerMetadata,
  credentials : ClientCredentials,
  redirect_uri~ : String,
  resource~ : String,
  pkce~ : PkceSession,
  scopes? : Array[String] = [],
) -> String raise AuthError {
  ignore(parse_absolute_uri(redirect_uri))
  let parameters = [
    ("response_type", "code"),
    ("client_id", credentials.client_id()),
    ("redirect_uri", redirect_uri),
    ("code_challenge", pkce.code_challenge()),
    ("code_challenge_method", "S256"),
    ("state", pkce.state()),
    ("resource", canonical_resource_uri(resource)),
  ]
  if !scopes.is_empty() {
    parameters.push(("scope", scopes.join(" ")))
  }
  append_query(metadata.authorization_endpoint(), parameters)
}

///|
fn basic_credentials(credentials : ClientCredentials) -> String {
  let user = percent_encode(credentials.client_id())
  let password = percent_encode(credentials.client_secret().unwrap_or(""))
  "Basic " + @base64.encode(@utf8.encode(user + ":" + password))
}

///|
pub fn authorization_code_token_request(
  metadata : AuthorizationServerMetadata,
  credentials : ClientCredentials,
  code~ : String,
  redirect_uri~ : String,
  code_verifier~ : String,
  resource~ : String,
) -> HttpRequest raise AuthError {
  let auth_method_name = match credentials.token_endpoint_auth_method() {
    ClientSecretBasic => "client_secret_basic"
    ClientSecretPost => "client_secret_post"
    None => "none"
  }
  if !metadata
    .token_endpoint_auth_methods_supported()
    .contains(auth_method_name) {
    raise AuthorizationFailed(
      "client token authentication is not supported by the authorization server",
    )
  }
  let parameters = [
    ("grant_type", "authorization_code"),
    ("code", code),
    ("redirect_uri", redirect_uri),
    ("code_verifier", code_verifier),
    ("resource", canonical_resource_uri(resource)),
  ]
  let headers : Map[String, String] = Map([
    ("content-type", "application/x-www-form-urlencoded"),
    ("accept", "application/json"),
  ])
  match credentials.token_endpoint_auth_method() {
    ClientSecretBasic =>
      headers["authorization"] = basic_credentials(credentials)
    ClientSecretPost => {
      parameters.push(("client_id", credentials.client_id()))
      parameters.push(("client_secret", credentials.client_secret().unwrap()))
    }
    None => parameters.push(("client_id", credentials.client_id()))
  }
  HttpRequest(
    request_method=Post,
    url=metadata.token_endpoint(),
    headers~,
    body=encode_parameters(parameters),
  )
}

///|
pub fn parse_token_response(value : Json) -> OAuthTokens raise AuthError {
  guard value is Object(fields) else {
    raise AuthorizationFailed("token response must be an object")
  }
  let access_token = required_string(fields, "access_token")
  let token_type = optional_string(fields, "token_type").unwrap_or("Bearer")
  let scope = scope_words(optional_string(fields, "scope").unwrap_or(""))
  match optional_string(fields, "refresh_token") {
    Some(refresh_token) =>
      OAuthTokens(access_token~, token_type~, refresh_token~, scope~)
    None => OAuthTokens(access_token~, token_type~, scope~)
  }
}
