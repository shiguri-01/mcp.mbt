///|
/// A compiled, bounded JSON Schema 2020-12 validator used at tool boundaries.
///
/// Schemas remain JSON on the public API. Compilation rejects unsupported
/// dialects and remote references; validation supports the validation keywords
/// used by MCP tool schemas without performing network access.
priv struct CompiledJsonSchema {
  schema : Json
}

///|
fn json_schema_error(path : String, message : String) -> String {
  if path == "$" {
    message
  } else {
    "\{path}: \{message}"
  }
}

///|
fn schema_number(
  fields : Map[String, Json],
  key : String,
) -> Double? raise McpError {
  match fields.get(key) {
    None => None
    Some(Number(value, ..)) => Some(value)
    Some(_) => raise InvalidParams("JSON Schema \{key} must be a number")
  }
}

///|
fn schema_int(fields : Map[String, Json], key : String) -> Int? raise McpError {
  match schema_number(fields, key) {
    None => None
    Some(value) => {
      if value < 0.0 || value != value.floor() || value > 2147483647.0 {
        raise InvalidParams("JSON Schema \{key} must be a non-negative integer")
      }
      Some(value.to_int())
    }
  }
}

///|
fn validate_schema_shape(
  schema : Json,
  depth : Int,
  count : Ref[Int],
) -> Unit raise McpError {
  if depth > 64 {
    raise InvalidParams("JSON Schema nesting exceeds 64 levels")
  }
  count.val += 1
  if count.val > 4096 {
    raise InvalidParams("JSON Schema exceeds 4096 subschemas")
  }
  match schema {
    True | False => ()
    Object(fields) => {
      match fields.get("$schema") {
        None => ()
        Some(String("https://json-schema.org/draft/2020-12/schema"))
        | Some(String("https://json-schema.org/draft/2020-12/schema#")) => ()
        Some(String(dialect)) =>
          raise InvalidParams("unsupported JSON Schema dialect: \{dialect}")
        Some(_) => raise InvalidParams("JSON Schema $schema must be a string")
      }
      match fields.get("$ref") {
        None => ()
        Some(String(reference)) =>
          if !reference.has_prefix("#") {
            raise InvalidParams("remote JSON Schema $ref is disabled")
          }
        Some(_) => raise InvalidParams("JSON Schema $ref must be a string")
      }
      ignore(schema_int(fields, "minLength"))
      ignore(schema_int(fields, "maxLength"))
      ignore(schema_int(fields, "minItems"))
      ignore(schema_int(fields, "maxItems"))
      ignore(schema_int(fields, "minProperties"))
      ignore(schema_int(fields, "maxProperties"))
      ignore(schema_number(fields, "minimum"))
      ignore(schema_number(fields, "maximum"))
      ignore(schema_number(fields, "exclusiveMinimum"))
      ignore(schema_number(fields, "exclusiveMaximum"))
      ignore(schema_number(fields, "multipleOf"))
      for
        key in ["properties", "$defs", "dependentSchemas", "patternProperties"] {
        match fields.get(key) {
          None => ()
          Some(Object(children)) =>
            for _, child in children {
              validate_schema_shape(child, depth + 1, count)
            }
          Some(_) => raise InvalidParams("JSON Schema \{key} must be an object")
        }
      }
      for
        key in [
          "items", "contains", "additionalProperties", "propertyNames", "not", "if",
          "then", "else",
        ] {
        match fields.get(key) {
          None => ()
          Some(child) => validate_schema_shape(child, depth + 1, count)
        }
      }
      for key in ["allOf", "anyOf", "oneOf", "prefixItems"] {
        match fields.get(key) {
          None => ()
          Some(Array(children)) =>
            for child in children {
              validate_schema_shape(child, depth + 1, count)
            }
          Some(_) => raise InvalidParams("JSON Schema \{key} must be an array")
        }
      }
      match fields.get("required") {
        None => ()
        Some(Array(values)) =>
          for value in values {
            if !(value is String(_)) {
              raise InvalidParams(
                "JSON Schema required entries must be strings",
              )
            }
          }
        Some(_) => raise InvalidParams("JSON Schema required must be an array")
      }
    }
    _ => raise InvalidParams("JSON Schema must be an object or boolean")
  }
}

///|
fn compile_json_schema(schema : Json) -> CompiledJsonSchema raise McpError {
  let count = Ref(0)
  validate_schema_shape(schema, 0, count)
  { schema, }
}

///|
fn decode_pointer_segment(segment : String) -> String {
  segment.replace(old="~1", new="/").replace(old="~0", new="~")
}

///|
fn resolve_local_ref(root : Json, reference : String) -> Json? {
  if reference == "#" {
    return Some(root)
  }
  guard reference.has_prefix("#/") else { return None }
  let mut current = root
  for raw in reference[2:].split("/") {
    let key = decode_pointer_segment(raw.to_owned())
    match current {
      Object(fields) =>
        match fields.get(key) {
          Some(value) => current = value
          None => return None
        }
      _ => return None
    }
  }
  Some(current)
}

///|
fn schema_type_matches(expected : String, value : Json) -> Bool {
  match expected {
    "null" => value is Null
    "boolean" => value is True || value is False
    "object" => value is Object(_)
    "array" => value is Array(_)
    "string" => value is String(_)
    "number" => value is Number(_)
    "integer" => value is Number(number, ..) && number == number.floor()
    _ => false
  }
}

///|
fn validate_json_schema(
  schema : Json,
  root : Json,
  value : Json,
  path : String,
  depth : Int,
) -> String? {
  if depth > 128 {
    return Some(json_schema_error(path, "validation depth exceeded"))
  }
  match schema {
    True => None
    False => Some(json_schema_error(path, "value is rejected by false schema"))
    Object(fields) => {
      if fields.get("$ref") is Some(String(reference)) {
        return match resolve_local_ref(root, reference) {
          Some(target) =>
            validate_json_schema(target, root, value, path, depth + 1)
          None =>
            Some(json_schema_error(path, "unresolved local $ref \{reference}"))
        }
      }
      if fields.get("enum") is Some(Array(values)) && !values.contains(value) {
        return Some(json_schema_error(path, "value is not in enum"))
      }
      if fields.get("const") is Some(expected) && expected != value {
        return Some(json_schema_error(path, "value does not equal const"))
      }
      match fields.get("type") {
        Some(String(expected)) =>
          if !schema_type_matches(expected, value) {
            return Some(json_schema_error(path, "expected type \{expected}"))
          }
        Some(Array(types)) => {
          let accepted = types.any(fn(item) {
            item is String(expected) && schema_type_matches(expected, value)
          })
          if !accepted {
            return Some(
              json_schema_error(path, "value does not match any declared type"),
            )
          }
        }
        _ => ()
      }
      for keyword in ["allOf"] {
        if fields.get(keyword) is Some(Array(children)) {
          for child in children {
            if validate_json_schema(child, root, value, path, depth + 1)
              is Some(error) {
              return Some(error)
            }
          }
        }
      }
      if fields.get("anyOf") is Some(Array(children)) &&
        !children.any(fn(child) {
          validate_json_schema(child, root, value, path, depth + 1) is None
        }) {
        return Some(json_schema_error(path, "value does not match anyOf"))
      }
      if fields.get("oneOf") is Some(Array(children)) {
        let mut matches = 0
        for child in children {
          if validate_json_schema(child, root, value, path, depth + 1) is None {
            matches += 1
          }
        }
        if matches != 1 {
          return Some(
            json_schema_error(path, "value must match exactly one oneOf schema"),
          )
        }
      }
      if fields.get("not") is Some(child) &&
        validate_json_schema(child, root, value, path, depth + 1) is None {
        return Some(
          json_schema_error(path, "value matches forbidden not schema"),
        )
      }
      if fields.get("if") is Some(condition) {
        let branch = if validate_json_schema(
            condition,
            root,
            value,
            path,
            depth + 1,
          )
          is None {
          fields.get("then")
        } else {
          fields.get("else")
        }
        if branch is Some(child) {
          if validate_json_schema(child, root, value, path, depth + 1)
            is Some(error) {
            return Some(error)
          }
        }
      }
      match value {
        Object(object) => {
          if fields.get("required") is Some(Array(required)) {
            for item in required {
              if item is String(key) && !object.contains(key) {
                return Some(
                  json_schema_error(path, "required property \{key} is missing"),
                )
              }
            }
          }
          if fields.get("minProperties") is Some(Number(minimum, ..)) &&
            object.length() < minimum.to_int() {
            return Some(
              json_schema_error(path, "object has too few properties"),
            )
          }
          if fields.get("maxProperties") is Some(Number(maximum, ..)) &&
            object.length() > maximum.to_int() {
            return Some(
              json_schema_error(path, "object has too many properties"),
            )
          }
          let properties = match fields.get("properties") {
            Some(Object(items)) => Some(items)
            _ => None
          }
          if properties is Some(items) {
            for key, child in items {
              if object.get(key) is Some(child_value) {
                if validate_json_schema(
                    child,
                    root,
                    child_value,
                    "\{path}.\{key}",
                    depth + 1,
                  )
                  is Some(error) {
                  return Some(error)
                }
              }
            }
          }
          if fields.get("additionalProperties") is Some(False) {
            for key, _ in object {
              if properties is None || !properties.unwrap().contains(key) {
                return Some(
                  json_schema_error(
                    path,
                    "additional property \{key} is not allowed",
                  ),
                )
              }
            }
          } else if fields.get("additionalProperties") is Some(child) &&
            !(child is True) {
            for key, child_value in object {
              if properties is None || !properties.unwrap().contains(key) {
                if validate_json_schema(
                    child,
                    root,
                    child_value,
                    "\{path}.\{key}",
                    depth + 1,
                  )
                  is Some(error) {
                  return Some(error)
                }
              }
            }
          }
        }
        Array(values) => {
          if fields.get("minItems") is Some(Number(minimum, ..)) &&
            values.length() < minimum.to_int() {
            return Some(json_schema_error(path, "array has too few items"))
          }
          if fields.get("maxItems") is Some(Number(maximum, ..)) &&
            values.length() > maximum.to_int() {
            return Some(json_schema_error(path, "array has too many items"))
          }
          if fields.get("uniqueItems") is Some(True) {
            for index, item in values {
              for previous = 0; previous < index; previous = previous + 1 {
                if values[previous] == item {
                  return Some(
                    json_schema_error(path, "array items are not unique"),
                  )
                }
              }
            }
          }
          if fields.get("items") is Some(child) {
            for index, item in values {
              if validate_json_schema(
                  child,
                  root,
                  item,
                  "\{path}[\{index}]",
                  depth + 1,
                )
                is Some(error) {
                return Some(error)
              }
            }
          }
        }
        String(text) => {
          let length = text.char_length()
          if fields.get("minLength") is Some(Number(minimum, ..)) &&
            length < minimum.to_int() {
            return Some(
              json_schema_error(path, "string is shorter than minLength"),
            )
          }
          if fields.get("maxLength") is Some(Number(maximum, ..)) &&
            length > maximum.to_int() {
            return Some(
              json_schema_error(path, "string is longer than maxLength"),
            )
          }
          if fields.get("pattern") is Some(String(pattern)) {
            let regex = Regex(pattern) catch {
              _ =>
                return Some(
                  json_schema_error(path, "invalid pattern in schema"),
                )
            }
            if regex.execute(text) is None {
              return Some(
                json_schema_error(path, "string does not match pattern"),
              )
            }
          }
        }
        Number(number, ..) => {
          if fields.get("minimum") is Some(Number(minimum, ..)) &&
            number < minimum {
            return Some(json_schema_error(path, "number is below minimum"))
          }
          if fields.get("maximum") is Some(Number(maximum, ..)) &&
            number > maximum {
            return Some(json_schema_error(path, "number is above maximum"))
          }
          if fields.get("exclusiveMinimum") is Some(Number(minimum, ..)) &&
            number <= minimum {
            return Some(
              json_schema_error(path, "number is not above exclusiveMinimum"),
            )
          }
          if fields.get("exclusiveMaximum") is Some(Number(maximum, ..)) &&
            number >= maximum {
            return Some(
              json_schema_error(path, "number is not below exclusiveMaximum"),
            )
          }
          if fields.get("multipleOf") is Some(Number(divisor, ..)) &&
            (divisor <= 0.0 || number / divisor != (number / divisor).floor()) {
            return Some(
              json_schema_error(path, "number is not a multipleOf value"),
            )
          }
        }
        _ => ()
      }
      None
    }
    _ => Some(json_schema_error(path, "invalid JSON Schema"))
  }
}

///|
fn CompiledJsonSchema::validate(
  self : CompiledJsonSchema,
  value : Json,
) -> String? {
  validate_json_schema(self.schema, self.schema, value, "$", 0)
}
