///|
pub(all) struct PromptArgument {
  name : String
  title : String?
  description : String?
  required : Bool
} derive(Debug, Eq)

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
pub(all) struct Prompt {
  name : String
  title : String?
  description : String?
  arguments : Array[PromptArgument]
  meta : Json?
} derive(Debug, Eq)

///|
pub fn Prompt::Prompt(
  name~ : String,
  title? : String,
  description? : String,
  arguments? : Array[PromptArgument] = [],
  meta? : Json,
) -> Prompt {
  { name, title, description, arguments, meta }
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
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}

///|
pub(all) struct PromptMessage {
  role : String
  content : ContentBlock
} derive(Debug, Eq)

///|
pub fn PromptMessage::user(text : String) -> PromptMessage {
  { role: "user", content: Text(text) }
}

///|
pub fn PromptMessage::assistant(text : String) -> PromptMessage {
  { role: "assistant", content: Text(text) }
}

///|
pub impl ToJson for PromptMessage with fn to_json(self : PromptMessage) -> Json {
  Json::object({
    "role": Json::string(self.role),
    "content": self.content.to_json(),
  })
}

///|
pub(all) struct GetPromptResult {
  description : String?
  messages : Array[PromptMessage]
  meta : Json?
} derive(Debug, Eq)

///|
pub impl ToJson for GetPromptResult with fn to_json(self : GetPromptResult) -> Json {
  let fields : Map[String, Json] = {
    "messages": self.messages.map(fn(message) { message.to_json() }).to_json(),
  }
  put_optional_string(fields, "description", self.description)
  put_optional_json(fields, "_meta", self.meta)
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
