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
      fields.set_opt("title", title.map(Json::string))
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
pub impl @json.FromJson for CompletionReference with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> CompletionReference raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let typ = match fields.get("type") {
    Some(String(s)) => s
    Some(_) => raise JsonDecodeError((path.add_key("type"), "expected string"))
    None => raise JsonDecodeError((path.add_key("type"), "type is required"))
  }
  match typ {
    "ref/prompt" => {
      let name = match fields.get("name") {
        Some(String(s)) => s
        Some(_) =>
          raise JsonDecodeError((path.add_key("name"), "expected string"))
        None =>
          raise JsonDecodeError((path.add_key("name"), "name is required"))
      }
      let title = match fields.get("title") {
        Some(String(s)) => Some(s)
        Some(Null) | None => None
        Some(_) =>
          raise JsonDecodeError((path.add_key("title"), "expected string"))
      }
      PromptRef(name~, title~)
    }
    "ref/resource" => {
      let uri = match fields.get("uri") {
        Some(String(s)) => s
        Some(_) =>
          raise JsonDecodeError((path.add_key("uri"), "expected string"))
        None => raise JsonDecodeError((path.add_key("uri"), "uri is required"))
      }
      ResourceRef(uri~)
    }
    other =>
      raise JsonDecodeError(
        (path.add_key("type"), "unknown completion reference type: \{other}"),
      )
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
pub impl @json.FromJson for CompletionRequest with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> CompletionRequest raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let reference : CompletionReference = match fields.get("ref") {
    Some(ref_val) => @json.from_json(ref_val, path=path.add_key("ref"))
    None => raise JsonDecodeError((path.add_key("ref"), "ref is required"))
  }
  let argument = match fields.get("argument") {
    Some(Object(arg_fields)) => arg_fields
    Some(_) =>
      raise JsonDecodeError((path.add_key("argument"), "expected object"))
    None =>
      raise JsonDecodeError((path.add_key("argument"), "argument is required"))
  }
  let argument_name = match argument.get("name") {
    Some(String(s)) => s
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("argument").add_key("name"), "expected string"),
      )
    None =>
      raise JsonDecodeError(
        (path.add_key("argument").add_key("name"), "name is required"),
      )
  }
  let argument_value = match argument.get("value") {
    Some(String(s)) => s
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("argument").add_key("value"), "expected string"),
      )
    None =>
      raise JsonDecodeError(
        (path.add_key("argument").add_key("value"), "value is required"),
      )
  }
  let context_arguments : Map[String, String] = match fields.get("context") {
    Some(Object(ctx_fields)) =>
      match ctx_fields.get("arguments") {
        Some(Object(args_fields)) => {
          let result : Map[String, String] = Map([])
          for key, val in args_fields {
            match val {
              String(s) => result[key] = s
              _ =>
                raise JsonDecodeError(
                  (
                    path.add_key("context").add_key("arguments").add_key(key),
                    "expected string",
                  ),
                )
            }
          }
          result
        }
        Some(Null) | None => Map([])
        Some(_) =>
          raise JsonDecodeError(
            (path.add_key("context").add_key("arguments"), "expected object"),
          )
      }
    Some(Null) | None => Map([])
    Some(_) =>
      raise JsonDecodeError((path.add_key("context"), "expected object"))
  }
  let meta = match fields.get("_meta") {
    Some(v) => Some(v.copy())
    None => None
  }
  { reference, argument_name, argument_value, context_arguments, meta }
}

///|
pub fn CompletionRequest::from_json(
  value : Json,
) -> CompletionRequest raise McpError {
  decode_json(value, context="completion/complete params")
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
  { values: values.copy(), total, has_more, meta: meta.map(fn(m) { m.copy() }) }
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
    Some(v) => Some(@json.from_json(v, path=path.add_key("_meta")))
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
