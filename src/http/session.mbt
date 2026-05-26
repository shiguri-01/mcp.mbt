///|
pub(all) struct RequestContext {
  http_method : @async_http.RequestMethod
  path : String
  headers : Map[String, String]
  session_id : String?
}

///|
pub(all) struct ServerOptions {
  endpoint_path : String
  allowed_origins : Set[String]
  require_session : Bool
  session_id_generator : () -> String
  authenticate : (RequestContext) -> Bool
}

///|
fn default_session_id_generator() -> String {
  "mcp-\{@async.now()}"
}

///|
pub fn ServerOptions::ServerOptions(
  endpoint_path? : String = "/mcp",
  allowed_origins? : Set[String] = Set([]),
  require_session? : Bool = true,
  session_id_generator? : () -> String = default_session_id_generator,
  authenticate? : (RequestContext) -> Bool = fn(_) { true },
) -> ServerOptions {
  {
    endpoint_path,
    allowed_origins,
    require_session,
    session_id_generator,
    authenticate,
  }
}

///|
priv struct Session {
  server : @mcp.Server
}

///|
priv struct SessionStore {
  sessions : Map[String, Session]
}

///|
fn SessionStore::SessionStore() -> SessionStore {
  { sessions: {} }
}

///|
fn SessionStore::insert(
  self : SessionStore,
  id : String,
  server : @mcp.Server,
) -> Unit {
  self.sessions[id] = { server, }
}

///|
fn SessionStore::get(self : SessionStore, id : String) -> Session? {
  self.sessions.get(id)
}

///|
fn SessionStore::remove(self : SessionStore, id : String) -> Bool {
  let existed = self.sessions.contains(id)
  self.sessions.remove(id)
  existed
}
