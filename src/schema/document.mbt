///|
/// An individual issue found during JSON Schema validation.
pub struct ValidationIssue {
  path : @json.JsonPath
  message : String
} derive(Debug, Eq)

///|
pub fn ValidationIssue::ValidationIssue(
  path : @json.JsonPath,
  message : String,
) -> ValidationIssue {
  { path, message }
}

///|
pub impl Show for ValidationIssue with fn output(
  self : ValidationIssue,
  logger : &Logger,
) -> Unit {
  logger.write_string("\{self.path}: \{self.message}")
}

///|
pub impl ToJson for ValidationIssue with fn to_json(self : ValidationIssue) -> Json {
  Json::object({
    "path": Json::string(self.path.to_string()),
    "message": Json::string(self.message),
  })
}

///|
/// Validation failure holding one or more validation issues.
pub suberror ValidationIssues {
  ValidationIssues(Array[ValidationIssue])
} derive(Debug, Eq)

///|
pub impl Show for ValidationIssues with fn output(
  self : ValidationIssues,
  logger : &Logger,
) -> Unit {
  match self {
    ValidationIssues(issues) =>
      for i, issue in issues {
        if i > 0 {
          logger.write_string("\n")
        }
        logger.write_string(issue.to_string())
      }
  }
}

///|
pub impl ToJson for ValidationIssues with fn to_json(self : ValidationIssues) -> Json {
  match self {
    ValidationIssues(issues) => issues.map(fn(i) { i.to_json() }).to_json()
  }
}

///|
priv struct ValidationContext {
  defs : Map[String, Schema]
  max_depth : Int
  issues : Array[ValidationIssue]
}

///|
fn ValidationContext::push_issue(
  self : ValidationContext,
  path : @json.JsonPath,
  message : String,
) -> Unit {
  self.issues.push(ValidationIssue(path, message))
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
fn validate_document_syntax(value : Json) -> Unit raise SchemaError {
  if value is (True | False) {
    return
  }
  guard value is Object(fields) else {
    raise InvalidDocument("a JSON Schema document must be an object or boolean")
  }
  match fields.get("$schema") {
    Some(String(dialect)) if dialect == DRAFT_2020_12 => ()
    Some(String(dialect)) => raise UnsupportedDialect(dialect)
    Some(_) => raise InvalidDocument("$schema must be a string")
    None => ()
  }
  if fields.get("$id") is Some(id) && !(id is String(_)) {
    raise InvalidDocument("$id must be a string")
  }
  if fields.get("$ref") is Some(reference) && !(reference is String(_)) {
    raise InvalidDocument("$ref must be a string")
  }
  validate_references(value, 0, 128)
}

///|
fn validate_document_compilation(
  value : Json,
  max_depth : Int,
  max_nodes : Int,
) -> Unit raise SchemaError {
  validate_document_syntax(value)
  let nodes = count_schema_nodes(value, 0, max_depth)
  if nodes > max_nodes {
    raise InvalidSchema("schema exceeds max_nodes")
  }
  validate_references(value, 0, max_depth)
  validate_supported_keywords(value, 0, max_depth)
  validate_keyword_shapes(value, 0, max_depth)
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
    True => Schema::from_node(BooleanSchema::always())
    False => Schema::from_node(BooleanSchema::never())
    Object(fields) => {
      if fields is { "$ref": String(reference), .. } {
        return Schema::from_node(RefSchema(reference))
      }
      if fields is { "const": val, .. } {
        return Schema::from_node(ConstSchema::from_value(val))
      }
      if fields is { "enum": Array(values), .. } {
        return Schema::from_node(EnumSchema(values))
      }
      if fields is { "allOf": Array(values), .. } {
        let schemas = []
        for v in values {
          schemas.push(parse_schema_json(v))
        }
        return Schema::from_node(AllOfSchema(schemas))
      }
      if fields is { "anyOf": Array(values), .. } {
        let schemas = []
        for v in values {
          schemas.push(parse_schema_json(v))
        }
        return Schema::from_node(AnyOfSchema(schemas))
      }
      if fields is { "oneOf": Array(values), .. } {
        let schemas = []
        for v in values {
          schemas.push(parse_schema_json(v))
        }
        return Schema::from_node(OneOfSchema(schemas))
      }
      if fields is { "not": v, .. } {
        return Schema::from_node(NotSchema(parse_schema_json(v)))
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
        Some("null") => Schema::from_node(NullSchema(description?=desc))
        Some("boolean") => Schema::from_node(BoolTypeSchema(description?=desc))
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
          Schema::from_node(
            StringSchema(min_length?, max_length?, description?=desc),
          )
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
          Schema::from_node(
            IntegerSchema(minimum?=min, maximum?=max, description?=desc),
          )
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
          Schema::from_node(
            NumberSchema(
              minimum?=min,
              maximum?=max,
              exclusive_minimum?=ex_min,
              exclusive_maximum?=ex_max,
              multiple_of?=mult,
              description?=desc,
            ),
          )
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
          Schema::from_node(
            ArraySchema(
              items?,
              min_items?=min,
              max_items?=max,
              unique_items=unique,
              description?=desc,
            ),
          )
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
            Schema::from_node(
              ObjectSchema(
                properties~,
                required~,
                additional_properties=add_props,
                min_properties?=min,
                max_properties?=max,
                description?=desc,
              ),
            )
          } else {
            Schema::from_node(BooleanSchema::always())
          }
        }
        _ => Schema::from_node(RawSchema(value))
      }
    }
    _ => raise InvalidDocument("schema must be an object or boolean")
  }
}
