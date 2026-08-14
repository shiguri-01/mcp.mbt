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
pub struct CompletionRequest {
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
pub fn CompletionRequest::from_json(
  value : Json,
) -> CompletionRequest raise McpError {
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
pub struct CompleteResult {
  values : Array[String]
  total : Int?
  has_more : Bool
  meta : ResultMeta?
} derive(Debug, Eq)

///|
pub fn CompleteResult::CompleteResult(
  values~ : Array[String],
  total? : Int,
  has_more? : Bool = false,
  meta? : ResultMeta,
) -> CompleteResult raise McpError {
  if values.length() > 100 {
    raise InvalidParams("completion values must not exceed 100 items")
  }
  if total is Some(value) && value < 0 {
    raise InvalidParams("completion total must be non-negative")
  }
  {
    values: values.copy(),
    total,
    has_more,
    meta: copy_optional_result_meta(meta),
  }
}

///|
pub impl ToJson for CompleteResult with fn to_json(self : CompleteResult) -> Json {
  let completion : Map[String, Json] = {
    "values": self.values.map(fn(value) { Json::string(value) }).to_json(),
    "hasMore": Json::boolean(self.has_more),
  }
  if self.total is Some(total) {
    completion["total"] = Json::number(total.to_double())
  }
  let fields : Map[String, Json] = { "completion": Json::object(completion) }
  if self.meta is Some(meta) {
    fields["_meta"] = meta.to_json()
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for CompleteResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> CompleteResult raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let completion_val = match fields.get("completion") {
    Some(Object(c)) => c
    Some(_) =>
      raise JsonDecodeError((path.add_key("completion"), "expected object"))
    None =>
      raise JsonDecodeError(
        (path.add_key("completion"), "completion is required"),
      )
  }
  let values_val = match completion_val.get("values") {
    Some(Array(arr)) => arr
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("completion").add_key("values"), "expected array"),
      )
    None =>
      raise JsonDecodeError(
        (path.add_key("completion").add_key("values"), "values is required"),
      )
  }
  let values : Array[String] = []
  for i, it in values_val {
    match it {
      String(s) => values.push(s)
      _ =>
        raise JsonDecodeError(
          (
            path.add_key("completion").add_key("values").add_index(i),
            "expected string",
          ),
        )
    }
  }
  let total = match completion_val.get("total") {
    Some(Number(n, ..)) => {
      if n < 0.0 || n != n.floor() {
        raise JsonDecodeError(
          (
            path.add_key("completion").add_key("total"),
            "expected non-negative integer",
          ),
        )
      }
      Some(n.to_int())
    }
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("completion").add_key("total"), "expected number"),
      )
  }
  let has_more = match completion_val.get("hasMore") {
    Some(True) => true
    Some(False) | Some(Null) | None => false
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("completion").add_key("hasMore"), "expected boolean"),
      )
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
  CompleteResult(values~, total?, has_more~, meta?) catch {
    error => raise JsonDecodeError((path, error.message()))
  }
}

///|
pub fn CompleteResult::from_json(value : Json) -> CompleteResult raise McpError {
  decode_json(value, context="completion/complete result")
}
