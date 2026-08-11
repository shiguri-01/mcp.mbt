///|
pub struct AuthorizationCode {
  priv code : String
  priv issuer : String?
}

///|
pub fn AuthorizationCode::code(self : AuthorizationCode) -> String {
  self.code
}

///|
pub fn AuthorizationCode::issuer(self : AuthorizationCode) -> String? {
  self.issuer
}

///|
/// Validate the redirect against the exact state and RFC 9207 issuer values
/// recorded when the authorization request was created.
pub fn validate_authorization_response(
  callback_uri : String,
  expected_state~ : String,
  expected_issuer~ : String,
  issuer_parameter_required~ : Bool,
) -> AuthorizationCode raise AuthError {
  let callback = parse_absolute_uri(callback_uri)
  let parameters = parse_query(callback.query().unwrap_or(""))
  if parameters.get("state") != Some(expected_state) {
    raise InvalidAuthorizationResponse("authorization state mismatch")
  }
  if parameters.get("error") is Some(error) {
    raise AuthorizationFailed("authorization server returned " + error)
  }
  let issuer = parameters.get("iss")
  if issuer_parameter_required && issuer is None {
    raise InvalidAuthorizationResponse("authorization response omitted iss")
  }
  if issuer is Some(actual) && actual != expected_issuer {
    // RFC 9207 deliberately requires simple string comparison.
    raise InvalidAuthorizationResponse("authorization response issuer mismatch")
  }
  guard parameters.get("code") is Some(code) && !code.is_empty() else {
    raise InvalidAuthorizationResponse("authorization response omitted code")
  }
  { code, issuer }
}
