///|
pub struct AuthorizationCode {
  code : String
  issuer : String?
}

///|
/// Validate the redirect against the exact state and RFC 9207 issuer values
/// recorded when the authorization request was created.
pub fn validate_authorization_response(
  callback_uri : String,
  expected_state~ : String,
  expected_issuer~ : String,
  issuer_parameter_required~ : Bool,
  expected_redirect_uri? : String,
) -> AuthorizationCode raise AuthError {
  let callback = parse_absolute_uri(callback_uri)
  let parameters = parse_query(callback.query.unwrap_or(""))
  if expected_redirect_uri is Some(expected) {
    let redirect = parse_absolute_uri(expected)
    if callback.scheme != redirect.scheme ||
      callback.authority != redirect.authority ||
      callback.path != redirect.path {
      raise InvalidAuthorizationResponse("authorization redirect URI mismatch")
    }
    let expected_query = parse_query(redirect.query.unwrap_or(""))
    for name, value in expected_query {
      if parameters.get(name) != Some(value) {
        raise InvalidAuthorizationResponse(
          "authorization redirect query mismatch",
        )
      }
    }
  }
  if parameters.get("state") != Some(expected_state) {
    raise InvalidAuthorizationResponse("authorization state mismatch")
  }
  let issuer = parameters.get("iss")
  if issuer_parameter_required && issuer is None {
    raise InvalidAuthorizationResponse("authorization response omitted iss")
  }
  if issuer is Some(actual) && actual != expected_issuer {
    // RFC 9207 deliberately requires simple string comparison.
    raise InvalidAuthorizationResponse("authorization response issuer mismatch")
  }
  if parameters.get("error") is Some(error) {
    raise AuthorizationFailed("authorization server returned " + error)
  }
  guard parameters.get("code") is Some(code) && !code.is_empty() else {
    raise InvalidAuthorizationResponse("authorization response omitted code")
  }
  { code, issuer }
}
