///|
pub fn authorization_request_url(
  metadata : AuthorizationServerMetadata,
  credentials : ClientCredentials,
  redirect_uri~ : String,
  resource~ : String,
  pkce~ : PkceSession,
  scopes? : Array[String] = [],
  allow_insecure_loopback? : Bool = false,
  exact_resource? : Bool = false,
) -> String raise AuthError {
  ignore(
    validate_secure_uri(
      redirect_uri,
      allow_loopback_http=allow_insecure_loopback,
    ),
  )
  let parameters = [
    ("response_type", "code"),
    ("client_id", credentials.client_id()),
    ("redirect_uri", redirect_uri),
    ("code_challenge", pkce.code_challenge()),
    ("code_challenge_method", "S256"),
    ("state", pkce.state()),
    ("resource", resource_parameter(resource, exact_resource)),
  ]
  if !scopes.is_empty() {
    parameters.push(("scope", scopes.join(" ")))
  }
  append_query(metadata.authorization_endpoint(), parameters)
}

///|
fn resource_parameter(
  resource : String,
  exact_resource : Bool,
) -> String raise AuthError {
  if exact_resource {
    ignore(parse_absolute_uri(resource))
    resource
  } else {
    canonical_resource_uri(resource)
  }
}

///|
fn basic_credentials(credentials : ClientCredentials) -> String {
  let user = form_encode_component(credentials.client_id())
  let password = form_encode_component(
    credentials.client_secret().unwrap_or(""),
  )
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
  exact_resource? : Bool = false,
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
    ("resource", resource_parameter(resource, exact_resource)),
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
    body=encode_form_parameters(parameters),
  )
}

///|
pub fn refresh_token_request(
  metadata : AuthorizationServerMetadata,
  credentials : ClientCredentials,
  refresh_token~ : String,
  resource~ : String,
  scopes? : Array[String] = [],
  exact_resource? : Bool = false,
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
    ("grant_type", "refresh_token"),
    ("refresh_token", refresh_token),
    ("resource", resource_parameter(resource, exact_resource)),
  ]
  if !scopes.is_empty() {
    parameters.push(("scope", scopes.join(" ")))
  }
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
    body=encode_form_parameters(parameters),
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
  let expires_in = match fields.get("expires_in") {
    Some(Number(value, ..)) if value >= 1.0 && value == value.floor() =>
      Some(value.to_int())
    Some(_) =>
      raise AuthorizationFailed("expires_in must be a positive integer")
    None => None
  }
  match (optional_string(fields, "refresh_token"), expires_in) {
    (Some(refresh_token), Some(expires_in)) =>
      OAuthTokens(
        access_token~,
        token_type~,
        refresh_token~,
        scope~,
        expires_in~,
      )
    (Some(refresh_token), None) =>
      OAuthTokens(access_token~, token_type~, refresh_token~, scope~)
    (None, Some(expires_in)) =>
      OAuthTokens(access_token~, token_type~, scope~, expires_in~)
    (None, None) => OAuthTokens(access_token~, token_type~, scope~)
  }
}
