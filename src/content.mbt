///|
pub(all) enum ContentBlock {
  Text(String)
  Image(data~ : String, mime_type~ : String)
  Audio(data~ : String, mime_type~ : String)
  Resource(Json)
} derive(Debug, Eq)

///|
pub impl ToJson for ContentBlock with fn to_json(self : ContentBlock) -> Json {
  match self {
    Text(text) =>
      Json::object({ "type": Json::string("text"), "text": Json::string(text) })
    Image(data~, mime_type~) =>
      Json::object({
        "type": Json::string("image"),
        "data": Json::string(data),
        "mimeType": Json::string(mime_type),
      })
    Audio(data~, mime_type~) =>
      Json::object({
        "type": Json::string("audio"),
        "data": Json::string(data),
        "mimeType": Json::string(mime_type),
      })
    Resource(resource) => resource
  }
}

///|
pub(all) struct CallToolResult {
  content : Array[ContentBlock]
  structured_content : Json?
  is_error : Bool
  meta : Json?
} derive(Debug, Eq)

///|
pub impl ToJson for CallToolResult with fn to_json(self : CallToolResult) -> Json {
  let fields : Map[String, Json] = {
    "content": self.content.map(fn(block) { block.to_json() }).to_json(),
  }
  put_optional_json(fields, "structuredContent", self.structured_content)
  if self.is_error {
    fields["isError"] = Json::boolean(true)
  }
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
/// Return a plain text tool result.
pub fn CallToolResult::text(text : String) -> CallToolResult {
  {
    content: [Text(text)],
    structured_content: None,
    is_error: false,
    meta: None,
  }
}

///|
/// Return structured content without a text block.
pub fn CallToolResult::json(value : Json) -> CallToolResult {
  { content: [], structured_content: Some(value), is_error: false, meta: None }
}

///|
/// Return typed structured content through `ToJson`.
pub fn[T : ToJson] CallToolResult::structured(value : T) -> CallToolResult {
  CallToolResult::json(value.to_json())
}

///|
pub fn CallToolResult::text_json(text : String, value : Json) -> CallToolResult {
  {
    content: [Text(text)],
    structured_content: Some(value),
    is_error: false,
    meta: None,
  }
}

///|
/// Return a tool error as MCP content, not as a JSON-RPC protocol error.
pub fn CallToolResult::error_text(text : String) -> CallToolResult {
  {
    content: [Text(text)],
    structured_content: None,
    is_error: true,
    meta: None,
  }
}
