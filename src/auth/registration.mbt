///|
pub fn dynamic_registration_request(
  metadata : AuthorizationServerMetadata,
  client_name~ : String,
  redirect_uris~ : Array[String],
  wants_refresh_token? : Bool = false,
) -> HttpRequest raise AuthError {
  guard metadata.registration_endpoint is Some(endpoint) else {
    raise UnsupportedRegistration(
      "authorization server has no registration endpoint",
    )
  }
  if client_name.is_empty() || redirect_uris.is_empty() {
    raise UnsupportedRegistration("client name and redirect URI are required")
  }
  for redirect_uri in redirect_uris {
    ignore(parse_absolute_uri(redirect_uri))
  }
  let grants = [Json::string("authorization_code")]
  if wants_refresh_token {
    grants.push(Json::string("refresh_token"))
  }
  let body = Json::object({
    "client_name": Json::string(client_name),
    "redirect_uris": Json::array(redirect_uris.map(Json::string)),
    "response_types": Json::array([Json::string("code")]),
    "grant_types": Json::array(grants),
    "token_endpoint_auth_method": Json::string("none"),
    "application_type": Json::string("native"),
  }).stringify()
  HttpRequest(
    request_method=Post,
    url=endpoint,
    headers=Map([
      ("content-type", "application/json"),
      ("accept", "application/json"),
    ]),
    body~,
  )
}

///|
pub fn parse_dynamic_registration_response(
  value : Json,
  requested_token_endpoint_auth_method? : TokenEndpointAuthMethod = None,
) -> ClientCredentials raise AuthError {
  guard value is Object(fields) else {
    raise UnsupportedRegistration("registration response must be an object")
  }
  let client_id = required_string(fields, "client_id")
  let client_secret = optional_string(fields, "client_secret")
  let method_name = optional_string(fields, "token_endpoint_auth_method")
  let auth_method = match method_name {
    Some("client_secret_basic") => ClientSecretBasic
    Some("client_secret_post") => ClientSecretPost
    Some("none") => None
    Some(_) =>
      raise UnsupportedRegistration(
        "unsupported token endpoint authentication method",
      )
    None => requested_token_endpoint_auth_method
  }
  match client_secret {
    Some(secret) =>
      ClientCredentials(
        client_id~,
        client_secret=secret,
        token_endpoint_auth_method=auth_method,
      )
    None =>
      ClientCredentials(client_id~, token_endpoint_auth_method=auth_method)
  }
}
