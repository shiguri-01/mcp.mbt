///|
pub struct ProtectedResourceMetadata {
  priv resource : String
  priv authorization_servers : Array[String]
  priv scopes_supported : Array[String]?
}

///|
pub fn ProtectedResourceMetadata::resource(
  self : ProtectedResourceMetadata,
) -> String {
  self.resource
}

///|
pub fn ProtectedResourceMetadata::authorization_servers(
  self : ProtectedResourceMetadata,
) -> Array[String] {
  self.authorization_servers.copy()
}

///|
pub fn ProtectedResourceMetadata::scopes_supported(
  self : ProtectedResourceMetadata,
) -> Array[String]? {
  self.scopes_supported.map(values => values.copy())
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
pub fn parse_protected_resource_metadata(
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
    let actual = parse_absolute_uri(resource)
    let expected = parse_absolute_uri(expected_resource)
    actual.scheme().equal_ignore_ascii_case(expected.scheme()) &&
    actual.authority().equal_ignore_ascii_case(expected.authority()) &&
    (actual.path().is_empty() || actual.path() == "/") &&
    actual.query() is None
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
  priv issuer : String
  priv authorization_endpoint : String
  priv token_endpoint : String
  priv registration_endpoint : String?
  priv scopes_supported : Array[String]?
  priv token_endpoint_auth_methods_supported : Array[String]
  priv client_id_metadata_document_supported : Bool
  priv authorization_response_iss_parameter_supported : Bool
  priv code_challenge_methods_supported : Array[String]
}

///|
pub fn AuthorizationServerMetadata::issuer(
  self : AuthorizationServerMetadata,
) -> String {
  self.issuer
}

///|
pub fn AuthorizationServerMetadata::authorization_endpoint(
  self : AuthorizationServerMetadata,
) -> String {
  self.authorization_endpoint
}

///|
pub fn AuthorizationServerMetadata::token_endpoint(
  self : AuthorizationServerMetadata,
) -> String {
  self.token_endpoint
}

///|
pub fn AuthorizationServerMetadata::registration_endpoint(
  self : AuthorizationServerMetadata,
) -> String? {
  self.registration_endpoint
}

///|
pub fn AuthorizationServerMetadata::scopes_supported(
  self : AuthorizationServerMetadata,
) -> Array[String]? {
  self.scopes_supported.map(values => values.copy())
}

///|
pub fn AuthorizationServerMetadata::token_endpoint_auth_methods_supported(
  self : AuthorizationServerMetadata,
) -> Array[String] {
  self.token_endpoint_auth_methods_supported.copy()
}

///|
pub fn AuthorizationServerMetadata::client_id_metadata_document_supported(
  self : AuthorizationServerMetadata,
) -> Bool {
  self.client_id_metadata_document_supported
}

///|
pub fn AuthorizationServerMetadata::authorization_response_iss_parameter_supported(
  self : AuthorizationServerMetadata,
) -> Bool {
  self.authorization_response_iss_parameter_supported
}

///|
pub fn AuthorizationServerMetadata::code_challenge_methods_supported(
  self : AuthorizationServerMetadata,
) -> Array[String] {
  self.code_challenge_methods_supported.copy()
}

///|
pub fn parse_authorization_server_metadata(
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
