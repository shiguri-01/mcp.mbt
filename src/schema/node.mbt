///|
/// A trait representing a JSON Schema (Draft 2020-12) node.
/// Every specific schema type (StringSchema, ObjectSchema, ArraySchema, etc.)
/// implements this trait.
pub(open) trait SchemaNode: ToJson + @debug.Debug {
  fn into_schema(Self) -> Schema
  fn validate(
    Self,
    instance : Json,
    path~ : @json.JsonPath,
    depth~ : Int,
    ctx~ : ValidationContext,
  ) -> Unit
}

///|
/// A first-class JSON Schema value wrapping any SchemaNode.
pub struct Schema {
  node : &SchemaNode
}

///|
pub impl Eq for Schema with fn equal(self : Schema, other : Schema) -> Bool {
  self.to_json() == other.to_json()
}

///|
pub impl Show for Schema with fn output(self : Schema, logger : &Logger) -> Unit {
  logger.write_string(self.to_json().stringify())
}

///|
pub impl @debug.Debug for Schema with fn to_repr(self : Schema) -> @debug.Repr {
  @debug.Repr::string(self.to_json().stringify())
}

///|
pub impl ToJson for Schema with fn to_json(self : Schema) -> Json {
  ToJson::to_json(self.node)
}

///|
pub impl SchemaNode for Schema with fn into_schema(self : Schema) -> Schema {
  self
}

///|
pub impl SchemaNode for Schema with fn validate(
  self : Schema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  self.node.validate(instance, path~, depth~, ctx~)
}

///|
pub fn Schema::to_json(self : Schema) -> Json {
  ToJson::to_json(self.node)
}

///|
pub fn Schema::document(self : Schema) -> Document raise SchemaError {
  Document::Document(self.to_json())
}

///|
pub fn Schema::from_json(value : Json) -> Schema raise SchemaError {
  parse_schema_json(value)
}

///|
pub fn Schema::validate(
  self : Schema,
  instance : Json,
  path? : @json.JsonPath,
  depth? : Int = 0,
  ctx~ : ValidationContext,
) -> Unit {
  let p = match path {
    Some(p) => p
    None => root_json_path()
  }
  self.node.validate(instance, path=p, depth~, ctx~)
}

///|
pub fn[T : SchemaNode] Schema::from_node(node : T) -> Schema {
  { node, }
}
