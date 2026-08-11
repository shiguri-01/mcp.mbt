///|
/// Errors raised while discovering or executing MCP HTTP authorization.
pub(all) suberror AuthError {
  InvalidUri(String)
  InvalidChallenge(String)
  InvalidMetadata(String)
  InvalidAuthorizationResponse(String)
  UnsupportedRegistration(String)
  TransportFailure(String)
  AuthorizationFailed(String)
  RetryLimitExceeded(String)
} derive(Debug, Eq)
