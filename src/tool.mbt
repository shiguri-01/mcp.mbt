///|
pub struct ToolAnnotations {
  title : String?
  read_only_hint : Bool?
  destructive_hint : Bool?
  idempotent_hint : Bool?
  open_world_hint : Bool?
} derive(Debug, Eq)

///|
/// Construct optional tool behavior annotations.
pub fn ToolAnnotations::ToolAnnotations(
  title? : String,
  read_only_hint? : Bool,
  destructive_hint? : Bool,
  idempotent_hint? : Bool,
  open_world_hint? : Bool,
) -> ToolAnnotations {
  { title, read_only_hint, destructive_hint, idempotent_hint, open_world_hint }
}

///|
pub impl ToJson for ToolAnnotations with fn to_json(self : ToolAnnotations) -> Json {
  let fields : Map[String, Json] = Map([])
  put_optional_string(fields, "title", self.title)
  put_optional_bool(fields, "readOnlyHint", self.read_only_hint)
  put_optional_bool(fields, "destructiveHint", self.destructive_hint)
  put_optional_bool(fields, "idempotentHint", self.idempotent_hint)
  put_optional_bool(fields, "openWorldHint", self.open_world_hint)
  Json::object(fields)
}

///|
/// MCP tool descriptor.
pub struct Tool {
  name : String
  title : String?
  description : String?
  input_schema : Json
  output_schema : Json?
  annotations : ToolAnnotations?
  icons : Array[Icon]
  meta : Json?
} derive(Debug, Eq)

///|
/// Copy a tool descriptor before handing it to an adapter.
fn Tool::copy(self : Tool) -> Tool {
  {
    ..self,
    input_schema: copy_json(self.input_schema),
    output_schema: copy_optional_json(self.output_schema),
    icons: self.icons.map(icon => icon.copy()),
    meta: copy_optional_json(self.meta),
  }
}

///|
/// Construct a tool descriptor.
pub fn Tool::Tool(
  name~ : String,
  title? : String,
  description? : String,
  input_schema? : Json = empty_object_schema(),
  output_schema? : Json,
  annotations? : ToolAnnotations,
  icons? : Array[Icon] = [],
  meta? : Json,
) -> Tool raise McpError {
  validate_tool_input_schema(input_schema)
  match output_schema {
    Some(schema) => validate_tool_document(schema, "tool outputSchema")
    None => ()
  }
  {
    name,
    title,
    description,
    input_schema: copy_json(input_schema),
    output_schema: copy_optional_json(output_schema),
    annotations,
    icons: icons.map(icon => icon.copy()),
    meta: copy_optional_json(meta),
  }
}

///|
fn validate_tool_input_schema(schema : Json) -> Unit raise McpError {
  validate_tool_document(schema, "tool inputSchema")
  guard schema is Object(fields) else {
    raise InvalidParams("tool inputSchema must be a JSON Schema object")
  }
  guard fields.get("type") is Some(String("object")) else {
    raise InvalidParams("tool inputSchema root type must be \"object\"")
  }
}

///|
fn validate_tool_document(
  schema : Json,
  context : String,
) -> Unit raise McpError {
  ignore(
    @schema.Document::Document(schema) catch {
      _ => raise InvalidParams("\{context} is not a valid JSON Schema document")
    },
  )
}

///|
pub impl ToJson for Tool with fn to_json(self : Tool) -> Json {
  let fields : Map[String, Json] = {
    "name": Json::string(self.name),
    "inputSchema": copy_json(self.input_schema),
  }
  put_optional_string(fields, "title", self.title)
  put_optional_string(fields, "description", self.description)
  put_optional_json(fields, "outputSchema", self.output_schema)
  match self.annotations {
    Some(annotations) => fields["annotations"] = annotations.to_json()
    None => ()
  }
  if !self.icons.is_empty() {
    fields["icons"] = self.icons.map(fn(icon) { icon.to_json() }).to_json()
  }
  put_optional_json(fields, "_meta", self.meta)
  Json::object(fields)
}
