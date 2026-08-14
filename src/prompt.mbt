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
/// Construct a single user prompt message result.
pub fn GetPromptResult::user(
  text : String,
  description? : String,
) -> GetPromptResult {
  { description, messages: [PromptMessage::user(text)], meta: None }
}
