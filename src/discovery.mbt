///|
/// Result of the stateless `server/discover` method.
pub struct DiscoverResult {
  supported_versions : Array[String]
  capabilities : ServerCapabilities
  instructions : String?
  cache_policy : CachePolicy
  meta : ResultMeta?
} derive(Debug)

///|
pub fn DiscoverResult::DiscoverResult(
  supported_versions? : Array[String] = [LATEST_PROTOCOL_VERSION],
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
  fields.set_opt("instructions", self.instructions.map(Json::string))
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
  match fields {
    { "ttlMs": Number(value, ..), .. } if value >= 0.0 &&
      value == value.to_int64().to_double() => value.to_int64()
    { "ttlMs": _, .. } =>
      raise InvalidParams("\{context}.ttlMs must be a non-negative integer")
    _ => raise InvalidParams("\{context}.ttlMs is required")
  }
}

///|
pub impl @json.FromJson for DiscoverResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> DiscoverResult raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let supported_versions_val = match fields {
    { "supportedVersions": Array(arr), .. } => arr
    { "supportedVersions": _, .. } =>
      raise JsonDecodeError(
        (path.add_key("supportedVersions"), "expected array"),
      )
    _ =>
      raise JsonDecodeError(
        (path.add_key("supportedVersions"), "supportedVersions is required"),
      )
  }
  let supported_versions : Array[String] = []
  for i, it in supported_versions_val {
    match it {
      String(s) => supported_versions.push(s)
      _ =>
        raise JsonDecodeError(
          (path.add_key("supportedVersions").add_index(i), "expected string"),
        )
    }
  }
  let capabilities : ServerCapabilities = match fields {
    { "capabilities": v, .. } =>
      @json.from_json(v, path=path.add_key("capabilities"))
    _ =>
      raise JsonDecodeError(
        (path.add_key("capabilities"), "capabilities is required"),
      )
  }
  let instructions = match fields {
    { "instructions": String(s), .. } => Some(s)
    { "instructions": Null, .. } => None
    { "instructions": _, .. } =>
      raise JsonDecodeError((path.add_key("instructions"), "expected string"))
    _ => None
  }
  let cache_policy : CachePolicy = @json.from_json(value) catch {
    JsonDecodeError((_, msg)) => raise JsonDecodeError((path, msg))
  }
  let meta : ResultMeta? = match fields {
    { "_meta": v, .. } => Some(@json.from_json(v, path=path.add_key("_meta")))
    _ => None
  }
  DiscoverResult(
    supported_versions~,
    capabilities~,
    instructions?,
    cache_policy~,
    meta?,
  ) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
/// Decode a `server/discover` result after the JSON-RPC envelope is removed.
pub fn DiscoverResult::from_json(value : Json) -> DiscoverResult raise McpError {
  decode_json(value, context="discover result")
}
