///|
pub struct AbsoluteUri {
  priv scheme : String
  priv authority : String
  priv path : String
  priv query : String?
}

///|
pub fn AbsoluteUri::scheme(self : AbsoluteUri) -> String {
  self.scheme
}

///|
pub fn AbsoluteUri::authority(self : AbsoluteUri) -> String {
  self.authority
}

///|
pub fn AbsoluteUri::path(self : AbsoluteUri) -> String {
  self.path
}

///|
pub fn AbsoluteUri::query(self : AbsoluteUri) -> String? {
  self.query
}

///|
pub fn AbsoluteUri::to_string(self : AbsoluteUri) -> String {
  let base = self.scheme + "://" + self.authority + self.path
  match self.query {
    Some(query) => base + "?" + query
    None => base
  }
}

///|
fn valid_scheme(scheme : String) -> Bool {
  guard scheme is [first, .. rest] else { return false }
  if !(first is ('a'..='z' | 'A'..='Z')) {
    return false
  }
  for char in rest {
    if !(char is ('a'..='z' | 'A'..='Z' | '0'..='9' | '+' | '-' | '.')) {
      return false
    }
  }
  true
}

///|
/// Parse the absolute hierarchical URI shape used by MCP HTTP authorization.
/// User-info and fragments are rejected to keep credential destinations
/// unambiguous.
pub fn parse_absolute_uri(value : String) -> AbsoluteUri raise AuthError {
  if value.contains("#"[:]) {
    raise InvalidUri("URI fragments are not allowed")
  }
  guard value.split_once("://") is Some((scheme_view, remainder_view)) else {
    raise InvalidUri("absolute URI must contain a scheme and authority")
  }
  let scheme = scheme_view.to_owned()
  let remainder = remainder_view.to_owned()
  if !valid_scheme(scheme) {
    raise InvalidUri("invalid URI scheme")
  }
  let (without_query, query) = match remainder.split_once("?") {
    Some((head, tail)) => (head.to_owned(), Some(tail.to_owned()))
    None => (remainder, None)
  }
  let (authority, path) = match without_query.find("/") {
    Some(index) =>
      (without_query[:index].to_owned(), without_query[index:].to_owned())
    None => (without_query, "")
  }
  if authority.is_empty() || authority.contains("@"[:]) {
    raise InvalidUri("URI authority must be non-empty and omit user-info")
  }
  { scheme, authority, path, query }
}

///|
fn origin(uri : AbsoluteUri) -> String {
  uri.scheme + "://" + uri.authority
}

///|
fn path_without_trailing_slash(path : String) -> String {
  if path.length() > 1 && path.has_suffix("/"[:]) {
    path[:path.length() - 1].to_owned()
  } else {
    path
  }
}

///|
/// Return the canonical RFC 8707 resource identifier for an MCP endpoint.
/// Scheme and authority are lower-cased; the endpoint path and query remain
/// significant, and fragments are rejected by parsing.
pub fn canonical_resource_uri(value : String) -> String raise AuthError {
  let uri = parse_absolute_uri(value)
  let path = path_without_trailing_slash(uri.path)
  let base = uri.scheme.to_lower() + "://" + uri.authority.to_lower() + path
  match uri.query {
    Some(query) => base + "?" + query
    None => base
  }
}

///|
pub fn resource_identifiers_match(
  left : String,
  right : String,
) -> Bool raise AuthError {
  canonical_resource_uri(left) == canonical_resource_uri(right)
}

///|
/// Protected Resource Metadata discovery order from RFC 9728: the endpoint
/// path-specific location precedes the origin-wide fallback.
pub fn protected_resource_metadata_urls(
  resource_uri : String,
) -> Array[String] raise AuthError {
  let uri = parse_absolute_uri(resource_uri)
  let suffix = path_without_trailing_slash(uri.path)
  let path_specific = origin(uri) +
    "/.well-known/oauth-protected-resource" +
    suffix
  let path_specific = match uri.query {
    Some(query) => path_specific + "?" + query
    None => path_specific
  }
  let root = origin(uri) + "/.well-known/oauth-protected-resource"
  if path_specific == root {
    [root]
  } else {
    [path_specific, root]
  }
}

///|
/// OAuth Authorization Server Metadata is tried before OpenID Connect
/// discovery. Issuer path components are placed according to each standard.
pub fn authorization_server_metadata_urls(
  issuer : String,
) -> Array[String] raise AuthError {
  let uri = parse_absolute_uri(issuer)
  let issuer_path = path_without_trailing_slash(uri.path)
  [
    origin(uri) + "/.well-known/oauth-authorization-server" + issuer_path,
    origin(uri) + "/.well-known/openid-configuration" + issuer_path,
    origin(uri) + issuer_path + "/.well-known/openid-configuration",
  ]
}

///|
fn authority_host(authority : String) -> String {
  let lower = authority.to_lower()
  if lower.has_prefix("["[:]) && lower.find("]") is Some(end) {
    lower[:end + 1].to_owned()
  } else {
    lower.split_once(":").map(pair => pair.0.to_owned()).unwrap_or(lower)
  }
}

///|
fn loopback_authority(authority : String) -> Bool {
  let host = authority_host(authority)
  host == "localhost" || host == "127.0.0.1" || host == "[::1]"
}

///|
fn private_literal_authority(authority : String) -> Bool {
  let host = authority_host(authority)
  if loopback_authority(authority) ||
    host == "0.0.0.0" ||
    host.has_prefix("0."[:]) ||
    host.has_prefix("10."[:]) ||
    host.has_prefix("127."[:]) ||
    host.has_prefix("169.254."[:]) ||
    host.has_prefix("192.0.0."[:]) ||
    host.has_prefix("192.0.2."[:]) ||
    host.has_prefix("192.168."[:]) ||
    host.has_prefix("198.18."[:]) ||
    host.has_prefix("198.19."[:]) ||
    host.has_prefix("198.51.100."[:]) ||
    host.has_prefix("203.0.113."[:]) ||
    host == "[::]" ||
    host.has_prefix("[::ffff:"[:]) ||
    host.has_prefix("[fc"[:]) ||
    host.has_prefix("[fd"[:]) ||
    host.has_prefix("[fe8"[:]) ||
    host.has_prefix("[fe9"[:]) ||
    host.has_prefix("[fea"[:]) ||
    host.has_prefix("[feb"[:]) {
    return true
  }
  if host.has_prefix("172."[:]) {
    for second in 16..<=31 {
      if host.has_prefix("172.\{second}."[:]) {
        return true
      }
    }
  }
  for second in 64..<=127 {
    if host.has_prefix("100.\{second}."[:]) {
      return true
    }
  }
  for first in 224..<=255 {
    if host.has_prefix("\{first}."[:]) {
      return true
    }
  }
  false
}

///|
pub fn validate_public_authorization_uri(
  value : String,
) -> AbsoluteUri raise AuthError {
  let uri = validate_secure_uri(value)
  if private_literal_authority(uri.authority()) {
    raise InvalidUri("authorization destination must not be a private address")
  }
  uri
}

///|
/// Authorization endpoints require HTTPS. A loopback redirect URI may use
/// plain HTTP as permitted for native clients.
pub fn validate_secure_uri(
  value : String,
  allow_loopback_http? : Bool = false,
) -> AbsoluteUri raise AuthError {
  let uri = parse_absolute_uri(value)
  if uri.scheme().equal_ignore_ascii_case("https") {
    return uri
  }
  if allow_loopback_http &&
    uri.scheme().equal_ignore_ascii_case("http") &&
    loopback_authority(uri.authority()) {
    return uri
  }
  raise InvalidUri("authorization URI must use HTTPS")
}

///|
fn unreserved(char : Char) -> Bool {
  char is ('a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '.' | '_' | '~')
}

///|
fn hex_digit(value : Int) -> Char {
  if value < 10 {
    (0x30 + value).unsafe_to_char()
  } else {
    (0x41 + value - 10).unsafe_to_char()
  }
}

///|
/// Percent-encode a UTF-8 value for OAuth query and form parameters.
pub fn percent_encode(value : String) -> String {
  let builder = StringBuilder()
  for byte in @utf8.encode(value) {
    let char = byte.to_int().unsafe_to_char()
    if byte < 0x80 && unreserved(char) {
      builder.write_char(char)
    } else {
      builder.write_char('%')
      builder.write_char(hex_digit(byte.to_int() / 16))
      builder.write_char(hex_digit(byte.to_int() % 16))
    }
  }
  builder.to_string()
}

///|
pub fn encode_parameters(parameters : Array[(String, String)]) -> String {
  parameters
  .map(pair => percent_encode(pair.0) + "=" + percent_encode(pair.1))
  .join("&")
}

///|
pub fn encode_form_parameters(parameters : Array[(String, String)]) -> String {
  parameters
  .map(pair => {
    form_encode_component(pair.0) + "=" + form_encode_component(pair.1)
  })
  .join("&")
}

///|
fn form_encode_component(value : String) -> String {
  percent_encode(value).replace_all(old="%20", new="+")
}

///|
fn hex_value(char : Char) -> Int? {
  match char {
    '0'..='9' => Some(char.to_int() - 0x30)
    'a'..='f' => Some(char.to_int() - 0x61 + 10)
    'A'..='F' => Some(char.to_int() - 0x41 + 10)
    _ => None
  }
}

///|
pub fn percent_decode(value : String) -> String raise AuthError {
  let bytes : Array[Byte] = []
  let mut index = 0
  while index < value.length() {
    if value[index] == '%' {
      guard index + 2 < value.length() &&
        value.get_char(index + 1) is Some(high_char) &&
        value.get_char(index + 2) is Some(low_char) &&
        hex_value(high_char) is Some(high) &&
        hex_value(low_char) is Some(low) else {
        raise InvalidUri("malformed percent escape")
      }
      bytes.push((high * 16 + low).to_byte())
      index += 3
    } else {
      guard value.get_char(index) is Some(char) else {
        raise InvalidUri("invalid query character")
      }
      for byte in @utf8.encode(char.to_string()) {
        bytes.push(byte)
      }
      index += char.to_string().length()
    }
  }
  @utf8.decode(Bytes::from_array(bytes)) catch {
    _ => raise InvalidUri("percent-decoded value is not UTF-8")
  }
}

///|
pub fn parse_query(value : String) -> Map[String, String] raise AuthError {
  let result : Map[String, String] = Map([])
  if value.is_empty() {
    return result
  }
  for field in value.split("&") {
    let (name, field_value) = match field.split_once("=") {
      Some((name, field_value)) => (name.to_owned(), field_value.to_owned())
      None => (field.to_owned(), "")
    }
    let decoded_name = percent_decode(name.replace_all(old="+", new=" "))
    if result.contains(decoded_name) {
      raise InvalidUri("duplicate query parameter: " + decoded_name)
    }
    result[decoded_name] = percent_decode(
      field_value.replace_all(old="+", new=" "),
    )
  }
  result
}

///|
pub fn append_query(
  endpoint : String,
  parameters : Array[(String, String)],
) -> String {
  let separator = if endpoint.contains("?"[:]) { "&" } else { "?" }
  endpoint + separator + encode_parameters(parameters)
}
