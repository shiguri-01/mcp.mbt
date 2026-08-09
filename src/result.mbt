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
pub fn parse_result_type(value : Json) -> ResultType raise McpError {
  match value {
    String("complete") => Complete
    String("input_required") => InputRequired
    String(value) => Extension(value)
    _ => raise InvalidRequest("result.resultType must be a string")
  }
}

///|
pub(all) struct ResultMeta {
  server_info : Implementation?
  extra : Map[String, Json]
} derive(Debug, Eq)

///|
pub fn ResultMeta::ResultMeta(
  server_info? : Implementation,
  extra? : Map[String, Json] = {},
) -> ResultMeta {
  { server_info, extra }
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
fn parse_result_meta(
  value : Json,
  context : String,
) -> ResultMeta raise McpError {
  let fields = expect_object(value, context)
  let extra = fields.copy()
  extra.remove("io.modelcontextprotocol/serverInfo")
  let server_info : Implementation? = match
    fields.get("io.modelcontextprotocol/serverInfo") {
    Some(value) =>
      Some(
        @json.from_json(value) catch {
          JsonDecodeError((_, message)) =>
            raise InvalidParams("\{context}.serverInfo: \{message}")
        },
      )
    None => None
  }
  ResultMeta(server_info?, extra~)
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
pub fn parse_cache_scope(value : Json) -> CacheScope raise McpError {
  match value {
    String("public") => Public
    String("private") => Private
    _ => raise InvalidParams("cacheScope must be 'public' or 'private'")
  }
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
pub fn CachePolicy::ttl_ms(self : CachePolicy) -> Int64 {
  self.ttl_ms
}

///|
pub fn CachePolicy::scope(self : CachePolicy) -> CacheScope {
  self.scope
}

///|
pub impl ToJson for CachePolicy with fn to_json(self : CachePolicy) -> Json {
  Json::object({
    "ttlMs": Json::number(self.ttl_ms.to_double(), repr="\{self.ttl_ms}"),
    "cacheScope": self.scope.to_json(),
  })
}

///|
fn CachePolicy::put(self : CachePolicy, fields : Map[String, Json]) -> Unit {
  fields["ttlMs"] = Json::number(self.ttl_ms.to_double(), repr="\{self.ttl_ms}")
  fields["cacheScope"] = self.scope.to_json()
}
