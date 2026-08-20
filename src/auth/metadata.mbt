///|
pub struct ProtectedResourceMetadata {
  resource : String
  authorization_servers : Array[String]
  scopes_supported : Array[String]?
}

///|
fn string_array(
  fields : Map[String, Json],
  name : String,
  required : Bool,
) -> Array[String]? raise AuthError {
  match fields.get(name) {
    Some(Array(values)) => {
      let result : Array[String] = []
      for value in values {
        match value {
          String(item) => result.push(item)
          _ => raise InvalidMetadata(name + " must contain only strings")
        }
      }
      Some(result)
    }
    Some(_) => raise InvalidMetadata(name + " must be an array")
    None if required => raise InvalidMetadata(name + " is required")
    None => None
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  name : String,
) -> String raise AuthError {
  match fields.get(name) {
    Some(String(value)) if !value.is_empty() => value
    Some(_) => raise InvalidMetadata(name + " must be a non-empty string")
    None => raise InvalidMetadata(name + " is required")
  }
}

///|
fn optional_string(
  fields : Map[String, Json],
  name : String,
) -> String? raise AuthError {
  match fields.get(name) {
    Some(String(value)) if !value.is_empty() => Some(value)
    Some(_) => raise InvalidMetadata(name + " must be a non-empty string")
    None => None
  }
}

///|
fn optional_bool(
  fields : Map[String, Json],
  name : String,
) -> Bool? raise AuthError {
  match fields.get(name) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(_) => raise InvalidMetadata(name + " must be a boolean")
    None => None
  }
}

///|
pub fn ProtectedResourceMetadata::from_json(
  value : Json,
  expected_resource~ : String,
  allow_insecure_loopback? : Bool = false,
  exact_resource? : Bool = false,
  allow_same_origin_root? : Bool = false,
) -> ProtectedResourceMetadata raise AuthError {
  guard value is Object(fields) else {
    raise InvalidMetadata("protected resource metadata must be an object")
  }
  let resource = required_string(fields, "resource")
  let resource_matches = if exact_resource {
    resource == expected_resource
  } else {
    resource_identifiers_match(resource, expected_resource)
  }
  let root_fallback_matches = if allow_same_origin_root {
    let actual = AbsoluteUri::parse(resource)
    let expected = AbsoluteUri::parse(expected_resource)
    actual.scheme.equal_ignore_ascii_case(expected.scheme) &&
    actual.authority.equal_ignore_ascii_case(expected.authority) &&
    (actual.path.is_empty() || actual.path == "/") &&
    actual.query is None
  } else {
    false
  }
  if !resource_matches && !root_fallback_matches {
    raise InvalidMetadata("protected resource metadata resource mismatch")
  }
  let authorization_servers = string_array(
    fields, "authorization_servers", true,
  ).unwrap()
  if authorization_servers.is_empty() {
    raise InvalidMetadata("authorization_servers must not be empty")
  }
  for issuer in authorization_servers {
    ignore(
      validate_secure_uri(issuer, allow_loopback_http=allow_insecure_loopback),
    )
  }
  {
    resource,
    authorization_servers,
    scopes_supported: string_array(fields, "scopes_supported", false),
  }
}

///|
pub struct AuthorizationServerMetadata {
  issuer : String
  authorization_endpoint : String
  token_endpoint : String
  registration_endpoint : String?
  scopes_supported : Array[String]?
  token_endpoint_auth_methods_supported : Array[String]
  client_id_metadata_document_supported : Bool
  authorization_response_iss_parameter_supported : Bool
  code_challenge_methods_supported : Array[String]
}

///|
pub fn AuthorizationServerMetadata::from_json(
  value : Json,
  expected_issuer~ : String,
  allow_insecure_loopback? : Bool = false,
) -> AuthorizationServerMetadata raise AuthError {
  guard value is Object(fields) else {
    raise InvalidMetadata("authorization server metadata must be an object")
  }
  let issuer = required_string(fields, "issuer")
  // RFC 9207 requires simple string comparison: never URL-normalize here.
  if issuer != expected_issuer {
    raise InvalidMetadata("authorization server metadata issuer mismatch")
  }
  ignore(
    validate_secure_uri(issuer, allow_loopback_http=allow_insecure_loopback),
  )
  let authorization_endpoint = required_string(fields, "authorization_endpoint")
  let token_endpoint = required_string(fields, "token_endpoint")
  ignore(
    validate_secure_uri(
      authorization_endpoint,
      allow_loopback_http=allow_insecure_loopback,
    ),
  )
  ignore(
    validate_secure_uri(
      token_endpoint,
      allow_loopback_http=allow_insecure_loopback,
    ),
  )
  let registration_endpoint = optional_string(fields, "registration_endpoint")
  if registration_endpoint is Some(endpoint) {
    ignore(
      validate_secure_uri(endpoint, allow_loopback_http=allow_insecure_loopback),
    )
  }
  let code_challenge_methods_supported = string_array(
    fields, "code_challenge_methods_supported", true,
  ).unwrap()
  if !code_challenge_methods_supported.contains("S256") {
    raise InvalidMetadata("authorization server must support PKCE S256")
  }
  {
    issuer,
    authorization_endpoint,
    token_endpoint,
    registration_endpoint,
    scopes_supported: string_array(fields, "scopes_supported", false),
    token_endpoint_auth_methods_supported: string_array(
      fields, "token_endpoint_auth_methods_supported", false,
    ).unwrap_or(["none"]),
    client_id_metadata_document_supported: optional_bool(
      fields, "client_id_metadata_document_supported",
    ).unwrap_or(false),
    authorization_response_iss_parameter_supported: optional_bool(
      fields, "authorization_response_iss_parameter_supported",
    ).unwrap_or(false),
    code_challenge_methods_supported,
  }
}
