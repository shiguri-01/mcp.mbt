///|
fn base64_url(input : Bytes) -> String {
  @base64_x.encode(input[:], url_safe=true).replace_all(old="=", new="")
}

///|
pub fn pkce_challenge(code_verifier : String) -> String raise AuthError {
  if code_verifier.length() < 43 || code_verifier.length() > 128 {
    raise AuthorizationFailed("PKCE verifier must contain 43 to 128 characters")
  }
  for char in code_verifier {
    if !unreserved(char) {
      raise AuthorizationFailed("PKCE verifier contains an invalid character")
    }
  }
  base64_url(
    Bytes::from_iter(@crypto.sha256(@utf8.encode(code_verifier)).iter()),
  )
}

///|
pub struct PkceSession {
  code_verifier : String
  code_challenge : String
  state : String
}

///|
/// Derive an OAuth PKCE S256 session from caller-provided cryptographic
/// entropy. This deterministic entry point is suitable for tests and hosts
/// with their own secure random source.
pub fn pkce_from_entropy(
  verifier_entropy : Bytes,
  state_entropy : Bytes,
) -> PkceSession raise AuthError {
  if verifier_entropy.length() < 32 || state_entropy.length() < 16 {
    raise AuthorizationFailed("insufficient PKCE or state entropy")
  }
  let code_verifier = base64_url(verifier_entropy)
  if code_verifier.length() < 43 || code_verifier.length() > 128 {
    raise AuthorizationFailed("PKCE verifier must contain 43 to 128 characters")
  }
  {
    code_verifier,
    code_challenge: pkce_challenge(code_verifier),
    state: base64_url(state_entropy),
  }
}
