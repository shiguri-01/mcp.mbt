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
  guard response.header("Content-Type") is Some(content_type) else {
    raise InvalidMetadata("JSON response omitted Content-Type")
  }
  let media_type = content_type
    .split_once(";")
    .map(pair => pair.0.trim().to_owned())
    .unwrap_or(content_type.trim().to_owned())
  if !media_type.equal_ignore_ascii_case("application/json") {
    raise InvalidMetadata(
      "JSON response must use application/json Content-Type",
    )
  }
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
  exact_resource? : Bool = false,
) -> ProtectedResourceMetadata raise AuthError {
  let challenge_metadata = match challenge {
    Some(item) => item.resource_metadata()
    None => None
  }
  let using_generated_candidates = challenge_metadata is None
  let candidates = match challenge_metadata {
    Some(url) => {
      ignore(parse_absolute_uri(url))
      [url]
    }
    None => protected_resource_metadata_urls(resource_uri)
  }
  let origin_fallback = protected_resource_metadata_urls(resource_uri).last()
  for url in candidates {
    let response = provider.send(discovery_get(url))
    if response.status() == 200 {
      return parse_protected_resource_metadata(
        response_json(response),
        expected_resource=resource_uri,
        allow_insecure_loopback=provider.allows_insecure_loopback(),
        exact_resource~,
        allow_same_origin_root=using_generated_candidates &&
          origin_fallback == Some(url),
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
        allow_insecure_loopback=provider.allows_insecure_loopback(),
      )
    }
  }
  raise InvalidMetadata("authorization server metadata discovery failed")
}
