///|
pub(all) enum CompletionReference {
  PromptRef(name~ : String, title~ : String?)
  ResourceRef(uri~ : String)
} derive(Debug, Eq)

///|
pub fn CompletionReference::prompt(
  name~ : String,
  title? : String,
) -> CompletionReference {
  PromptRef(name~, title~)
}

///|
pub fn CompletionReference::resource(uri~ : String) -> CompletionReference {
  ResourceRef(uri~)
}

///|
pub impl ToJson for CompletionReference with fn to_json(
  self : CompletionReference,
) -> Json {
  match self {
    PromptRef(name~, title~) => {
      let fields : Map[String, Json] = {
        "type": Json::string("ref/prompt"),
        "name": Json::string(name),
      }
      put_optional_string(fields, "title", title)
      Json::object(fields)
    }
    ResourceRef(uri~) =>
      Json::object({
        "type": Json::string("ref/resource"),
        "uri": Json::string(uri),
      })
  }
}

///|
fn parse_completion_reference(
  value : Json,
) -> CompletionReference raise McpError {
  let fields = expect_object(value, "completion/complete params.ref")
  match get_string(fields, "type", "completion/complete params.ref") {
    "ref/prompt" =>
      PromptRef(
        name=get_string(fields, "name", "completion/complete params.ref"),
        title=get_optional_string(
          fields, "title", "completion/complete params.ref",
        ),
      )
    "ref/resource" =>
      ResourceRef(
        uri=get_string(fields, "uri", "completion/complete params.ref"),
      )
    other => raise InvalidParams("unknown completion reference type: \{other}")
  }
}

///|
pub(all) struct CompletionRequest {
  reference : CompletionReference
  argument_name : String
  argument_value : String
  context_arguments : Map[String, String]
  meta : Json?
} derive(Debug, Eq)

///|
fn parse_string_map(
  value : Json,
  context : String,
) -> Map[String, String] raise McpError {
  let fields = expect_object(value, context)
  let result : Map[String, String] = Map([])
  for key, value in fields {
    match value {
      String(value) => result[key] = value
      _ => raise InvalidParams("\{context} values must be strings")
    }
  }
  result
}

///|
fn parse_completion_request(params : Json?) -> CompletionRequest raise McpError {
  let value = match params {
    Some(value) => value
    None => raise InvalidParams("completion/complete params are required")
  }
  let fields = expect_object(value, "completion/complete params")
  let argument = expect_object(
    match fields.get("argument") {
      Some(value) => value
      None =>
        raise InvalidParams("completion/complete params.argument is required")
    },
    "completion/complete params.argument",
  )
  let context_arguments = match
    get_optional_fields(fields, "context", "completion/complete params") {
    Some(context) =>
      match context.get("arguments") {
        Some(value) =>
          parse_string_map(
            value, "completion/complete params.context.arguments",
          )
        None => {}
      }
    None => {}
  }
  {
    reference: parse_completion_reference(
      match fields.get("ref") {
        Some(value) => value
        None =>
          raise InvalidParams("completion/complete params.ref is required")
      },
    ),
    argument_name: get_string(
      argument, "name", "completion/complete params.argument",
    ),
    argument_value: get_string(
      argument, "value", "completion/complete params.argument",
    ),
    context_arguments,
    meta: fields.get("_meta"),
  }
}

///|
pub(all) struct CompleteResult {
  values : Array[String]
  total : Int?
  has_more : Bool
} derive(Debug, Eq)

///|
pub fn CompleteResult::CompleteResult(
  values~ : Array[String],
  total? : Int,
  has_more? : Bool = false,
) -> CompleteResult raise McpError {
  if values.length() > 100 {
    raise InvalidParams("completion values must not exceed 100 items")
  }
  { values, total, has_more }
}

///|
pub impl ToJson for CompleteResult with fn to_json(self : CompleteResult) -> Json {
  let completion : Map[String, Json] = { "values": self.values.to_json() }
  match self.total {
    Some(total) =>
      completion["total"] = Json::number(total.to_double(), repr="\{total}")
    None => ()
  }
  if self.has_more {
    completion["hasMore"] = Json::boolean(true)
  }
  Json::object({ "completion": Json::object(completion) })
}
