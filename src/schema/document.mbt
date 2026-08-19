///|
/// An individual issue found during JSON Schema validation.
pub struct ValidationIssue {
  path : @json.JsonPath
  message : String
} derive(Debug, Eq)

///|
pub fn ValidationIssue::ValidationIssue(
  path~ : @json.JsonPath,
  message~ : String,
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
  self.issues.push(ValidationIssue(path~, message~))
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
  validate_references(value, depth=0, max_depth=128)
}

///|
fn validate_document_compilation(
  value : Json,
  max_depth~ : Int,
  max_nodes~ : Int,
) -> Unit raise SchemaError {
  validate_document_syntax(value)
  let nodes = count_schema_nodes(value, depth=0, max_depth~)
  guard nodes <= max_nodes else {
    raise InvalidSchema("schema exceeds max_nodes")
  }
  validate_references(value, depth=0, max_depth~)
  validate_supported_keywords(value, depth=0, max_depth~)
  validate_keyword_shapes(value, depth=0, max_depth~)
}

///|
fn count_schema_nodes(
  value : Json,
  depth~ : Int,
  max_depth~ : Int,
) -> Int raise SchemaError {
  guard depth <= max_depth else {
    raise InvalidSchema("schema exceeds max_depth")
  }
  match value {
    Object(fields) =>
      fields
      .values()
      .fold(init=1, (acc, child) => {
        acc + count_schema_nodes(child, depth=depth + 1, max_depth~)
      })
    Array(values) =>
      values.fold(init=1, (acc, child) => {
        acc + count_schema_nodes(child, depth=depth + 1, max_depth~)
      })
    _ => 1
  }
}

///|
fn validate_references(
  value : Json,
  depth~ : Int,
  max_depth~ : Int,
) -> Unit raise SchemaError {
  guard depth <= max_depth else {
    raise InvalidSchema("schema exceeds max_depth")
  }
  guard value is Object(fields) else { return }
  for ref_key in ["$ref", "$dynamicRef"] {
    guard fields.get(ref_key) is Some(ref_val) else { continue }
    guard ref_val is String(reference) else {
      raise InvalidSchema("JSON Schema \{ref_key} must be a string")
    }
    guard reference.has_prefix("#") else {
      raise InvalidSchema("network JSON Schema references are disabled")
    }
  }
  for child in schema_children(fields) {
    validate_references(child, depth=depth + 1, max_depth~)
  }
}

///|
/// The portable validator rejects keywords it cannot evaluate instead of
/// silently accepting instances that were never checked.
fn validate_supported_keywords(
  value : Json,
  depth~ : Int,
  max_depth~ : Int,
) -> Unit raise SchemaError {
  guard depth <= max_depth else {
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
        validate_supported_keywords(child, depth=depth + 1, max_depth~)
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
  depth~ : Int,
  max_depth~ : Int,
) -> Unit raise SchemaError {
  guard depth <= max_depth else {
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
          Some(_) => raise InvalidSchema("\{keyword} must be a finite number")
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
            raise InvalidSchema("\{keyword} must be a non-negative integer")
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
            raise InvalidSchema("\{keyword} must be a non-negative integer")
          None => ()
        }
      }
      for keyword in ["allOf", "anyOf", "oneOf"] {
        match fields.get(keyword) {
          Some(Array(values)) if keyword == "allOf" || !values.is_empty() => ()
          Some(Array(_)) => raise InvalidSchema("\{keyword} must not be empty")
          Some(_) => raise InvalidSchema("\{keyword} must be an array")
          None => ()
        }
      }
      match fields.get("required") {
        Some(Array(names)) => {
          let seen : Map[String, Bool] = Map([])
          for name in names {
            guard name is String(name_str) else {
              raise InvalidSchema("required names must be strings")
            }
            guard !seen.contains(name_str) else {
              raise InvalidSchema("required property names must be unique")
            }
            seen[name_str] = true
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
        validate_keyword_shapes(child, depth=depth + 1, max_depth~)
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
    guard fields.get(key) is Some(Object(fields)) else { continue }
    for _, child in fields {
      children.push(child)
    }
  }
  for key in ["allOf", "anyOf", "oneOf"] {
    guard fields.get(key) is Some(Array(values)) else { continue }
    for child in values {
      children.push(child)
    }
  }
  for
    key in [
      "not", "items", "contains", "propertyNames", "if", "then", "else", "unevaluatedItems",
      "unevaluatedProperties",
    ] {
    guard fields.get(key) is Some(child) && child is (Object(_) | True | False) else {
      continue
    }
    children.push(child)
  }
  children
}

///|
fn collect_definitions(
  value : Json,
  defs~ : Map[String, Schema],
  pointer~ : String,
  depth~ : Int,
  max_depth~ : Int,
) -> Unit raise SchemaError {
  guard depth <= max_depth else {
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
        collect_definitions(
          v,
          defs~,
          pointer=child_pointer,
          depth=depth + 1,
          max_depth~,
        )
      }
    }
  }
}

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
        let schemas = values.map_raise(parse_schema_json)
        return Schema::from_node(AllOfSchema(schemas))
      }
      if fields is { "anyOf": Array(values), .. } {
        let schemas = values.map_raise(parse_schema_json)
        return Schema::from_node(AnyOfSchema(schemas))
      }
      if fields is { "oneOf": Array(values), .. } {
        let schemas = values.map_raise(parse_schema_json)
        return Schema::from_node(OneOfSchema(schemas))
      }
      if fields is { "not": v, .. } {
        return Schema::from_node(NotSchema(parse_schema_json(v)))
      }
      let desc = fields.get_string("description")
      let type_name = fields.get_string("type")
      match type_name {
        Some("null") => Schema::from_node(NullSchema(description?=desc))
        Some("boolean") => Schema::from_node(BoolTypeSchema(description?=desc))
        Some("string") => {
          let min_length = fields.get_number("minLength").map(n => n.to_int())
          let max_length = fields.get_number("maxLength").map(n => n.to_int())
          Schema::from_node(
            StringSchema(min_length?, max_length?, description?=desc),
          )
        }
        Some("integer") => {
          let min = fields.get_number("minimum").map(n => n.to_int())
          let max = fields.get_number("maximum").map(n => n.to_int())
          Schema::from_node(
            IntegerSchema(minimum?=min, maximum?=max, description?=desc),
          )
        }
        Some("number") => {
          let min = fields.get_number("minimum")
          let max = fields.get_number("maximum")
          let ex_min = fields.get_number("exclusiveMinimum")
          let ex_max = fields.get_number("exclusiveMaximum")
          let mult = fields.get_number("multipleOf")
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
          let items = fields.get("items").map(parse_schema_json)
          let min = fields.get_number("minItems").map(n => n.to_int())
          let max = fields.get_number("maxItems").map(n => n.to_int())
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
        Some("object") => {
          let properties : Map[String, Schema] = if fields
            is { "properties": Object(props), .. } {
            props.map_raise((_, v) => parse_schema_json(v))
          } else {
            Map([])
          }
          let required : Array[String] = if fields
            is { "required": Array(reqs), .. } {
            reqs.filter_map(r => if r is String(s) { Some(s) } else { None })
          } else {
            []
          }
          let add_props = !(fields is { "additionalProperties": False, .. })
          let min = fields.get_number("minProperties").map(n => n.to_int())
          let max = fields.get_number("maxProperties").map(n => n.to_int())
          if !properties.is_empty() ||
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
        None => Schema::from_node(BooleanSchema::always())
        _ => Schema::from_node(RawSchema(value))
      }
    }
    _ => raise InvalidDocument("schema must be an object or boolean")
  }
}
