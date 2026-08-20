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
    "resultType": ToJson::to_json(ResultType::Complete),
    "supportedVersions": self.supported_versions.to_json(),
    "capabilities": ToJson::to_json(self.capabilities),
  }
  fields.set_opt("instructions", self.instructions.map(Json::string))
  self.cache_policy.put(fields)
  if self.meta is Some(value) {
    fields["_meta"] = ToJson::to_json(value)
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for DiscoverResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> DiscoverResult raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let supported_versions : Array[String] = match
    fields.get("supportedVersions") {
    Some(Array(arr)) => {
      let result : Array[String] = []
      for i, it in arr {
        match it {
          String(s) => result.push(s)
          _ =>
            raise JsonDecodeError(
              (
                path.add_key("supportedVersions").add_index(i),
                "expected string",
              ),
            )
        }
      }
      result
    }
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("supportedVersions"), "expected array"),
      )
    None =>
      raise JsonDecodeError(
        (path.add_key("supportedVersions"), "supportedVersions is required"),
      )
  }
  let capabilities : ServerCapabilities = match fields.get("capabilities") {
    Some(v) => @json.from_json(v, path=path.add_key("capabilities"))
    None =>
      raise JsonDecodeError(
        (path.add_key("capabilities"), "capabilities is required"),
      )
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
    Some(v) => Some(@json.from_json(v, path=path.add_key("_meta")))
    None => None
  }
  DiscoverResult(
    supported_versions~,
    capabilities~,
    instructions?,
    cache_policy~,
    meta?,
  ) catch {
    error => raise JsonDecodeError((path, error.to_string()))
  }
}

///|
/// Decode a `server/discover` result after the JSON-RPC envelope is removed.
pub fn DiscoverResult::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> DiscoverResult raise McpError {
  decode_json(value, path?)
}
