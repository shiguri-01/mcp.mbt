///|
pub(all) enum HttpMethod {
  Get
  Post
} derive(Debug, Eq)

///|
pub struct HttpRequest {
  request_method : HttpMethod
  url : String
  headers : Map[String, String]
  body : String
}

///|
pub fn HttpRequest::HttpRequest(
  request_method~ : HttpMethod,
  url~ : String,
  headers? : Map[String, String] = Map([]),
  body? : String = "",
) -> HttpRequest raise AuthError {
  ignore(parse_absolute_uri(url))
  { request_method, url, headers: headers.copy(), body }
}

///|
pub struct HttpResponse {
  status : Int
  headers : Map[String, String]
  body : String
}

///|
pub fn HttpResponse::HttpResponse(
  status~ : Int,
  headers? : Map[String, String] = Map([]),
  body? : String = "",
) -> HttpResponse {
  { status, headers: headers.copy(), body }
}

///|
pub fn HttpResponse::header(self : HttpResponse, name : String) -> String? {
  for header_name, value in self.headers {
    if header_name.equal_ignore_ascii_case(name) {
      return Some(value)
    }
  }
  None
}

///|
/// Host seam for authorization I/O. The auth package owns OAuth policy while
/// applications choose their HTTP stack, browser/user-agent, and CSPRNG.
pub struct AuthorizationProvider {
  priv send_request : async (HttpRequest) -> HttpResponse raise AuthError
  priv open_authorization_url : async (String) -> String raise AuthError
  priv random_bytes : (Int) -> Bytes raise AuthError
  priv validate_destination : (String) -> Unit raise AuthError
  priv allow_insecure_loopback : Bool
}

///|
fn validate_destination_default(
  url : String,
  allow_insecure_loopback : Bool,
) -> Unit raise AuthError {
  let uri = validate_secure_uri(
    url,
    allow_loopback_http=allow_insecure_loopback,
  )
  if private_literal_authority(uri.authority) &&
    !(allow_insecure_loopback && loopback_authority(uri.authority)) {
    raise InvalidUri("authorization destination must not be a private address")
  }
}

///|
pub fn AuthorizationProvider::AuthorizationProvider(
  send_request~ : async (HttpRequest) -> HttpResponse raise AuthError,
  open_authorization_url~ : async (String) -> String raise AuthError,
  random_bytes~ : (Int) -> Bytes raise AuthError,
  validate_destination? : (String) -> Unit raise AuthError,
  allow_insecure_loopback? : Bool = false,
) -> AuthorizationProvider {
  let validate_destination = validate_destination.unwrap_or(url => {
    validate_destination_default(url, allow_insecure_loopback)
  })
  {
    send_request,
    open_authorization_url,
    random_bytes,
    validate_destination,
    allow_insecure_loopback,
  }
}

///|
pub fn AuthorizationProvider::allows_insecure_loopback(
  self : AuthorizationProvider,
) -> Bool {
  self.allow_insecure_loopback
}

///|
pub fn AuthorizationProvider::check_destination(
  self : AuthorizationProvider,
  url : String,
) -> Unit raise AuthError {
  (self.validate_destination)(url)
}

///|
pub async fn AuthorizationProvider::send(
  self : AuthorizationProvider,
  request : HttpRequest,
) -> HttpResponse raise AuthError {
  if @async.is_being_cancelled() {
    raise TransportFailure("authorization transport cancelled")
  }
  (self.validate_destination)(request.url)
  (self.send_request)(request)
}

///|
pub async fn AuthorizationProvider::authorize(
  self : AuthorizationProvider,
  authorization_url : String,
) -> String raise AuthError {
  if @async.is_being_cancelled() {
    raise TransportFailure("authorization interaction cancelled")
  }
  (self.validate_destination)(authorization_url)
  (self.open_authorization_url)(authorization_url)
}

///|
pub fn AuthorizationProvider::new_pkce_session(
  self : AuthorizationProvider,
) -> PkceSession raise AuthError {
  pkce_from_entropy((self.random_bytes)(32), (self.random_bytes)(24))
}
