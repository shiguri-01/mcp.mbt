///|
fn discovery_get(url : String) -> HttpRequest raise AuthError {
  HttpRequest(
    request_method=Get,
    url~,
    headers=Map([("accept", "application/json")]),
  )
}

///|
fn response_json(response : HttpResponse) -> Json raise AuthError {
  @json.parse(response.body()) catch {
    _ => raise InvalidMetadata("metadata response is not valid JSON")
  }
}

///|
/// Discover RFC 9728 metadata. A challenge-provided metadata URL is
/// authoritative; otherwise path-specific and origin-wide locations are tried.
pub async fn discover_protected_resource_metadata(
  provider : AuthorizationProvider,
  resource_uri : String,
  challenge? : BearerChallenge,
) -> ProtectedResourceMetadata raise AuthError {
  let challenge_metadata = match challenge {
    Some(item) => item.resource_metadata()
    None => None
  }
  let candidates = match challenge_metadata {
    Some(url) => {
      ignore(parse_absolute_uri(url))
      [url]
    }
    None => protected_resource_metadata_urls(resource_uri)
  }
  for url in candidates {
    let response = provider.send(discovery_get(url))
    if response.status() == 200 {
      return parse_protected_resource_metadata(
        response_json(response),
        expected_resource=resource_uri,
      )
    }
  }
  raise InvalidMetadata("protected resource metadata discovery failed")
}

///|
/// Discover authorization-server metadata in RFC 8414 then OpenID Connect
/// order. The metadata issuer must exactly equal the selected issuer.
pub async fn discover_authorization_server_metadata(
  provider : AuthorizationProvider,
  issuer : String,
) -> AuthorizationServerMetadata raise AuthError {
  for url in authorization_server_metadata_urls(issuer) {
    let response = provider.send(discovery_get(url))
    if response.status() == 200 {
      return parse_authorization_server_metadata(
        response_json(response),
        expected_issuer=issuer,
      )
    }
  }
  raise InvalidMetadata("authorization server metadata discovery failed")
}
