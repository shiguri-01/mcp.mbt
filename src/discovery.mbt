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
pub impl @json.FromJson for DiscoverResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> DiscoverResult raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let supported_versions_val = match fields.get("supportedVersions") {
    Some(Array(arr)) => arr
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("supportedVersions"), "expected array"),
      )
    None =>
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
  let cap_val = match fields.get("capabilities") {
    Some(v) => v
    None =>
      raise JsonDecodeError(
        (path.add_key("capabilities"), "capabilities is required"),
      )
  }
  let capabilities : ServerCapabilities = @json.from_json(cap_val) catch {
    JsonDecodeError((_, msg)) =>
      raise JsonDecodeError((path.add_key("capabilities"), msg))
  }
  let instructions = match fields.get("instructions") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("instructions"), "expected string"))
  }
  let cache_policy : CachePolicy = @json.from_json(value) catch {
    JsonDecodeError((_, msg)) => raise JsonDecodeError((path, msg))
  }
  let meta : ResultMeta? = match fields.get("_meta") {
    Some(v) =>
      Some(
        @json.from_json(v) catch {
          JsonDecodeError((_, msg)) =>
            raise JsonDecodeError((path.add_key("_meta"), msg))
        },
      )
    None => None
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
