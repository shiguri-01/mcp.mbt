///|
/// A trait representing a JSON Schema (Draft 2020-12) node.
/// Sealed to this package to prevent external invalid schema nodes.
priv trait SchemaNode: ToJson + @debug.Debug {
  fn validate(
    Self,
    instance : Json,
    path~ : @json.JsonPath,
    depth~ : Int,
    ctx~ : ValidationContext,
  ) -> Unit
}

///|
/// A first-class JSON Schema value wrapping any JSON Schema construct.
pub struct Schema {
  priv node : &SchemaNode
  priv defs : Map[String, Schema]
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
pub fn Schema::to_json(self : Schema) -> Json {
  ToJson::to_json(self.node)
}

///|
/// Parse a JSON value as a JSON Schema document (Draft 2020-12).
pub fn Schema::from_json(
  value : Json,
  max_depth? : Int = 128,
  max_nodes? : Int = 10000,
) -> Schema raise SchemaError {
  if max_depth <= 0 || max_nodes <= 0 {
    raise InvalidSchema("schema compilation limits must be positive")
  }
  validate_document_compilation(value, max_depth, max_nodes)
  let defs : Map[String, Schema] = Map([])
  collect_definitions(value, defs, "#", 0, max_depth)
  let parsed = parse_schema_json(value)
  { node: parsed.node, defs }
}

///|
/// Validate a JSON instance against this schema.
pub fn Schema::validate(
  self : Schema,
  instance : Json,
  max_depth? : Int = 128,
) -> ValidationResult {
  let ctx : ValidationContext = { defs: self.defs, max_depth, errors: [] }
  self.node.validate(instance, path=root_json_path(), depth=0, ctx~)
  { valid: ctx.errors.is_empty(), errors: ctx.errors }
}

///|
fn[T : SchemaNode] Schema::from_node(
  node : T,
  defs? : Map[String, Schema] = {},
) -> Schema {
  { node, defs }
}

///|
/// Create a boolean schema (`true` or `false`).
pub fn Schema::boolean(value : Bool) -> Schema {
  if value {
    Schema::from_node(BooleanSchema::always())
  } else {
    Schema::from_node(BooleanSchema::never())
  }
}

///|
/// A boolean schema that always passes validation (`true`).
pub fn Schema::always() -> Schema {
  Schema::from_node(BooleanSchema::always())
}

///|
/// A boolean schema that always fails validation (`false`).
pub fn Schema::never() -> Schema {
  Schema::from_node(BooleanSchema::never())
}

///|
/// A `null` type schema.
pub fn Schema::null(description? : String) -> Schema {
  Schema::from_node(NullSchema(description?))
}

///|
/// A `boolean` type schema (`type: "boolean"`).
pub fn Schema::bool_type(description? : String) -> Schema {
  Schema::from_node(BoolTypeSchema(description?))
}

///|
/// A `string` type schema.
pub fn Schema::string(
  min_length? : Int,
  max_length? : Int,
  description? : String,
) -> Schema raise SchemaError {
  Schema::from_node(StringSchema(min_length?, max_length?, description?))
}

///|
/// An `integer` type schema.
pub fn Schema::integer(
  minimum? : Int,
  maximum? : Int,
  description? : String,
) -> Schema raise SchemaError {
  Schema::from_node(IntegerSchema(minimum?, maximum?, description?))
}

///|
/// A `number` type schema.
pub fn Schema::number(
  minimum? : Double,
  maximum? : Double,
  exclusive_minimum? : Double,
  exclusive_maximum? : Double,
  multiple_of? : Double,
  description? : String,
) -> Schema raise SchemaError {
  Schema::from_node(
    NumberSchema(
      minimum?,
      maximum?,
      exclusive_minimum?,
      exclusive_maximum?,
      multiple_of?,
      description?,
    ),
  )
}

///|
/// An `array` type schema.
pub fn Schema::array(
  items? : Schema,
  min_items? : Int,
  max_items? : Int,
  unique_items? : Bool = false,
  description? : String,
) -> Schema raise SchemaError {
  Schema::from_node(
    ArraySchema(items?, min_items?, max_items?, unique_items~, description?),
  )
}

///|
/// An `object` type schema.
pub fn Schema::object(
  properties? : Map[String, Schema] = {},
  required? : Array[String] = [],
  additional_properties? : Bool = true,
  min_properties? : Int,
  max_properties? : Int,
  description? : String,
) -> Schema raise SchemaError {
  Schema::from_node(
    ObjectSchema(
      properties~,
      required~,
      additional_properties~,
      min_properties?,
      max_properties?,
      description?,
    ),
  )
}

///|
/// A `const` assertion schema.
pub fn[T : ToJson] Schema::constant(value : T, description? : String) -> Schema {
  Schema::from_node(ConstSchema::from_value(value, description?))
}

///|
/// An `enum` assertion schema.
pub fn[T : ToJson] Schema::enumeration(
  values : Array[T],
  description? : String,
) -> Schema raise SchemaError {
  Schema::from_node(EnumSchema::from_values(values, description?))
}

///|
/// An `allOf` combinator schema.
pub fn Schema::all_of(values : Array[Schema], description? : String) -> Schema {
  Schema::from_node(AllOfSchema(values, description?))
}

///|
/// An `anyOf` combinator schema.
pub fn Schema::any_of(
  values : Array[Schema],
  description? : String,
) -> Schema raise SchemaError {
  Schema::from_node(AnyOfSchema(values, description?))
}

///|
/// A `oneOf` combinator schema.
pub fn Schema::one_of(
  values : Array[Schema],
  description? : String,
) -> Schema raise SchemaError {
  Schema::from_node(OneOfSchema(values, description?))
}

///|
/// A `not` combinator schema.
pub fn Schema::not(value : Schema, description? : String) -> Schema {
  Schema::from_node(NotSchema(value, description?))
}

///|
/// A `$ref` reference schema.
pub fn Schema::ref_(
  reference : String,
  description? : String,
) -> Schema raise SchemaError {
  Schema::from_node(RefSchema(reference, description?))
}

///|
/// An unconstrained escape hatch schema for raw JSON.
pub fn Schema::raw(value : Json) -> Schema raise SchemaError {
  Schema::from_node(RawSchema(value))
}
