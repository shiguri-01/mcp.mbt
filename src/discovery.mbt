///|
/// Result of the stateless `server/discover` method.
pub(all) struct DiscoverResult {
  supported_versions : Array[String]
  capabilities : ServerCapabilities
  instructions : String?
  cache_policy : CachePolicy
  meta : ResultMeta?
} derive(Debug)

///|
pub fn DiscoverResult::DiscoverResult(
  supported_versions? : Array[String] = [latest_protocol_version],
  capabilities~ : ServerCapabilities,
  instructions? : String,
  cache_policy~ : CachePolicy,
  meta? : ResultMeta,
) -> DiscoverResult raise McpError {
  if supported_versions.is_empty() {
    raise InvalidParams("supportedVersions must not be empty")
  }
  {
    supported_versions: supported_versions.copy(),
    capabilities: capabilities.copy(),
    instructions,
    cache_policy,
    meta,
  }
}

///|
pub impl ToJson for DiscoverResult with fn to_json(self : DiscoverResult) -> Json {
  let fields : Map[String, Json] = {
    "resultType": ResultType::Complete.to_json(),
    "supportedVersions": self.supported_versions.to_json(),
    "capabilities": self.capabilities.to_json(),
  }
  put_optional_string(fields, "instructions", self.instructions)
  self.cache_policy.put(fields)
  if self.meta is Some(value) {
    fields["_meta"] = value.to_json()
  }
  Json::object(fields)
}

///|
fn parse_ttl_ms(
  fields : Map[String, Json],
  context : String,
) -> Int64 raise McpError {
  match fields.get("ttlMs") {
    Some(Number(value, ..)) if value >= 0.0 &&
      value == value.to_int64().to_double() => value.to_int64()
    Some(_) =>
      raise InvalidParams("\{context}.ttlMs must be a non-negative integer")
    None => raise InvalidParams("\{context}.ttlMs is required")
  }
}

///|
pub fn parse_discover_result(value : Json) -> DiscoverResult raise McpError {
  let context = "discover result"
  let fields = expect_object(value, context)
  match fields.get("resultType") {
    Some(result_type) if parse_result_type(result_type) == Complete => ()
    None => ()
    _ => raise InvalidRequest("discover result.resultType must be 'complete'")
  }
  let supported_versions = match fields.get("supportedVersions") {
    Some(Array(values)) =>
      values.map(item => {
        match item {
          String(version) => version
          _ =>
            raise InvalidParams(
              "\{context}.supportedVersions must contain strings",
            )
        }
      })
    Some(_) =>
      raise InvalidParams("\{context}.supportedVersions must be an array")
    None => raise InvalidParams("\{context}.supportedVersions is required")
  }
  guard fields.get("capabilities") is Some(capabilities) else {
    raise InvalidParams("\{context}.capabilities is required")
  }
  let scope = match fields.get("cacheScope") {
    Some(value) => parse_cache_scope(value)
    None => raise InvalidParams("\{context}.cacheScope is required")
  }
  DiscoverResult(
    supported_versions~,
    capabilities=parse_server_capabilities(capabilities),
    instructions?=get_optional_string(fields, "instructions", context),
    cache_policy=CachePolicy(ttl_ms=parse_ttl_ms(fields, context), scope~),
    meta?=match fields.get("_meta") {
      Some(value) => Some(parse_result_meta(value, "\{context}._meta"))
      None => None
    },
  )
}

///|
pub impl @json.FromJson for DiscoverResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> DiscoverResult raise {
  parse_discover_result(value) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}
