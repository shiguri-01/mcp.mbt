///|
pub(all) enum ResultType {
  Complete
  InputRequired
  Extension(String)
} derive(Debug, Eq)

///|
pub fn ResultType::to_string(self : ResultType) -> String {
  match self {
    Complete => "complete"
    InputRequired => "input_required"
    Extension(value) => value
  }
}

///|
pub impl ToJson for ResultType with fn to_json(self : ResultType) -> Json {
  Json::string(self.to_string())
}

///|
pub impl @json.FromJson for ResultType with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ResultType raise {
  match value {
    String("complete") => Complete
    String("input_required") => InputRequired
    String(value) => Extension(value)
    _ => raise JsonDecodeError((path, "expected string"))
  }
}

///|
pub fn ResultType::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ResultType raise McpError {
  decode_json(value, path?)
}

///|
pub struct ResultMeta {
  server_info : Implementation?
  extra : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn ResultMeta::ResultMeta(
  server_info? : Implementation,
  extra? : Map[String, Json] = {},
) -> ResultMeta raise McpError {
  validate_meta_map(extra)
  {
    server_info: server_info.map(value => value.copy()),
    extra: extra.copy_json(),
  }
}

///|
/// Copy result metadata before retaining it in another protocol value.
fn ResultMeta::copy(self : ResultMeta) -> ResultMeta {
  {
    server_info: self.server_info.map(value => value.copy()),
    extra: self.extra.copy_json(),
  }
}

///|
pub impl ToJson for ResultMeta with fn to_json(self : ResultMeta) -> Json {
  let fields = self.extra.copy()
  if self.server_info is Some(value) {
    fields["io.modelcontextprotocol/serverInfo"] = ToJson::to_json(value)
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for ResultMeta with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ResultMeta raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let extra = fields.copy()
  extra.remove("io.modelcontextprotocol/serverInfo")
  let server_info : Implementation? = match fields {
    { "io.modelcontextprotocol/serverInfo": v, .. } =>
      Some(
        @json.from_json(
          v,
          path=path.add_key("io.modelcontextprotocol/serverInfo"),
        ),
      )
    _ => None
  }
  ResultMeta(server_info?, extra~) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub fn ResultMeta::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ResultMeta raise McpError {
  decode_json(value, path?)
}

///|

///|
fn merge_result_meta(
  fields : Map[String, Json],
  server_info? : Implementation,
  extra? : Map[String, Json] = {},
) -> Unit raise McpError {
  let merged = match fields {
    { "_meta": Object(value), .. } => value.copy()
    { "_meta": _, .. } => raise InvalidParams("result._meta must be an object")
    _ => Map([])
  }
  validate_meta_map(merged)
  validate_meta_map(extra)
  for key, value in extra {
    merged[key] = value
  }
  if server_info is Some(value) {
    merged["io.modelcontextprotocol/serverInfo"] = ToJson::to_json(value)
  }
  if !merged.is_empty() {
    fields["_meta"] = Json::object(merged)
  }
}

///|
/// Stamp a method-specific result object with mandatory modern result metadata.
pub fn stamp_result_meta(
  value : Json,
  server_info? : Implementation,
  meta? : Map[String, Json] = {},
) -> Json raise McpError {
  guard value is Object(fields) else {
    raise InvalidParams("result must be an object")
  }
  let fields = fields.copy_json()
  merge_result_meta(fields, server_info?, extra=meta)
  Json::object(fields)
}

///|
/// Stamp a method-specific result object with complete resultType and modern metadata.
pub fn complete_result(
  value : Json,
  server_info? : Implementation,
  meta? : Map[String, Json] = {},
) -> Json raise McpError {
  guard value is Object(fields) else {
    raise InvalidParams("complete result must be an object")
  }
  let fields = fields.copy_json()
  fields["resultType"] = ToJson::to_json(ResultType::Complete)
  merge_result_meta(fields, server_info?, extra=meta)
  Json::object(fields)
}

///|
/// Cache policy scope: shared across all callers or private to this session/connection.
pub(all) enum CacheScope {
  Public
  Private
} derive(Debug, Eq)

///|
pub impl ToJson for CacheScope with fn to_json(self : CacheScope) -> Json {
  match self {
    Public => Json::string("public")
    Private => Json::string("private")
  }
}

///|
pub impl @json.FromJson for CacheScope with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> CacheScope raise {
  match value {
    String("public") => Public
    String("private") => Private
    _ =>
      raise JsonDecodeError(
        (path, "expected cacheScope to be \"public\" or \"private\""),
      )
  }
}

///|
pub fn CacheScope::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> CacheScope raise McpError {
  decode_json(value, path?)
}

///|
/// Validated caching advice for discover, list, and resource read results.
pub struct CachePolicy {
  ttl_ms : Int64
  scope : CacheScope
} derive(Debug, Eq)

///|
pub fn CachePolicy::CachePolicy(
  ttl_ms~ : Int64,
  scope? : CacheScope = Private,
) -> CachePolicy raise McpError {
  if ttl_ms < 0L {
    raise InvalidParams("cache ttlMs must be non-negative")
  }
  { ttl_ms, scope }
}

///|
pub impl ToJson for CachePolicy with fn to_json(self : CachePolicy) -> Json {
  Json::object({
    "ttlMs": Json::number(self.ttl_ms.to_double(), repr="\{self.ttl_ms}"),
    "cacheScope": ToJson::to_json(self.scope),
  })
}

///|
pub impl @json.FromJson for CachePolicy with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> CachePolicy raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  guard fields is { "cacheScope": scope_val, .. } else {
    raise JsonDecodeError(
      (path.add_key("cacheScope"), "cacheScope is required"),
    )
  }
  let scope : CacheScope = @json.from_json(scope_val) catch {
    JsonDecodeError((_, msg)) =>
      raise JsonDecodeError((path.add_key("cacheScope"), msg))
  }
  let ttl_ms = match fields {
    { "ttlMs": Number(value, ..), .. } if value >= 0.0 &&
      value == value.to_int64().to_double() => value.to_int64()
    { "ttlMs": _, .. } =>
      raise JsonDecodeError(
        (path.add_key("ttlMs"), "expected non-negative integer"),
      )
    _ => raise JsonDecodeError((path.add_key("ttlMs"), "ttlMs is required"))
  }
  CachePolicy(ttl_ms~, scope~) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub fn CachePolicy::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> CachePolicy raise McpError {
  decode_json(value, path?)
}

///|
fn CachePolicy::put(self : CachePolicy, fields : Map[String, Json]) -> Unit {
  fields["ttlMs"] = Json::number(self.ttl_ms.to_double(), repr="\{self.ttl_ms}")
  fields["cacheScope"] = ToJson::to_json(self.scope)
}
