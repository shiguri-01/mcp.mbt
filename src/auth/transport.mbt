///|
pub(all) enum HttpMethod {
  Get
  Post
} derive(Debug, Eq)

///|
pub struct HttpRequest {
  priv request_method : HttpMethod
  priv url : String
  priv headers : Map[String, String]
  priv body : String
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
pub fn HttpRequest::request_method(self : HttpRequest) -> HttpMethod {
  self.request_method
}

///|
pub fn HttpRequest::url(self : HttpRequest) -> String {
  self.url
}

///|
pub fn HttpRequest::headers(self : HttpRequest) -> Map[String, String] {
  self.headers.copy()
}

///|
pub fn HttpRequest::body(self : HttpRequest) -> String {
  self.body
}

///|
pub struct HttpResponse {
  priv status : Int
  priv headers : Map[String, String]
  priv body : String
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
pub fn HttpResponse::status(self : HttpResponse) -> Int {
  self.status
}

///|
pub fn HttpResponse::headers(self : HttpResponse) -> Map[String, String] {
  self.headers.copy()
}

///|
pub fn HttpResponse::body(self : HttpResponse) -> String {
  self.body
}

///|
/// Host seam for authorization I/O. The auth package owns OAuth policy while
/// applications choose their HTTP stack, browser/user-agent, and CSPRNG.
pub struct AuthorizationProvider {
  priv send_request : async (HttpRequest) -> HttpResponse raise AuthError
  priv open_authorization_url : async (String) -> String raise AuthError
  priv random_bytes : (Int) -> Bytes raise AuthError
}

///|
pub fn AuthorizationProvider::AuthorizationProvider(
  send_request~ : async (HttpRequest) -> HttpResponse raise AuthError,
  open_authorization_url~ : async (String) -> String raise AuthError,
  random_bytes~ : (Int) -> Bytes raise AuthError,
) -> AuthorizationProvider {
  { send_request, open_authorization_url, random_bytes }
}

///|
pub async fn AuthorizationProvider::send(
  self : AuthorizationProvider,
  request : HttpRequest,
) -> HttpResponse raise AuthError {
  if @async.is_being_cancelled() {
    raise TransportFailure("authorization transport cancelled")
  }
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
  (self.open_authorization_url)(authorization_url)
}

///|
pub fn AuthorizationProvider::new_pkce_session(
  self : AuthorizationProvider,
) -> PkceSession raise AuthError {
  pkce_from_entropy((self.random_bytes)(32), (self.random_bytes)(24))
}
