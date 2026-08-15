///|
/// Decode a JSON value into a domain type using `@json.FromJson`, mapping
/// any `JsonDecodeError` into an `InvalidParams` protocol error.
pub fn[T : @json.FromJson] decode_json(
  value : Json,
  path? : @json.JsonPath,
) -> T raise McpError {
  @json.from_json(value, path?) catch {
    JsonDecodeError((p, msg)) => {
      let path_str = p.to_string()
      if path_str.is_empty() {
        raise InvalidParams(msg)
      } else {
        raise InvalidParams("\{path_str}: \{msg}")
      }
    }
  }
}

///|
fn[K : Eq + Hash, V] Map::set_opt(
  self : Map[K, V],
  key : K,
  value : V?,
) -> Unit {
  if value is Some(v) {
    self[key] = v
  }
}

///|
/// Copy a JSON value recursively before retaining caller-owned protocol data.
fn Json::copy(self : Json) -> Json {
  match self {
    Object(fields) => {
      let copied : Map[String, Json] = Map([])
      for key, value in fields {
        copied[key] = value.copy()
      }
      Json::object(copied)
    }
    Array(values) => Json::array(values.map(fn(v) { v.copy() }))
    _ => self
  }
}

///|
fn Map::copy_json(self : Map[String, Json]) -> Map[String, Json] {
  let copied : Map[String, Json] = Map([])
  for key, value in self {
    copied[key] = value.copy()
  }
  copied
}
