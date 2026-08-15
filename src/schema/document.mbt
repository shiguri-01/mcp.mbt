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
    Some(String(value)) if value == draft_2020_12 => value
    Some(String(value)) => raise UnsupportedDialect(value)
    Some(_) => raise InvalidDocument("$schema must be a string")
    None => draft_2020_12
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
  root : Schema
  defs : Map[String, Schema]
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
  let defs : Map[String, Schema] = Map([])
  collect_definitions(self.value, defs, "#", 0, options.max_depth)
  let root = parse_schema_json(self.value)
  { document: self, options, root, defs }
}

///|
/// A validation failure describing the path in the JSON instance and the reason.
pub struct ValidationError {
  path : @json.JsonPath
  message : String
} derive(Debug, Eq)

///|
pub fn ValidationError::ValidationError(
  path : @json.JsonPath,
  message : String,
) -> ValidationError {
  { path, message }
}

///|
pub impl Show for ValidationError with fn output(
  self : ValidationError,
  logger : &Logger,
) -> Unit {
  logger.write_string("\{self.path}: \{self.message}")
}

///|
pub impl ToJson for ValidationError with fn to_json(self : ValidationError) -> Json {
  Json::object({
    "path": Json::string(self.path.to_string()),
    "message": Json::string(self.message),
  })
}

///|
pub struct ValidationResult {
  valid : Bool
  errors : Array[ValidationError]
} derive(Debug, Eq)

///|
pub struct ValidationContext {
  defs : Map[String, Schema]
  options : CompileOptions
  errors : Array[ValidationError]
}

///|
pub fn ValidationContext::push_error(
  self : ValidationContext,
  path : @json.JsonPath,
  message : String,
) -> Unit {
  self.errors.push(ValidationError(path, message))
}

///|
priv struct PathWitness {
  path : @json.JsonPath
}

///|
impl @json.FromJson for PathWitness with fn from_json(
  _json : Json,
  path : @json.JsonPath,
) -> PathWitness {
  { path, }
}

///|
fn root_json_path() -> @json.JsonPath {
  let witness : PathWitness = try! @json.from_json(Json::null())
  witness.path
}

///|
pub fn CompiledSchema::validate(
  self : CompiledSchema,
  instance : Json,
) -> ValidationResult {
  let ctx : ValidationContext = {
    defs: self.defs,
    options: self.options,
    errors: [],
  }
  self.root.validate(instance, path=root_json_path(), depth=0, ctx~)
  { valid: ctx.errors.is_empty(), errors: ctx.errors }
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
fn collect_definitions(
  value : Json,
  defs : Map[String, Schema],
  pointer : String,
  depth : Int,
  max_depth : Int,
) -> Unit raise SchemaError {
  if depth > max_depth {
    raise InvalidSchema("schema exceeds max_depth")
  }
  defs[pointer] = parse_schema_json(value)
  if value is Object(fields) {
    for k, v in fields {
      let encoded = k
        .replace_all(old="~", new="~0")
        .replace_all(old="/", new="~1")
      let child_pointer = if pointer == "#" {
        "#/" + encoded
      } else {
        pointer + "/" + encoded
      }
      if v is (Object(_) | True | False) {
        collect_definitions(v, defs, child_pointer, depth + 1, max_depth)
      }
    }
  }
}

///|

///|
fn parse_schema_json(value : Json) -> Schema raise SchemaError {
  match value {
    True => BooleanSchema::always().into_schema()
    False => BooleanSchema::never().into_schema()
    Object(fields) => {
      if fields is { "$ref": String(reference), .. } {
        return RefSchema(reference).into_schema()
      }
      if fields is { "const": val, .. } {
        return ConstSchema(val).into_schema()
      }
      if fields is { "enum": Array(values), .. } {
        return EnumSchema(values).into_schema()
      }
      if fields is { "allOf": Array(values), .. } {
        let schemas = []
        for v in values {
          schemas.push(parse_schema_json(v))
        }
        return AllOfSchema(schemas).into_schema()
      }
      if fields is { "anyOf": Array(values), .. } {
        let schemas = []
        for v in values {
          schemas.push(parse_schema_json(v))
        }
        return AnyOfSchema(schemas).into_schema()
      }
      if fields is { "oneOf": Array(values), .. } {
        let schemas = []
        for v in values {
          schemas.push(parse_schema_json(v))
        }
        return OneOfSchema(schemas).into_schema()
      }
      if fields is { "not": v, .. } {
        return NotSchema(parse_schema_json(v)).into_schema()
      }
      let desc = if fields is { "description": String(d), .. } {
        Some(d)
      } else {
        None
      }
      let type_name = if fields is { "type": String(t), .. } {
        Some(t)
      } else {
        None
      }
      match type_name {
        Some("null") => NullSchema(description?=desc).into_schema()
        Some("boolean") => BoolTypeSchema(description?=desc).into_schema()
        Some("string") => {
          let min_length = if fields is { "minLength": Number(n, ..), .. } {
            Some(n.to_int())
          } else {
            None
          }
          let max_length = if fields is { "maxLength": Number(n, ..), .. } {
            Some(n.to_int())
          } else {
            None
          }
          StringSchema(min_length?, max_length?, description?=desc).into_schema()
        }
        Some("integer") => {
          let min = if fields is { "minimum": Number(n, ..), .. } {
            Some(n.to_int())
          } else {
            None
          }
          let max = if fields is { "maximum": Number(n, ..), .. } {
            Some(n.to_int())
          } else {
            None
          }
          IntegerSchema(minimum?=min, maximum?=max, description?=desc).into_schema()
        }
        Some("number") => {
          let min = if fields is { "minimum": Number(n, ..), .. } {
            Some(n)
          } else {
            None
          }
          let max = if fields is { "maximum": Number(n, ..), .. } {
            Some(n)
          } else {
            None
          }
          let ex_min = if fields is { "exclusiveMinimum": Number(n, ..), .. } {
            Some(n)
          } else {
            None
          }
          let ex_max = if fields is { "exclusiveMaximum": Number(n, ..), .. } {
            Some(n)
          } else {
            None
          }
          let mult = if fields is { "multipleOf": Number(n, ..), .. } {
            Some(n)
          } else {
            None
          }
          NumberSchema(
            minimum?=min,
            maximum?=max,
            exclusive_minimum?=ex_min,
            exclusive_maximum?=ex_max,
            multiple_of?=mult,
            description?=desc,
          ).into_schema()
        }
        Some("array") => {
          let items = if fields is { "items": item_json, .. } {
            Some(parse_schema_json(item_json))
          } else {
            None
          }
          let min = if fields is { "minItems": Number(n, ..), .. } {
            Some(n.to_int())
          } else {
            None
          }
          let max = if fields is { "maxItems": Number(n, ..), .. } {
            Some(n.to_int())
          } else {
            None
          }
          let unique = fields is { "uniqueItems": True, .. }
          ArraySchema(
            items?,
            min_items?=min,
            max_items?=max,
            unique_items=unique,
            description?=desc,
          ).into_schema()
        }
        Some("object") | None => {
          let properties : Map[String, Schema] = Map([])
          if fields is { "properties": Object(props), .. } {
            for k, v in props {
              properties[k] = parse_schema_json(v)
            }
          }
          let required : Array[String] = []
          if fields is { "required": Array(reqs), .. } {
            for r in reqs {
              if r is String(s) {
                required.push(s)
              }
            }
          }
          let add_props = !(fields is { "additionalProperties": False, .. })
          let min = if fields is { "minProperties": Number(n, ..), .. } {
            Some(n.to_int())
          } else {
            None
          }
          let max = if fields is { "maxProperties": Number(n, ..), .. } {
            Some(n.to_int())
          } else {
            None
          }
          if type_name == Some("object") ||
            !properties.is_empty() ||
            !required.is_empty() ||
            !add_props ||
            min is Some(_) ||
            max is Some(_) {
            ObjectSchema(
              properties~,
              required~,
              additional_properties=add_props,
              min_properties?=min,
              max_properties?=max,
              description?=desc,
            ).into_schema()
          } else {
            BooleanSchema::always().into_schema()
          }
        }
        _ => RawSchema(value).into_schema()
      }
    }
    _ => raise InvalidDocument("schema must be an object or boolean")
  }
}
