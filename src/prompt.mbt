///|
pub struct PromptArgument {
  name : String
  title : String?
  description : String?
  required : Bool
} derive(Debug, Eq)

///|
/// A typed prompt declares the arguments it accepts through this trait.
pub(open) trait PromptArguments {
  fn prompt_arguments() -> Array[PromptArgument]
}

///|
/// Construct a prompt argument descriptor.
pub fn PromptArgument::PromptArgument(
  name~ : String,
  title? : String,
  description? : String,
  required? : Bool = false,
) -> PromptArgument {
  { name, title, description, required }
}

///|
fn validate_prompt_argument_names(
  arguments : Array[PromptArgument],
  context : String,
) -> Unit raise McpError {
  let names : Map[String, Unit] = Map([])
  for argument in arguments {
    if names.contains(argument.name) {
      raise InvalidParams(
        "\{context} contains duplicate argument name: \{argument.name}",
      )
    }
    names[argument.name] = ()
  }
}

///|
pub impl ToJson for PromptArgument with fn to_json(self : PromptArgument) -> Json {
  let fields : Map[String, Json] = { "name": Json::string(self.name) }
  put_optional_string(fields, "title", self.title)
  put_optional_string(fields, "description", self.description)
  if self.required {
    fields["required"] = Json::boolean(true)
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for PromptArgument with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> PromptArgument raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let name = match fields.get("name") {
    Some(String(s)) => s
    Some(_) => raise JsonDecodeError((path.add_key("name"), "expected string"))
    None => raise JsonDecodeError((path.add_key("name"), "name is required"))
  }
  let title = match fields.get("title") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) => raise JsonDecodeError((path.add_key("title"), "expected string"))
  }
  let description = match fields.get("description") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("description"), "expected string"))
  }
  let required = match fields.get("required") {
    Some(True) => true
    Some(False) => false
    Some(Null) | None => false
    Some(_) =>
      raise JsonDecodeError((path.add_key("required"), "expected boolean"))
  }
  { name, title, description, required }
}

///|
pub fn PromptArgument::from_json(
  value : Json,
  context? : String = "prompt argument",
) -> PromptArgument raise McpError {
  decode_json(value, context~)
}

///|
pub struct Prompt {
  name : String
  title : String?
  description : String?
  arguments : Array[PromptArgument]
  icons : Array[Icon]
  meta : Json?
} derive(Debug, Eq)

///|
pub fn Prompt::Prompt(
  name~ : String,
  title? : String,
  description? : String,
  arguments? : Array[PromptArgument] = [],
  icons? : Array[Icon] = [],
  meta? : Json,
) -> Prompt {
  {
    name,
    title,
    description,
    arguments: arguments.copy(),
    icons: icons.map(icon => icon.copy()),
    meta: copy_optional_json(meta),
  }
}

///|
pub impl ToJson for Prompt with fn to_json(self : Prompt) -> Json {
  let fields : Map[String, Json] = { "name": Json::string(self.name) }
  put_optional_string(fields, "title", self.title)
  put_optional_string(fields, "description", self.description)
  if !self.arguments.is_empty() {
    fields["arguments"] = self.arguments
      .map(fn(arg) { arg.to_json() })
      .to_json()
  }
  if !self.icons.is_empty() {
    fields["icons"] = self.icons.map(fn(icon) { icon.to_json() }).to_json()
  }
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
pub impl @json.FromJson for Prompt with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> Prompt raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let name = match fields.get("name") {
    Some(String(s)) => s
    Some(_) => raise JsonDecodeError((path.add_key("name"), "expected string"))
    None => raise JsonDecodeError((path.add_key("name"), "name is required"))
  }
  let title = match fields.get("title") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) => raise JsonDecodeError((path.add_key("title"), "expected string"))
  }
  let description = match fields.get("description") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("description"), "expected string"))
  }
  let arguments : Array[PromptArgument] = match fields.get("arguments") {
    Some(Array(arr)) => {
      let result : Array[PromptArgument] = []
      for i, it in arr {
        result.push(
          @json.from_json(it) catch {
            JsonDecodeError((_, msg)) =>
              raise JsonDecodeError(
                (path.add_key("arguments").add_index(i), msg),
              )
          },
        )
      }
      result
    }
    Some(Null) | None => []
    Some(_) =>
      raise JsonDecodeError((path.add_key("arguments"), "expected array"))
  }
  validate_prompt_argument_names(arguments, "prompt.arguments") catch {
    error => raise JsonDecodeError((path.add_key("arguments"), error.message()))
  }
  let icons : Array[Icon] = match fields.get("icons") {
    Some(Array(arr)) => {
      let result : Array[Icon] = []
      for i, it in arr {
        result.push(
          @json.from_json(it) catch {
            JsonDecodeError((_, msg)) =>
              raise JsonDecodeError((path.add_key("icons").add_index(i), msg))
          },
        )
      }
      result
    }
    Some(Null) | None => []
    Some(_) => raise JsonDecodeError((path.add_key("icons"), "expected array"))
  }
  let meta = fields.get("_meta")
  Prompt(name~, title?, description?, arguments~, icons~, meta?)
}

///|
pub fn Prompt::from_json(
  value : Json,
  context? : String = "prompt",
) -> Prompt raise McpError {
  decode_json(value, context~)
}

///|
pub struct PromptMessage {
  role : Role
  content : Content
} derive(Debug, Eq)

///|
pub fn PromptMessage::PromptMessage(
  role~ : Role,
  content~ : Content,
) -> PromptMessage {
  { role, content }
}

///|
pub fn PromptMessage::user(text : String) -> PromptMessage {
  { role: User, content: Content::text(text) }
}

///|
pub fn PromptMessage::assistant(text : String) -> PromptMessage {
  { role: Assistant, content: Content::text(text) }
}

///|
pub impl ToJson for PromptMessage with fn to_json(self : PromptMessage) -> Json {
  Json::object({
    "role": self.role.to_json(),
    "content": self.content.to_json(),
  })
}

///|
pub impl @json.FromJson for PromptMessage with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> PromptMessage raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let role_val = match fields.get("role") {
    Some(v) => v
    None => raise JsonDecodeError((path.add_key("role"), "role is required"))
  }
  let role : Role = @json.from_json(role_val) catch {
    JsonDecodeError((_, msg)) =>
      raise JsonDecodeError((path.add_key("role"), msg))
  }
  let content_val = match fields.get("content") {
    Some(v) => v
    None =>
      raise JsonDecodeError((path.add_key("content"), "content is required"))
  }
  let content : Content = @json.from_json(content_val) catch {
    JsonDecodeError((_, msg)) =>
      raise JsonDecodeError((path.add_key("content"), msg))
  }
  PromptMessage(role~, content~)
}

///|
pub fn PromptMessage::from_json(
  value : Json,
  context? : String = "prompt message",
) -> PromptMessage raise McpError {
  decode_json(value, context~)
}

///|
pub struct GetPromptResult {
  description : String?
  messages : Array[PromptMessage]
  meta : ResultMeta?
} derive(Debug, Eq)

///|
/// Construct a prompt result and retain an owned message array.
pub fn GetPromptResult::GetPromptResult(
  messages~ : Array[PromptMessage],
  description? : String,
  meta? : ResultMeta,
) -> GetPromptResult {
  {
    description,
    messages: messages.copy(),
    meta: copy_optional_result_meta(meta),
  }
}

///|
pub impl ToJson for GetPromptResult with fn to_json(self : GetPromptResult) -> Json {
  let fields : Map[String, Json] = {
    "messages": self.messages.map(fn(message) { message.to_json() }).to_json(),
  }
  put_optional_string(fields, "description", self.description)
  if self.meta is Some(meta) {
    fields["_meta"] = meta.to_json()
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for GetPromptResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> GetPromptResult raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let description = match fields.get("description") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("description"), "expected string"))
  }
  let messages_val = match fields.get("messages") {
    Some(Array(arr)) => arr
    Some(_) =>
      raise JsonDecodeError((path.add_key("messages"), "expected array"))
    None =>
      raise JsonDecodeError((path.add_key("messages"), "messages is required"))
  }
  let messages : Array[PromptMessage] = []
  for i, it in messages_val {
    messages.push(
      @json.from_json(it) catch {
        JsonDecodeError((_, msg)) =>
          raise JsonDecodeError((path.add_key("messages").add_index(i), msg))
      },
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
  { description, messages, meta }
}

///|
pub fn GetPromptResult::from_json(
  value : Json,
) -> GetPromptResult raise McpError {
  decode_json(value, context="prompts/get result")
}

///|
/// Construct a single user prompt message result.
pub fn GetPromptResult::user(
  text : String,
  description? : String,
) -> GetPromptResult {
  { description, messages: [PromptMessage::user(text)], meta: None }
}

///|
/// Canonical decoded result of `prompts/list`.
pub struct ListPromptsResult {
  prompts : Array[Prompt]
  next_cursor : String?
  cache_policy : CachePolicy
  meta : ResultMeta?
} derive(Debug, Eq)

///|
pub impl ToJson for ListPromptsResult with fn to_json(self : ListPromptsResult) -> Json {
  let fields : Map[String, Json] = {
    "resultType": ResultType::Complete.to_json(),
    "prompts": self.prompts.map(fn(p) { p.to_json() }).to_json(),
  }
  put_optional_string(fields, "nextCursor", self.next_cursor)
  self.cache_policy.put(fields)
  if self.meta is Some(meta) {
    fields["_meta"] = meta.to_json()
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for ListPromptsResult with fn from_json(
  value : Json,
  path : @json.JsonPath,
) -> ListPromptsResult raise {
  guard value is Object(fields) else {
    raise JsonDecodeError((path, "expected object"))
  }
  let p_val = match fields.get("prompts") {
    Some(Array(arr)) => arr
    Some(_) =>
      raise JsonDecodeError((path.add_key("prompts"), "expected array"))
    None =>
      raise JsonDecodeError((path.add_key("prompts"), "prompts is required"))
  }
  let prompts : Array[Prompt] = []
  for i, it in p_val {
    prompts.push(
      @json.from_json(it) catch {
        JsonDecodeError((_, msg)) =>
          raise JsonDecodeError((path.add_key("prompts").add_index(i), msg))
      },
    )
  }
  let next_cursor = match fields.get("nextCursor") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("nextCursor"), "expected string"))
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
  { prompts, next_cursor, cache_policy, meta }
}

///|
pub fn ListPromptsResult::from_json(
  value : Json,
) -> ListPromptsResult raise McpError {
  decode_json(value, context="prompts/list result")
}
