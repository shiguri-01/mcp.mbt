///|
fn empty_object_schema() -> Json {
  Json::object({
    "$schema": Json::string("https://json-schema.org/draft/2020-12/schema"),
    "type": Json::string("object"),
    "properties": Json::object({}),
    "additionalProperties": Json::boolean(false),
  })
}
