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
pub fn ResultType::from_json(value : Json) -> ResultType raise McpError {
  decode_json(value, context="result.resultType")
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
    extra: copy_json_map(extra),
  }
}

///|
/// Copy result metadata before retaining it in another protocol value.
fn ResultMeta::copy(self : ResultMeta) -> ResultMeta {
  {
    server_info: self.server_info.map(value => value.copy()),
    extra: copy_json_map(self.extra),
  }
}

///|
fn copy_optional_result_meta(value : ResultMeta?) -> ResultMeta? {
  value.map(meta => meta.copy())
}

///|
pub impl ToJson for ResultMeta with fn to_json(self : ResultMeta) -> Json {
  let fields = self.extra.copy()
  if self.server_info is Some(value) {
    fields["io.modelcontextprotocol/serverInfo"] = value.to_json()
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
  let server_info : Implementation? = match
    fields.get("io.modelcontextprotocol/serverInfo") {
    Some(v) =>
      Some(
        @json.from_json(v) catch {
          JsonDecodeError((_, msg)) =>
            raise JsonDecodeError(
              (path.add_key("io.modelcontextprotocol/serverInfo"), msg),
            )
        },
      )
    None => None
  }
  ResultMeta(server_info?, extra~) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub fn ResultMeta::from_json(
  value : Json,
  context? : String = "result._meta",
) -> ResultMeta raise McpError {
  decode_json(value, context~)
}

///|
fn merge_result_meta(
  fields : Map[String, Json],
  server_info? : Implementation,
  extra? : Map[String, Json] = {},
) -> Unit raise McpError {
  let merged = match fields.get("_meta") {
    Some(value) => expect_object(value, "result._meta").copy()
    None => Map([])
  }
  validate_meta_map(merged)
  validate_meta_map(extra)
  for key, value in extra {
    merged[key] = value
  }
  if server_info is Some(value) {
    merged["io.modelcontextprotocol/serverInfo"] = value.to_json()
  }
  if !merged.is_empty() {
    fields["_meta"] = Json::object(merged)
  }
}

///|
/// Stamp a method-specific result object with mandatory modern result metadata.
pub fn complete_result(
  value : Json,
  server_info? : Implementation,
  meta? : Map[String, Json] = {},
) -> Json raise McpError {
  let fields = expect_object(value, "complete result").copy()
  fields["resultType"] = ResultType::Complete.to_json()
  merge_result_meta(fields, server_info?, extra=meta)
  Json::object(fields)
}

///|
pub(all) enum CacheScope {
  Public
  Private
} derive(Debug, Eq)

///|
pub fn CacheScope::to_string(self : CacheScope) -> String {
  match self {
    Public => "public"
    Private => "private"
  }
}

///|
pub impl ToJson for CacheScope with fn to_json(self : CacheScope) -> Json {
  Json::string(self.to_string())
}

///|
pub impl @json.FromJson for CacheScope with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> CacheScope raise {
  match value {
    String("public") => Public
    String("private") => Private
    _ => raise JsonDecodeError((path, "expected 'public' or 'private'"))
  }
}

///|
pub fn CacheScope::from_json(value : Json) -> CacheScope raise McpError {
  decode_json(value, context="cacheScope")
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
    "cacheScope": self.scope.to_json(),
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
  let scope_val = match fields.get("cacheScope") {
    Some(v) => v
    None =>
      raise JsonDecodeError(
        (path.add_key("cacheScope"), "cacheScope is required"),
      )
  }
  let scope : CacheScope = @json.from_json(scope_val) catch {
    JsonDecodeError((_, msg)) =>
      raise JsonDecodeError((path.add_key("cacheScope"), msg))
  }
  let ttl_ms = match fields.get("ttlMs") {
    Some(Number(value, ..)) if value >= 0.0 &&
      value == value.to_int64().to_double() => value.to_int64()
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("ttlMs"), "expected non-negative integer"),
      )
    None => raise JsonDecodeError((path.add_key("ttlMs"), "ttlMs is required"))
  }
  CachePolicy(ttl_ms~, scope~) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub fn CachePolicy::from_json(
  fields : Map[String, Json],
  context? : String = "result",
) -> CachePolicy raise McpError {
  let scope = match fields.get("cacheScope") {
    Some(value) => CacheScope::from_json(value)
    None => raise InvalidParams("\{context}.cacheScope is required")
  }
  CachePolicy(ttl_ms=parse_ttl_ms(fields, context), scope~)
}

///|
fn CachePolicy::put(self : CachePolicy, fields : Map[String, Json]) -> Unit {
  fields["ttlMs"] = Json::number(self.ttl_ms.to_double(), repr="\{self.ttl_ms}")
  fields["cacheScope"] = self.scope.to_json()
}
