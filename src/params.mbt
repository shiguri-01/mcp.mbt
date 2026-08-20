///|
/// Parameters for pagination-supporting list requests (`tools/list`, `resources/list`, etc.).
pub struct ListParams {
  cursor : String?
} derive(Debug, Eq)

///|
pub fn ListParams::ListParams(cursor? : String) -> ListParams {
  { cursor, }
}

///|
pub impl @json.FromJson for ListParams with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ListParams raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let cursor = match fields.get("cursor") {
    Some(String(cursor)) => Some(cursor)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("cursor"), "expected string"))
  }
  ListParams(cursor?)
}

///|
pub impl ToJson for ListParams with fn to_json(self : ListParams) -> Json {
  let fields : Map[String, Json] = Map([])
  if self.cursor is Some(cursor) {
    fields["cursor"] = Json::string(cursor)
  }
  Json::object(fields)
}

///|
pub fn ListParams::from_json(
  value : Json,
  path? : @json.JsonPath,
) -> ListParams raise McpError {
  decode_json(value, path?)
}
