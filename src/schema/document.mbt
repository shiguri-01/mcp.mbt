///|
/// A typed programmatic JSON Schema value for the common 2020-12 keywords.
/// `Raw` is the explicit escape hatch for keywords not modeled here.
priv enum SchemaNode {
  Always
  Never
  Null
  Boolean
  Integer
  Number
  String
  StringConstraints(Int?, Int?)
  Array(SchemaNode)
  ArrayConstraints(SchemaNode, Int?, Int?, Bool)
  Object(Map[String, SchemaNode], Array[String], Bool)
  ObjectConstraints(Map[String, SchemaNode], Array[String], Bool, Int?, Int?)
  Const(Json)
  Enum(Array[Json])
  AllOf(Array[SchemaNode])
  AnyOf(Array[SchemaNode])
  OneOf(Array[SchemaNode])
  Not(SchemaNode)
  Reference(String)
  Description(SchemaNode, String)
  Raw(Json)
} derive(Debug, Eq)

///|
/// A validated JSON Schema value. The representation is private so callers
/// must use the constructors below and cannot create an invalid combinator or
/// reference directly.
pub struct Schema {
  priv node : SchemaNode
} derive(Debug, Eq)

///|
fn schema(node : SchemaNode) -> Schema {
  { node, }
}

///|
fn[K : Eq + Hash, V] Map::set_opt(
  self : Map[K, V],
  key : K,
  value : V?,
) -> Unit {
  if value is Some(v) {
    self[key] = v
  }
}

///|
pub fn Schema::always() -> Schema {
  schema(Always)
}

///|
pub fn Schema::never() -> Schema {
  schema(Never)
}

///|
pub fn Schema::null() -> Schema {
  schema(Null)
}

///|
pub fn Schema::boolean() -> Schema {
  schema(Boolean)
}

///|
pub fn Schema::integer() -> Schema {
  schema(Integer)
}

///|
pub fn Schema::number() -> Schema {
  schema(Number)
}

///|
pub fn Schema::string() -> Schema {
  schema(String)
}

///|
/// Build a string schema with the standard JSON Schema string constraints.
/// The constraint values are checked while constructing the typed schema;
/// callers do not need a later validation pass just to discover invalid
/// bounds.
pub fn Schema::string_constraints(
  min_length? : Int,
  max_length? : Int,
) -> Schema raise SchemaError {
  if min_length is Some(value) && value < 0 {
    raise InvalidSchema("minLength must be non-negative")
  }
  if max_length is Some(value) && value < 0 {
    raise InvalidSchema("maxLength must be non-negative")
  }
  if min_length is Some(min) && max_length is Some(max) && min > max {
    raise InvalidSchema("minLength must not exceed maxLength")
  }
  schema(StringConstraints(min_length, max_length))
}

///|
pub fn Schema::array(items~ : Schema) -> Schema {
  schema(Array(items.node))
}

///|
/// Build an array schema with typed size and uniqueness constraints.
pub fn Schema::array_constraints(
  items~ : Schema,
  min_items? : Int,
  max_items? : Int,
  unique_items? : Bool = false,
) -> Schema raise SchemaError {
  validate_bounds(min_items, max_items, "items")
  schema(ArrayConstraints(items.node, min_items, max_items, unique_items))
}

///|
pub fn[T : ToJson] Schema::const_value(value : T) -> Schema {
  schema(Const(value.to_json()))
}

///|
pub fn[T : ToJson] Schema::enum_values(
  values : Array[T],
) -> Schema raise SchemaError {
  if values.is_empty() {
    raise InvalidSchema("JSON Schema enum must not be empty")
  }
  let encoded : Array[Json] = values.map(value => value.to_json())
  let seen : Array[Json] = []
  for value in encoded {
    if seen.contains(value) {
      raise InvalidSchema("JSON Schema enum values must be unique")
    }
    seen.push(value)
  }
  schema(Enum(encoded))
}

///|
pub fn Schema::all_of(values : Array[Schema]) -> Schema {
  schema(AllOf(values.map(value => value.node)))
}

///|
pub fn Schema::any_of(values : Array[Schema]) -> Schema raise SchemaError {
  if values.is_empty() {
    raise InvalidSchema("JSON Schema anyOf must not be empty")
  }
  schema(AnyOf(values.map(value => value.node)))
}

///|
pub fn Schema::one_of(values : Array[Schema]) -> Schema raise SchemaError {
  if values.is_empty() {
    raise InvalidSchema("JSON Schema oneOf must not be empty")
  }
  schema(OneOf(values.map(value => value.node)))
}

///|
pub fn Schema::not(value : Schema) -> Schema {
  schema(Not(value.node))
}

///|
/// Attach the standard JSON Schema description annotation to a schema.
pub fn Schema::description(value : Schema, description : String) -> Schema {
  schema(Description(value.node, description))
}

///|
pub fn Schema::reference(reference : String) -> Schema raise SchemaError {
  if !reference.has_prefix("#") {
    raise InvalidSchema("network JSON Schema references are disabled")
  }
  schema(Reference(reference))
}

///|
pub fn Schema::object(
  properties~ : Map[String, Schema],
  required? : Array[String] = [],
  additional_properties? : Bool = true,
) -> Schema raise SchemaError {
  let required_names : Map[String, Bool] = Map([])
  for name in required {
    if required_names.contains(name) {
      raise InvalidSchema("required property names must be unique")
    }
    required_names[name] = true
    if properties.get(name) is None {
      raise InvalidSchema("required property is not declared: \{name}")
    }
  }
  let nodes : Map[String, SchemaNode] = Map([])
  for name, value in properties {
    nodes[name] = value.node
  }
  schema(Object(nodes, required.copy(), additional_properties))
}

///|
/// Build an object schema with typed property-count constraints.
pub fn Schema::object_constraints(
  properties~ : Map[String, Schema],
  required? : Array[String] = [],
  additional_properties? : Bool = true,
  min_properties? : Int,
  max_properties? : Int,
) -> Schema raise SchemaError {
  validate_bounds(min_properties, max_properties, "properties")
  let base = Schema::object(properties~, required~, additional_properties~)
  let nodes = match base.node {
    Object(values, names, additional) =>
      ObjectConstraints(
        values, names, additional, min_properties, max_properties,
      )
    _ => base.node
  }
  schema(nodes)
}

///|
/// Validate a pair of non-negative JSON Schema integer bounds.
fn validate_bounds(
  minimum : Int?,
  maximum : Int?,
  label : String,
) -> Unit raise SchemaError {
  if minimum is Some(value) && value < 0 {
    raise InvalidSchema("min\{label} must be non-negative")
  }
  if maximum is Some(value) && value < 0 {
    raise InvalidSchema("max\{label} must be non-negative")
  }
  if minimum is Some(min) && maximum is Some(max) && min > max {
    raise InvalidSchema("min\{label} must not exceed max\{label}")
  }
}

///|
pub fn Schema::raw(value : Json) -> Schema raise SchemaError {
  ignore(Document::Document(value))
  schema(Raw(value))
}

///|
pub fn Schema::to_json(self : Schema) -> Json {
  schema_node_to_json(self.node)
}

///|
fn schema_node_to_json(node : SchemaNode) -> Json {
  match node {
    Always => Json::boolean(true)
    Never => Json::boolean(false)
    Null => Json::object({ "type": Json::string("null") })
    Boolean => Json::object({ "type": Json::string("boolean") })
    Integer => Json::object({ "type": Json::string("integer") })
    Number => Json::object({ "type": Json::string("number") })
    String => Json::object({ "type": Json::string("string") })
    StringConstraints(min_length, max_length) => {
      let fields : Map[String, Json] = { "type": Json::string("string") }
      match min_length {
        Some(value) =>
          fields["minLength"] = Json::number(
            value.to_double(),
            repr=value.to_string(),
          )
        None => ()
      }
      match max_length {
        Some(value) =>
          fields["maxLength"] = Json::number(
            value.to_double(),
            repr=value.to_string(),
          )
        None => ()
      }
      Json::object(fields)
    }
    Array(items) =>
      Json::object({
        "type": Json::string("array"),
        "items": schema_node_to_json(items),
      })
    ArrayConstraints(items, min_items, max_items, unique_items) => {
      let fields : Map[String, Json] = {
        "type": Json::string("array"),
        "items": schema_node_to_json(items),
        "uniqueItems": Json::boolean(unique_items),
      }
      fields.set_opt(
        "minItems",
        min_items.map(fn(n) { Json::number(n.to_double(), repr=n.to_string()) }),
      )
      fields.set_opt(
        "maxItems",
        max_items.map(fn(n) { Json::number(n.to_double(), repr=n.to_string()) }),
      )
      Json::object(fields)
    }
    Object(properties, required, additional_properties) => {
      let fields : Map[String, Json] = Map([])
      let property_fields : Map[String, Json] = Map([])
      for name, schema in properties {
        property_fields[name] = schema_node_to_json(schema)
      }
      fields["type"] = Json::string("object")
      fields["properties"] = Json::object(property_fields)
      fields["required"] = required.to_json()
      fields["additionalProperties"] = Json::boolean(additional_properties)
      Json::object(fields)
    }
    ObjectConstraints(
      properties,
      required,
      additional_properties,
      min_properties,
      max_properties
    ) => {
      let fields = schema_node_to_json(
        Object(properties, required, additional_properties),
      )
      guard fields is Object(fields) else { return fields }
      fields.set_opt(
        "minProperties",
        min_properties.map(fn(n) {
          Json::number(n.to_double(), repr=n.to_string())
        }),
      )
      fields.set_opt(
        "maxProperties",
        max_properties.map(fn(n) {
          Json::number(n.to_double(), repr=n.to_string())
        }),
      )
      Json::object(fields)
    }
    Const(value) => Json::object({ "const": value })
    Enum(values) => Json::object({ "enum": values.to_json() })
    AllOf(values) =>
      Json::object({ "allOf": values.map(schema_node_to_json).to_json() })
    AnyOf(values) =>
      Json::object({ "anyOf": values.map(schema_node_to_json).to_json() })
    OneOf(values) =>
      Json::object({ "oneOf": values.map(schema_node_to_json).to_json() })
    Not(value) => Json::object({ "not": schema_node_to_json(value) })
    Reference(reference) => Json::object({ "$ref": Json::string(reference) })
    Description(value, description) => {
      guard schema_node_to_json(value) is Object(fields) else {
        return Json::object({
          "allOf": Json::array([schema_node_to_json(value)]),
          "description": Json::string(description),
        })
      }
      fields["description"] = Json::string(description)
      Json::object(fields)
    }
    Raw(value) => value
  }
}

///|
pub impl ToJson for Schema with fn to_json(self) -> Json {
  self.to_json()
}

///|
pub fn Schema::document(self : Schema) -> Document raise SchemaError {
  Document::Document(self.to_json())
}

///|
/// A JSON Schema document owned by the schema package.
///
/// `Document` performs document-level checks only. It does not validate an
/// instance and it never resolves a network reference. The JSON value is
/// retained so `$id`, `$ref`, `$defs`, and extension vocabularies are not
/// silently discarded.
pub struct Document {
  value : Json
  dialect : String
} derive(Debug, Eq)

///|
pub impl ToJson for Document with fn to_json(self) -> Json {
  self.value
}

///|
pub fn Document::Document(value : Json) -> Document raise SchemaError {
  if value is (True | False) {
    return { value, dialect: draft_2020_12 }
  }
  guard value is Object(fields) else {
    raise InvalidDocument("a JSON Schema document must be an object or boolean")
  }
  let dialect = match fields.get("$schema") {
    None => draft_2020_12
    Some(String(value)) if value == draft_2020_12 => value
    Some(String(value)) => raise UnsupportedDialect(value)
    Some(_) => raise InvalidDocument("$schema must be a string")
  }
  if fields.get("$id") is Some(id) && !(id is String(_)) {
    raise InvalidDocument("$id must be a string")
  }
  if fields.get("$ref") is Some(reference) && !(reference is String(_)) {
    raise InvalidDocument("$ref must be a string")
  }
  validate_references(value, 0, 128)
  { value, dialect }
}

///|
pub struct CompileOptions {
  max_depth : Int
  max_nodes : Int
} derive(Debug, Eq)

///|
pub fn CompileOptions::CompileOptions(
  max_depth? : Int = 128,
  max_nodes? : Int = 10000,
) -> CompileOptions raise SchemaError {
  if max_depth <= 0 || max_nodes <= 0 {
    raise InvalidSchema("schema compilation limits must be positive")
  }
  { max_depth, max_nodes }
}

///|
pub fn CompileOptions::default() -> CompileOptions {
  try! CompileOptions()
}

///|
pub struct CompiledSchema {
  document : Document
  options : CompileOptions
} derive(Debug, Eq)

///|
pub fn Document::compile(
  self : Document,
  options? : CompileOptions = CompileOptions::default(),
) -> CompiledSchema raise SchemaError {
  let nodes = count_schema_nodes(self.value, 0, options.max_depth)
  if nodes > options.max_nodes {
    raise InvalidSchema("schema exceeds max_nodes")
  }
  validate_references(self.value, 0, options.max_depth)
  validate_supported_keywords(self.value, 0, options.max_depth)
  validate_keyword_shapes(self.value, 0, options.max_depth)
  { document: self, options }
}

///|
pub struct ValidationResult {
  valid : Bool
  errors : Array[String]
} derive(Debug, Eq)

///|
pub fn CompiledSchema::validate(
  self : CompiledSchema,
  instance : Json,
) -> ValidationResult {
  let errors : Array[String] = []
  validate_instance(
    self.document.value,
    self.document.value,
    instance,
    "$",
    0,
    self.options,
    errors,
  )
  { valid: errors.is_empty(), errors }
}

///|
fn count_schema_nodes(
  value : Json,
  depth : Int,
  max_depth : Int,
) -> Int raise SchemaError {
  if depth > max_depth {
    raise InvalidSchema("schema exceeds max_depth")
  }
  match value {
    Object(fields) => {
      let mut count = 1
      for _, child in fields {
        count += count_schema_nodes(child, depth + 1, max_depth)
      }
      count
    }
    Array(values) => {
      let mut count = 1
      for child in values {
        count += count_schema_nodes(child, depth + 1, max_depth)
      }
      count
    }
    _ => 1
  }
}

///|
fn validate_references(
  value : Json,
  depth : Int,
  max_depth : Int,
) -> Unit raise SchemaError {
  if depth > max_depth {
    raise InvalidSchema("schema exceeds max_depth")
  }
  match value {
    Object(fields) => {
      match fields.get("$ref") {
        Some(String(reference)) if !reference.has_prefix("#") =>
          raise InvalidSchema("network JSON Schema references are disabled")
        Some(String(_)) => ()
        Some(_) => raise InvalidSchema("JSON Schema $ref must be a string")
        None => ()
      }
      match fields.get("$dynamicRef") {
        Some(String(reference)) if !reference.has_prefix("#") =>
          raise InvalidSchema("network JSON Schema references are disabled")
        Some(String(_)) => ()
        Some(_) =>
          raise InvalidSchema("JSON Schema $dynamicRef must be a string")
        None => ()
      }
      for child in schema_children(fields) {
        validate_references(child, depth + 1, max_depth)
      }
    }
    Array(_) => ()
    _ => ()
  }
}

///|
/// The portable validator rejects keywords it cannot evaluate instead of
/// silently accepting instances that were never checked.
fn validate_supported_keywords(
  value : Json,
  depth : Int,
  max_depth : Int,
) -> Unit raise SchemaError {
  if depth > max_depth {
    raise InvalidSchema("schema exceeds max_depth")
  }
  match value {
    Object(fields) => {
      for
        keyword in [
          "pattern", "contains", "prefixItems", "patternProperties", "propertyNames",
          "dependentRequired", "dependentSchemas", "if", "then", "else", "unevaluatedItems",
          "unevaluatedProperties", "format", "contentEncoding", "contentMediaType",
          "$dynamicRef",
        ] {
        if fields.contains(keyword) {
          raise UnsupportedKeyword(keyword)
        }
      }
      for child in schema_children(fields) {
        validate_supported_keywords(child, depth + 1, max_depth)
      }
    }
    Array(_) => ()
    _ => ()
  }
}

///|
/// Validate the shapes of keywords understood by the bounded evaluator. This
/// keeps malformed schemas out of `CompiledSchema`; instance validation can
/// therefore focus on instances rather than reinterpreting schema syntax.
fn validate_keyword_shapes(
  value : Json,
  depth : Int,
  max_depth : Int,
) -> Unit raise SchemaError {
  if depth > max_depth {
    raise InvalidSchema("schema exceeds max_depth")
  }
  match value {
    Object(fields) => {
      match fields.get("type") {
        Some(String(_)) | None => ()
        Some(_) => raise InvalidSchema("schema type must be a string")
      }
      match fields.get("enum") {
        Some(Array(values)) if !values.is_empty() => ()
        Some(Array(_)) => raise InvalidSchema("schema enum must not be empty")
        Some(_) => raise InvalidSchema("schema enum must be an array")
        None => ()
      }
      for
        keyword in [
          "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
        ] {
        match fields.get(keyword) {
          Some(Number(value, ..)) if !value.is_nan() && !value.is_inf() => ()
          Some(_) => raise InvalidSchema("{keyword} must be a finite number")
          None => ()
        }
      }
      for keyword in ["minLength", "maxLength"] {
        match fields.get(keyword) {
          Some(Number(value, ..)) if !value.is_nan() &&
            !value.is_inf() &&
            value >= 0.0 &&
            value == value.to_int().to_double() => ()
          Some(_) =>
            raise InvalidSchema("{keyword} must be a non-negative integer")
          None => ()
        }
      }
      match fields.get("multipleOf") {
        Some(Number(value, ..)) if !value.is_nan() &&
          !value.is_inf() &&
          value > 0.0 => ()
        Some(_) => raise InvalidSchema("multipleOf must be a positive number")
        None => ()
      }
      for keyword in ["minItems", "maxItems", "minProperties", "maxProperties"] {
        match fields.get(keyword) {
          Some(Number(value, ..)) if !value.is_nan() &&
            !value.is_inf() &&
            value >= 0.0 &&
            value == value.to_int().to_double() => ()
          Some(_) =>
            raise InvalidSchema("{keyword} must be a non-negative integer")
          None => ()
        }
      }
      for keyword in ["allOf", "anyOf", "oneOf"] {
        match fields.get(keyword) {
          Some(Array(values)) if keyword == "allOf" || !values.is_empty() => ()
          Some(Array(_)) => raise InvalidSchema("{keyword} must not be empty")
          Some(_) => raise InvalidSchema("{keyword} must be an array")
          None => ()
        }
      }
      match fields.get("required") {
        Some(Array(names)) => {
          let seen : Map[String, Bool] = Map([])
          for name in names {
            match name {
              String(name) if !seen.contains(name) => seen[name] = true
              String(_) =>
                raise InvalidSchema("required property names must be unique")
              _ => raise InvalidSchema("required names must be strings")
            }
          }
        }
        Some(_) => raise InvalidSchema("required must be an array")
        None => ()
      }
      match fields.get("properties") {
        Some(Object(_)) => ()
        Some(_) => raise InvalidSchema("properties must be an object")
        None => ()
      }
      match fields.get("additionalProperties") {
        Some(True | False) | None => ()
        Some(_) =>
          raise InvalidSchema("additionalProperties schemas are unsupported")
      }
      match fields.get("items") {
        Some(Object(_) | True | False) | None => ()
        Some(_) => raise InvalidSchema("items must be a schema")
      }
      for child in schema_children(fields) {
        validate_keyword_shapes(child, depth + 1, max_depth)
      }
    }
    Array(_) => ()
    _ => ()
  }
}

///|
/// Return only values that are themselves schemas. Values of `const`, `enum`,
/// and annotations are instance data and must not be interpreted as schemas.
fn schema_children(fields : Map[String, Json]) -> Array[Json] {
  let children : Array[Json] = []
  for key in ["properties", "$defs", "definitions", "dependentSchemas"] {
    match fields.get(key) {
      Some(Object(values)) =>
        for _, child in values {
          children.push(child)
        }
      _ => ()
    }
  }
  for key in ["allOf", "anyOf", "oneOf"] {
    match fields.get(key) {
      Some(Array(values)) =>
        for child in values {
          children.push(child)
        }
      _ => ()
    }
  }
  for
    key in [
      "not", "items", "contains", "propertyNames", "if", "then", "else", "unevaluatedItems",
      "unevaluatedProperties",
    ] {
    match fields.get(key) {
      Some(child) if child is (Object(_) | True | False) => children.push(child)
      _ => ()
    }
  }
  children
}

///|
fn add_error(errors : Array[String], path : String, message : String) -> Unit {
  errors.push("\{path}: \{message}")
}

///|
fn type_matches(type_name : String, value : Json) -> Bool {
  match (type_name, value) {
    ("null", Null) => true
    ("boolean", True | False) => true
    ("object", Object(_)) => true
    ("array", Array(_)) => true
    ("string", String(_)) => true
    ("number", Number(_)) => true
    ("integer", Number(number, ..)) => number == number.to_int().to_double()
    _ => false
  }
}

///|
fn local_reference(root : Json, reference : String) -> Json? {
  if reference == "#" {
    return Some(root)
  }
  guard reference.has_prefix("#/") else { return None }
  let mut current = root
  for encoded in reference[2:].split("/") {
    let segment = encoded
      .to_owned()
      .replace_all(old="~1", new="/")
      .replace_all(old="~0", new="~")
    current = match current {
      Object(fields) =>
        match fields.get(segment) {
          Some(value) => value
          None => return None
        }
      Array(values) => {
        let mut index = 0
        if segment.is_empty() {
          return None
        }
        for char in segment {
          if !(char is ('0'..='9')) {
            return None
          }
          let digit = char.to_int() - '0'.to_int()
          if index > (2147483647 - digit) / 10 {
            return None
          }
          index = index * 10 + digit
        }
        if index < 0 || index >= values.length() {
          return None
        }
        values[index]
      }
      _ => return None
    }
  }
  Some(current)
}

///|
fn validate_instance(
  schema : Json,
  root : Json,
  instance : Json,
  path : String,
  depth : Int,
  options : CompileOptions,
  errors : Array[String],
) -> Unit {
  if depth > options.max_depth {
    add_error(errors, path, "validation exceeded max_depth")
    return
  }
  let resolved = match schema {
    Object(fields) =>
      match fields.get("$ref") {
        Some(String(reference)) =>
          local_reference(root, reference).unwrap_or(schema)
        _ => schema
      }
    _ => schema
  }
  match resolved {
    True => return
    False => {
      add_error(errors, path, "boolean schema is false")
      return
    }
    _ => ()
  }
  guard resolved is Object(fields) else { return }
  match fields.get("type") {
    Some(String(type_name)) if !type_matches(type_name, instance) =>
      add_error(errors, path, "value does not match type \{type_name}")
    _ => ()
  }
  match fields.get("enum") {
    Some(Array(values)) if !values.contains(instance) =>
      add_error(errors, path, "value is not in enum")
    _ => ()
  }
  match fields.get("const") {
    Some(expected) if expected != instance =>
      add_error(errors, path, "value does not match const")
    _ => ()
  }
  match (fields.get("minimum"), instance) {
    (Some(Number(limit, ..)), Number(value, ..)) if value < limit =>
      add_error(errors, path, "number is less than minimum")
    _ => ()
  }
  match (fields.get("maximum"), instance) {
    (Some(Number(limit, ..)), Number(value, ..)) if value > limit =>
      add_error(errors, path, "number is greater than maximum")
    _ => ()
  }
  match (fields.get("exclusiveMinimum"), instance) {
    (Some(Number(limit, ..)), Number(value, ..)) if value <= limit =>
      add_error(errors, path, "number is not greater than exclusiveMinimum")
    _ => ()
  }
  match (fields.get("exclusiveMaximum"), instance) {
    (Some(Number(limit, ..)), Number(value, ..)) if value >= limit =>
      add_error(errors, path, "number is not less than exclusiveMaximum")
    _ => ()
  }
  match (fields.get("minLength"), instance) {
    (Some(Number(limit, ..)), String(value)) if value.length() < limit.to_int() =>
      add_error(errors, path, "string is shorter than minLength")
    _ => ()
  }
  match (fields.get("maxLength"), instance) {
    (Some(Number(limit, ..)), String(value)) if value.length() > limit.to_int() =>
      add_error(errors, path, "string is longer than maxLength")
    _ => ()
  }
  match (fields.get("multipleOf"), instance) {
    (Some(Number(divisor, ..)), Number(value, ..)) if divisor > 0.0 => {
      let quotient = value / divisor
      if quotient != quotient.to_int().to_double() {
        add_error(errors, path, "number is not a multipleOf value")
      }
    }
    _ => ()
  }
  match (fields.get("minItems"), instance) {
    (Some(Number(limit, ..)), Array(values)) if values.length() < limit.to_int() =>
      add_error(errors, path, "array is shorter than minItems")
    _ => ()
  }
  match (fields.get("maxItems"), instance) {
    (Some(Number(limit, ..)), Array(values)) if values.length() > limit.to_int() =>
      add_error(errors, path, "array is longer than maxItems")
    _ => ()
  }
  match (fields.get("uniqueItems"), instance) {
    (Some(True), Array(values)) => {
      let seen : Array[Json] = []
      for value in values {
        if seen.contains(value) {
          add_error(errors, path, "array items must be unique")
        }
        seen.push(value)
      }
    }
    _ => ()
  }
  match (fields.get("minProperties"), instance) {
    (Some(Number(limit, ..)), Object(values)) if values.length() <
      limit.to_int() =>
      add_error(errors, path, "object has fewer than minProperties")
    _ => ()
  }
  match (fields.get("maxProperties"), instance) {
    (Some(Number(limit, ..)), Object(values)) if values.length() >
      limit.to_int() =>
      add_error(errors, path, "object has more than maxProperties")
    _ => ()
  }
  match fields.get("allOf") {
    Some(Array(values)) =>
      for child in values {
        validate_instance(
          child,
          root,
          instance,
          path,
          depth + 1,
          options,
          errors,
        )
      }
    _ => ()
  }
  match fields.get("anyOf") {
    Some(Array(values)) => {
      let mut matched = false
      for child in values {
        if schema_matches(child, root, instance, path, depth + 1, options) {
          matched = true
        }
      }
      if !matched {
        add_error(errors, path, "value does not match anyOf")
      }
    }
    _ => ()
  }
  match fields.get("oneOf") {
    Some(Array(values)) => {
      let mut matches = 0
      for child in values {
        if schema_matches(child, root, instance, path, depth + 1, options) {
          matches += 1
        }
      }
      if matches != 1 {
        add_error(errors, path, "value must match exactly one oneOf branch")
      }
    }
    _ => ()
  }
  match fields.get("not") {
    Some(child) if schema_matches(
        child,
        root,
        instance,
        path,
        depth + 1,
        options,
      ) => add_error(errors, path, "value matches a not schema")
    _ => ()
  }
  match (fields.get("properties"), instance) {
    (Some(Object(properties)), Object(instance_fields)) =>
      for name, property_schema in properties {
        match instance_fields.get(name) {
          Some(property) =>
            validate_instance(
              property_schema,
              root,
              property,
              path + "." + name,
              depth + 1,
              options,
              errors,
            )
          None => ()
        }
      }
    _ => ()
  }
  match (fields.get("required"), instance) {
    (Some(Array(names)), Object(instance_fields)) =>
      for name in names {
        match name {
          String(name) if instance_fields.get(name) is None =>
            add_error(errors, path, "required property is missing: \{name}")
          _ => ()
        }
      }
    _ => ()
  }
  match
    (fields.get("additionalProperties"), fields.get("properties"), instance) {
    (Some(False), Some(Object(properties)), Object(instance_fields)) =>
      for name, _ in instance_fields {
        if properties.get(name) is None {
          add_error(errors, path, "additional property is not allowed: \{name}")
        }
      }
    _ => ()
  }
  match (fields.get("items"), instance) {
    (Some(item_schema), Array(values)) =>
      for index, value in values {
        validate_instance(
          item_schema,
          root,
          value,
          path + "[" + index.to_string() + "]",
          depth + 1,
          options,
          errors,
        )
      }
    _ => ()
  }
}

///|
fn schema_matches(
  schema : Json,
  root : Json,
  instance : Json,
  path : String,
  depth : Int,
  options : CompileOptions,
) -> Bool {
  let branch_errors : Array[String] = []
  validate_instance(schema, root, instance, path, depth, options, branch_errors)
  branch_errors.is_empty()
}
