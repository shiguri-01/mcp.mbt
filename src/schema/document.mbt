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
pub fn Document::new(value : Json) -> Document raise SchemaError {
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
  { value, dialect }
}

///|
pub struct CompileOptions {
  max_depth : Int
  max_nodes : Int
} derive(Debug, Eq)

///|
pub fn CompileOptions::new(
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
  { max_depth: 128, max_nodes: 10000 }
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
  validate_instance(self.document.value, instance, "$", 0, self.options, errors)
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
fn validate_instance(
  schema : Json,
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
  match schema {
    True => return
    False => {
      add_error(errors, path, "boolean schema is false")
      return
    }
    _ => ()
  }
  guard schema is Object(fields) else { return }
  match fields.get("type") {
    Some(String(type_name)) if !type_matches(type_name, instance) =>
      add_error(errors, path, "value does not match type {type_name}")
    _ => ()
  }
  match fields.get("enum") {
    Some(Array(values)) if !values.contains(instance) =>
      add_error(errors, path, "value is not in enum")
    _ => ()
  }
  match (fields.get("properties"), instance) {
    (Some(Object(properties)), Object(instance_fields)) =>
      for name, property_schema in properties {
        match instance_fields.get(name) {
          Some(property) =>
            validate_instance(
              property_schema,
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
            add_error(errors, path, "required property is missing: {name}")
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
          add_error(errors, path, "additional property is not allowed: {name}")
        }
      }
    _ => ()
  }
  match (fields.get("items"), instance) {
    (Some(item_schema), Array(values)) =>
      for index, value in values {
        validate_instance(
          item_schema,
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
