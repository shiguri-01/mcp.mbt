///|
/// A compiled, bounded JSON Schema validator used at tool boundaries.
///
/// Schemas remain JSON on the public API. Compilation rejects unsupported
/// dialects and remote references; validation supports the validation keywords
/// used by MCP tool schemas without performing network access.
priv struct CompiledJsonSchema {
  schema : Json
  root_resource : String
  resources : Map[String, Json]
  anchors : Map[String, Json]
  dynamic_anchors : Map[String, Json]
}

///|
priv struct JsonSchemaEvalContext {
  compiled : CompiledJsonSchema
  resource : String
  dynamic_scope : Array[String]
}

///|
priv struct ResolvedSchemaReference {
  schema : Json
  resource : String
  dynamic_anchor : String?
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
fn validate_schema_type_keyword(
  fields : Map[String, Json],
) -> Unit raise McpError {
  let allowed = [
    "null", "boolean", "object", "array", "number", "string", "integer",
  ]
  match fields.get("type") {
    None => ()
    Some(String(value)) =>
      if !allowed.contains(value) {
        raise InvalidParams("JSON Schema type is not recognized: \{value}")
      }
    Some(Array(values)) => {
      if values.is_empty() {
        raise InvalidParams("JSON Schema type array must not be empty")
      }
      let seen : Map[String, Bool] = Map([])
      for value in values {
        guard value is String(name) && allowed.contains(name) else {
          raise InvalidParams(
            "JSON Schema type entries must be recognized strings",
          )
        }
        if seen.contains(name) {
          raise InvalidParams("JSON Schema type entries must be unique")
        }
        seen[name] = true
      }
    }
    Some(_) => raise InvalidParams("JSON Schema type must be a string or array")
  }
}

///|
fn validate_unique_strings(
  values : Array[Json],
  keyword : String,
) -> Unit raise McpError {
  let seen : Map[String, Bool] = Map([])
  for value in values {
    guard value is String(name) else {
      raise InvalidParams("JSON Schema \{keyword} entries must be strings")
    }
    if seen.contains(name) {
      raise InvalidParams("JSON Schema \{keyword} entries must be unique")
    }
    seen[name] = true
  }
}

///|
fn valid_schema_anchor(value : String) -> Bool {
  let chars = value.to_array()
  guard chars is [first, .. rest] &&
    (first is ('A'..='Z') || first is ('a'..='z') || first == '_') else {
    return false
  }
  rest.all(fn(char) {
    char is ('A'..='Z') ||
    char is ('a'..='z') ||
    char is ('0'..='9') ||
    char == '-' ||
    char == '_' ||
    char == '.'
  })
}

///|
fn validate_schema_shape(
  schema : Json,
  depth : Int,
  count : Ref[Int],
  draft7 : Bool,
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
      validate_schema_type_keyword(fields)
      match fields.get("$schema") {
        None => ()
        Some(String("https://json-schema.org/draft/2020-12/schema"))
        | Some(String("https://json-schema.org/draft/2020-12/schema#"))
        | Some(String("http://json-schema.org/draft-07/schema#"))
        | Some(String("https://json-schema.org/draft-07/schema#")) => ()
        Some(String(dialect)) =>
          raise InvalidParams("unsupported JSON Schema dialect: \{dialect}")
        Some(_) => raise InvalidParams("JSON Schema $schema must be a string")
      }
      match fields.get("$ref") {
        None => ()
        Some(String(_)) => ()
        Some(_) => raise InvalidParams("JSON Schema $ref must be a string")
      }
      match fields.get("$id") {
        None | Some(String(_)) => ()
        Some(_) => raise InvalidParams("JSON Schema $id must be a string")
      }
      match fields.get("$dynamicRef") {
        None => ()
        Some(String(_)) => ()
        Some(_) =>
          raise InvalidParams("JSON Schema $dynamicRef must be a string")
      }
      for keyword in ["$anchor", "$dynamicAnchor"] {
        match fields.get(keyword) {
          None => ()
          Some(String(value)) =>
            if !valid_schema_anchor(value) {
              raise InvalidParams(
                "JSON Schema \{keyword} is not a valid anchor",
              )
            }
          Some(_) =>
            raise InvalidParams("JSON Schema \{keyword} must be a string")
        }
      }
      ignore(schema_int(fields, "minLength"))
      ignore(schema_int(fields, "maxLength"))
      ignore(schema_int(fields, "minItems"))
      ignore(schema_int(fields, "maxItems"))
      ignore(schema_int(fields, "minProperties"))
      ignore(schema_int(fields, "maxProperties"))
      if !draft7 {
        ignore(schema_int(fields, "minContains"))
        ignore(schema_int(fields, "maxContains"))
      }
      ignore(schema_number(fields, "minimum"))
      ignore(schema_number(fields, "maximum"))
      ignore(schema_number(fields, "exclusiveMinimum"))
      ignore(schema_number(fields, "exclusiveMaximum"))
      ignore(schema_number(fields, "multipleOf"))
      if schema_number(fields, "multipleOf") is Some(value) && value <= 0.0 {
        raise InvalidParams("JSON Schema multipleOf must be greater than zero")
      }
      for keyword in ["uniqueItems"] {
        match fields.get(keyword) {
          None | Some(True) | Some(False) => ()
          Some(_) =>
            raise InvalidParams("JSON Schema \{keyword} must be a boolean")
        }
      }
      match fields.get("enum") {
        None => ()
        Some(Array(values)) =>
          if values.is_empty() {
            raise InvalidParams("JSON Schema enum must not be empty")
          }
        Some(_) => raise InvalidParams("JSON Schema enum must be an array")
      }
      let object_keywords = if draft7 {
        ["properties", "definitions", "patternProperties"]
      } else {
        ["properties", "$defs", "dependentSchemas", "patternProperties"]
      }
      for key in object_keywords {
        match fields.get(key) {
          None => ()
          Some(Object(children)) =>
            for name, child in children {
              if key == "patternProperties" {
                ignore(
                  Regex(name) catch {
                    _ =>
                      raise InvalidParams(
                        "JSON Schema patternProperties key is not a valid regular expression",
                      )
                  },
                )
              }
              validate_schema_shape(child, depth + 1, count, draft7)
            }
          Some(_) => raise InvalidParams("JSON Schema \{key} must be an object")
        }
      }
      let schema_keywords = if draft7 {
        [
          "contains", "additionalProperties", "additionalItems", "propertyNames",
          "not", "if", "then", "else",
        ]
      } else {
        [
          "contains", "additionalProperties", "propertyNames", "not", "if", "then",
          "else", "unevaluatedProperties", "unevaluatedItems",
        ]
      }
      for key in schema_keywords {
        match fields.get(key) {
          None => ()
          Some(child) => validate_schema_shape(child, depth + 1, count, draft7)
        }
      }
      match fields.get("items") {
        None => ()
        Some(Array(children)) => {
          if !draft7 {
            raise InvalidParams(
              "JSON Schema 2020-12 items must be a schema, not an array",
            )
          }
          for child in children {
            validate_schema_shape(child, depth + 1, count, draft7)
          }
        }
        Some(child) => validate_schema_shape(child, depth + 1, count, draft7)
      }
      let array_keywords = if draft7 {
        ["allOf", "anyOf", "oneOf"]
      } else {
        ["allOf", "anyOf", "oneOf", "prefixItems"]
      }
      for key in array_keywords {
        match fields.get(key) {
          None => ()
          Some(Array(children)) => {
            if children.is_empty() {
              raise InvalidParams("JSON Schema \{key} must not be empty")
            }
            for child in children {
              validate_schema_shape(child, depth + 1, count, draft7)
            }
          }
          Some(_) => raise InvalidParams("JSON Schema \{key} must be an array")
        }
      }
      match fields.get("required") {
        None => ()
        Some(Array(values)) => validate_unique_strings(values, "required")
        Some(_) => raise InvalidParams("JSON Schema required must be an array")
      }
      if !draft7 {
        let key = "dependentRequired"
        match fields.get(key) {
          None => ()
          Some(Object(entries)) =>
            for _, value in entries {
              guard value is Array(names) else {
                raise InvalidParams("JSON Schema \{key} values must be arrays")
              }
              validate_unique_strings(names, key)
            }
          Some(_) => raise InvalidParams("JSON Schema \{key} must be an object")
        }
      }
      if draft7 {
        match fields.get("dependencies") {
          None => ()
          Some(Object(entries)) =>
            for _, dependency in entries {
              match dependency {
                Array(names) =>
                  for name in names {
                    if !(name is String(_)) {
                      raise InvalidParams(
                        "JSON Schema dependencies entries must be strings",
                      )
                    }
                  }
                child => validate_schema_shape(child, depth + 1, count, draft7)
              }
            }
          Some(_) =>
            raise InvalidParams("JSON Schema dependencies must be an object")
        }
      }
      match fields.get("pattern") {
        Some(String(pattern)) =>
          ignore(
            Regex(pattern) catch {
              _ =>
                raise InvalidParams(
                  "JSON Schema pattern is not a valid regular expression",
                )
            },
          )
        Some(_) => raise InvalidParams("JSON Schema pattern must be a string")
        None => ()
      }
    }
    _ => raise InvalidParams("JSON Schema must be an object or boolean")
  }
}

///|
fn uri_has_scheme(uri : String) -> Bool {
  let chars = uri.to_array()
  guard chars is [first, .. rest] &&
    (first is ('A'..='Z') || first is ('a'..='z')) else {
    return false
  }
  for char in rest {
    if char == ':' {
      return true
    }
    if !(char is ('A'..='Z') ||
      char is ('a'..='z') ||
      char is ('0'..='9') ||
      char == '+' ||
      char == '-' ||
      char == '.') {
      return false
    }
  }
  false
}

///|
fn split_uri_fragment(uri : String) -> (String, String?) {
  match uri.split_once("#") {
    Some((resource, fragment)) =>
      (resource.to_owned(), Some(fragment.to_owned()))
    None => (uri, None)
  }
}

///|
fn strip_uri_query(uri : String) -> String {
  match uri.split_once("?") {
    Some((path, _)) => path.to_owned()
    None => uri
  }
}

///|
fn normalize_uri_path(path : String) -> String {
  let absolute = path.has_prefix("/")
  let trailing = path.has_suffix("/")
  let segments : Array[String] = []
  for raw in path.split("/") {
    let segment = raw.to_owned()
    if segment.is_empty() || segment == "." {
      continue
    }
    if segment == ".." {
      ignore(segments.pop())
    } else {
      segments.push(segment)
    }
  }
  let body = segments.join("/")
  let prefix = if absolute { "/" } else { "" }
  let suffix = if trailing && !body.is_empty() { "/" } else { "" }
  prefix + body + suffix
}

///|
fn resolve_schema_uri(base : String, reference : String) -> String {
  let (reference_resource, fragment) = split_uri_fragment(reference)
  let resolved_resource = if reference_resource.is_empty() {
    split_uri_fragment(base).0
  } else if uri_has_scheme(reference_resource) {
    reference_resource
  } else {
    let base_resource = strip_uri_query(split_uri_fragment(base).0)
    match base_resource.split_once("://") {
      Some((scheme, authority_and_path)) => {
        let authority_and_path = authority_and_path.to_owned()
        let (authority, base_path) = match authority_and_path.split_once("/") {
          Some((authority, path)) =>
            (authority.to_owned(), "/" + path.to_owned())
          None => (authority_and_path, "/")
        }
        let path = if reference_resource.has_prefix("/") {
          reference_resource
        } else {
          let directory = match base_path.rev_split_once("/") {
            Some((directory, _)) => directory.to_owned() + "/"
            None => "/"
          }
          directory + reference_resource
        }
        scheme.to_owned() + "://" + authority + normalize_uri_path(path)
      }
      None => reference_resource
    }
  }
  match fragment {
    Some(fragment) => resolved_resource + "#" + fragment
    None => resolved_resource
  }
}

///|
fn schema_resource_uri(
  schema : Json,
  inherited : String,
) -> String raise McpError {
  guard schema is Object(fields) else { return inherited }
  match fields.get("$id") {
    Some(String(identifier)) => {
      let (resource, fragment) = split_uri_fragment(
        resolve_schema_uri(inherited, identifier),
      )
      if fragment is Some(value) && !value.is_empty() {
        raise InvalidParams("JSON Schema $id must not contain a fragment")
      }
      resource
    }
    _ => inherited
  }
}

///|
fn schema_children(schema : Json, draft7 : Bool) -> Array[Json] {
  let children : Array[Json] = []
  guard schema is Object(fields) else { return children }
  let object_keywords = if draft7 {
    ["properties", "definitions", "patternProperties", "dependencies"]
  } else {
    ["properties", "$defs", "dependentSchemas", "patternProperties"]
  }
  for keyword in object_keywords {
    if fields.get(keyword) is Some(Object(entries)) {
      for _, child in entries {
        if child is Object(_) || child is True || child is False {
          children.push(child)
        }
      }
    }
  }
  let schema_keywords = if draft7 {
    [
      "contains", "additionalProperties", "additionalItems", "propertyNames", "not",
      "if", "then", "else",
    ]
  } else {
    [
      "contains", "additionalProperties", "propertyNames", "not", "if", "then", "else",
      "unevaluatedProperties", "unevaluatedItems", "contentSchema",
    ]
  }
  for keyword in schema_keywords {
    if fields.get(keyword) is Some(child) {
      children.push(child)
    }
  }
  match fields.get("items") {
    Some(Array(items)) =>
      for child in items {
        children.push(child)
      }
    Some(child) => children.push(child)
    None => ()
  }
  let array_keywords = if draft7 {
    ["allOf", "anyOf", "oneOf"]
  } else {
    ["allOf", "anyOf", "oneOf", "prefixItems"]
  }
  for keyword in array_keywords {
    if fields.get(keyword) is Some(Array(items)) {
      for child in items {
        children.push(child)
      }
    }
  }
  children
}

///|
fn index_schema_resources(
  schema : Json,
  inherited_resource : String,
  resources : Map[String, Json],
  anchors : Map[String, Json],
  dynamic_anchors : Map[String, Json],
  draft7 : Bool,
  depth : Int,
) -> Unit raise McpError {
  if depth > 64 {
    raise InvalidParams("JSON Schema resource nesting exceeds 64 levels")
  }
  let resource = schema_resource_uri(schema, inherited_resource)
  if resource != inherited_resource || depth == 0 {
    match resources.get(resource) {
      Some(existing) if existing != schema =>
        raise InvalidParams("duplicate JSON Schema resource URI: \{resource}")
      _ => resources[resource] = schema
    }
  }
  if schema is Object(fields) {
    for keyword in ["$anchor", "$dynamicAnchor"] {
      if fields.get(keyword) is Some(String(anchor)) {
        let target = resource + "#" + anchor
        if anchors.contains(target) {
          raise InvalidParams("duplicate JSON Schema anchor: \{target}")
        }
        anchors[target] = schema
        if keyword == "$dynamicAnchor" {
          dynamic_anchors[target] = schema
        }
      }
    }
  }
  for child in schema_children(schema, draft7) {
    index_schema_resources(
      child,
      resource,
      resources,
      anchors,
      dynamic_anchors,
      draft7,
      depth + 1,
    )
  }
}

///|
fn decode_pointer_segment(segment : String) -> String {
  segment.replace(old="~1", new="/").replace(old="~0", new="~")
}

///|
fn parse_pointer_index(value : String) -> Int? {
  if value.is_empty() {
    return None
  }
  let mut result = 0
  for char in value {
    if !(char is ('0'..='9')) {
      return None
    }
    result = result * 10 + char.to_int() - '0'.to_int()
  }
  Some(result)
}

///|
fn resolve_schema_pointer(root : Json, pointer : String) -> Json? {
  if pointer.is_empty() {
    return Some(root)
  }
  guard pointer.has_prefix("/") else { return None }
  let mut current = root
  for raw in pointer[1:].split("/") {
    let key = decode_pointer_segment(raw.to_owned())
    match current {
      Object(fields) =>
        match fields.get(key) {
          Some(value) => current = value
          None => return None
        }
      Array(values) => {
        guard parse_pointer_index(key) is Some(index) &&
          index >= 0 &&
          index < values.length() else {
          return None
        }
        current = values[index]
      }
      _ => return None
    }
  }
  Some(current)
}

///|
fn resolve_schema_reference(
  compiled : CompiledJsonSchema,
  resource : String,
  reference : String,
) -> ResolvedSchemaReference? {
  let absolute = resolve_schema_uri(resource, reference)
  let (target_resource, fragment) = split_uri_fragment(absolute)
  guard compiled.resources.get(target_resource) is Some(resource_root) else {
    return None
  }
  let target = match fragment {
    None | Some("") => Some(resource_root)
    Some(fragment) if fragment.has_prefix("/") =>
      resolve_schema_pointer(resource_root, fragment)
    Some(anchor) => compiled.anchors.get(target_resource + "#" + anchor)
  }
  guard target is Some(schema) else { return None }
  let dynamic_anchor = match fragment {
    Some(anchor) if !anchor.has_prefix("/") &&
      compiled.dynamic_anchors.contains(target_resource + "#" + anchor) =>
      Some(anchor)
    _ => None
  }
  Some({ schema, resource: target_resource, dynamic_anchor })
}

///|
fn validate_schema_references(
  schema : Json,
  compiled : CompiledJsonSchema,
  inherited_resource : String,
  draft7 : Bool,
  depth : Int,
) -> Unit raise McpError {
  if depth > 64 {
    raise InvalidParams("JSON Schema reference nesting exceeds 64 levels")
  }
  let resource = schema_resource_uri(schema, inherited_resource)
  if schema is Object(fields) {
    for keyword in ["$ref", "$dynamicRef"] {
      if fields.get(keyword) is Some(String(reference)) &&
        resolve_schema_reference(compiled, resource, reference) is None {
        raise InvalidParams("unresolved JSON Schema \{keyword}: \{reference}")
      }
    }
  }
  for child in schema_children(schema, draft7) {
    validate_schema_references(child, compiled, resource, draft7, depth + 1)
  }
}

///|
fn compile_json_schema(schema : Json) -> CompiledJsonSchema raise McpError {
  let count = Ref(0)
  let draft7 = root_uses_draft_07(schema)
  validate_schema_shape(schema, 0, count, draft7)
  let synthetic_root = "mcp-schema://local/root"
  let root_resource = schema_resource_uri(schema, synthetic_root)
  let resources : Map[String, Json] = Map([])
  let anchors : Map[String, Json] = Map([])
  let dynamic_anchors : Map[String, Json] = Map([])
  index_schema_resources(
    schema, synthetic_root, resources, anchors, dynamic_anchors, draft7, 0,
  )
  let compiled = { schema, root_resource, resources, anchors, dynamic_anchors }
  validate_schema_references(schema, compiled, synthetic_root, draft7, 0)
  compiled
}

///|
fn schema_eval_context(compiled : CompiledJsonSchema) -> JsonSchemaEvalContext {
  {
    compiled,
    resource: compiled.root_resource,
    dynamic_scope: [compiled.root_resource],
  }
}

///|
fn enter_schema_resource(
  context : JsonSchemaEvalContext,
  schema : Json,
) -> JsonSchemaEvalContext {
  let resource = match context.compiled.resources.get(context.resource) {
    Some(root) if root == schema => context.resource
    _ =>
      schema_resource_uri(schema, context.resource) catch {
        _ => context.resource
      }
  }
  if resource == context.resource {
    context
  } else {
    {
      compiled: context.compiled,
      resource,
      dynamic_scope: context.dynamic_scope + [resource],
    }
  }
}

///|
fn reference_eval_context(
  context : JsonSchemaEvalContext,
  resource : String,
) -> JsonSchemaEvalContext {
  if context.dynamic_scope.last() is Some(last) && last == resource {
    { ..context, resource, }
  } else {
    {
      compiled: context.compiled,
      resource,
      dynamic_scope: context.dynamic_scope + [resource],
    }
  }
}

///|
fn resolve_dynamic_schema_reference(
  context : JsonSchemaEvalContext,
  reference : String,
) -> ResolvedSchemaReference? {
  guard resolve_schema_reference(context.compiled, context.resource, reference)
    is Some(initial) else {
    return None
  }
  guard initial.dynamic_anchor is Some(anchor) else { return Some(initial) }
  for resource in context.dynamic_scope {
    let target = resource + "#" + anchor
    if context.compiled.dynamic_anchors.get(target) is Some(schema) {
      return Some({ schema, resource, dynamic_anchor: Some(anchor) })
    }
  }
  Some(initial)
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
fn root_uses_draft_07(root : Json) -> Bool {
  root
  is Object(
    {
      "$schema": String(
        "http://json-schema.org/draft-07/schema#"
        | "https://json-schema.org/draft-07/schema#"
      ),
      ..
    }
  )
}

///|
fn json_schema_pattern_matches(pattern : String, value : String) -> Bool {
  // Patterns are compiled during schema registration.
  Regex::unsafe_from_string(pattern).execute(value) is Some(_)
}

///|
fn collect_evaluated_object_properties(
  schema : Json,
  context : JsonSchemaEvalContext,
  object : Map[String, Json],
  evaluated : Map[String, Bool],
  depth : Int,
) -> Unit {
  if depth > 64 {
    return
  }
  let context = enter_schema_resource(context, schema)
  guard schema is Object(fields) else { return }
  for keyword in ["$ref", "$dynamicRef"] {
    if fields.get(keyword) is Some(String(reference)) {
      let target = if keyword == "$dynamicRef" {
        resolve_dynamic_schema_reference(context, reference)
      } else {
        resolve_schema_reference(context.compiled, context.resource, reference)
      }
      if target is Some(target) {
        collect_evaluated_object_properties(
          target.schema,
          reference_eval_context(context, target.resource),
          object,
          evaluated,
          depth + 1,
        )
      }
    }
  }
  let properties = match fields.get("properties") {
    Some(Object(items)) => Some(items)
    _ => None
  }
  if properties is Some(items) {
    for key, _ in items {
      if object.contains(key) {
        evaluated[key] = true
      }
    }
  }
  let patterns = match fields.get("patternProperties") {
    Some(Object(items)) => Some(items)
    _ => None
  }
  if patterns is Some(items) {
    for pattern, _ in items {
      for key, _ in object {
        if json_schema_pattern_matches(pattern, key) {
          evaluated[key] = true
        }
      }
    }
  }
  if fields.contains("additionalProperties") {
    for key, _ in object {
      let known = properties is Some(items) && items.contains(key)
      let patterned = patterns is Some(items) &&
        items.keys().any(pattern => json_schema_pattern_matches(pattern, key))
      if !known && !patterned {
        evaluated[key] = true
      }
    }
  }
  for keyword in ["allOf", "anyOf", "oneOf"] {
    if fields.get(keyword) is Some(Array(children)) {
      for child in children {
        if validate_json_schema(
            child,
            context,
            Json::object(object),
            "$",
            depth + 1,
          )
          is None {
          collect_evaluated_object_properties(
            child,
            context,
            object,
            evaluated,
            depth + 1,
          )
        }
      }
    }
  }
  if fields.get("if") is Some(condition) {
    let condition_matches = validate_json_schema(
        condition,
        context,
        Json::object(object),
        "$",
        depth + 1,
      )
      is None
    if condition_matches {
      collect_evaluated_object_properties(
        condition,
        context,
        object,
        evaluated,
        depth + 1,
      )
    }
    let branch = if condition_matches {
      fields.get("then")
    } else {
      fields.get("else")
    }
    if branch is Some(child) {
      collect_evaluated_object_properties(
        child,
        context,
        object,
        evaluated,
        depth + 1,
      )
    }
  }
  if fields.get("dependentSchemas") is Some(Object(dependencies)) {
    for key, child in dependencies {
      if object.contains(key) &&
        validate_json_schema(
          child,
          context,
          Json::object(object),
          "$",
          depth + 1,
        )
        is None {
        collect_evaluated_object_properties(
          child,
          context,
          object,
          evaluated,
          depth + 1,
        )
      }
    }
  }
}

///|
fn collect_evaluated_array_items(
  schema : Json,
  context : JsonSchemaEvalContext,
  values : Array[Json],
  evaluated : Map[Int, Bool],
  depth : Int,
) -> Unit {
  if depth > 64 {
    return
  }
  let context = enter_schema_resource(context, schema)
  guard schema is Object(fields) else { return }
  for keyword in ["$ref", "$dynamicRef"] {
    if fields.get(keyword) is Some(String(reference)) {
      let target = if keyword == "$dynamicRef" {
        resolve_dynamic_schema_reference(context, reference)
      } else {
        resolve_schema_reference(context.compiled, context.resource, reference)
      }
      if target is Some(target) {
        collect_evaluated_array_items(
          target.schema,
          reference_eval_context(context, target.resource),
          values,
          evaluated,
          depth + 1,
        )
      }
    }
  }
  if !root_uses_draft_07(context.compiled.schema) &&
    fields.get("prefixItems") is Some(Array(items)) {
    for index, _ in items {
      if index < values.length() {
        evaluated[index] = true
      }
    }
  }
  match fields.get("items") {
    Some(Array(items)) =>
      for index, _ in items {
        if index < values.length() {
          evaluated[index] = true
        }
      }
    Some(_) => {
      let start = match fields.get("prefixItems") {
        Some(Array(items)) if !root_uses_draft_07(context.compiled.schema) =>
          items.length()
        _ => 0
      }
      for index = start; index < values.length(); index = index + 1 {
        evaluated[index] = true
      }
    }
    None => ()
  }
  if fields.get("contains") is Some(contains) {
    for index, item in values {
      if validate_json_schema(contains, context, item, "$[\{index}]", depth + 1)
        is None {
        evaluated[index] = true
      }
    }
  }
  for keyword in ["allOf", "anyOf", "oneOf"] {
    if fields.get(keyword) is Some(Array(children)) {
      for child in children {
        if validate_json_schema(
            child,
            context,
            Json::array(values),
            "$",
            depth + 1,
          )
          is None {
          collect_evaluated_array_items(
            child,
            context,
            values,
            evaluated,
            depth + 1,
          )
        }
      }
    }
  }
  if fields.get("if") is Some(condition) {
    let condition_matches = validate_json_schema(
        condition,
        context,
        Json::array(values),
        "$",
        depth + 1,
      )
      is None
    if condition_matches {
      collect_evaluated_array_items(
        condition,
        context,
        values,
        evaluated,
        depth + 1,
      )
    }
    let branch = if condition_matches {
      fields.get("then")
    } else {
      fields.get("else")
    }
    if branch is Some(child) {
      collect_evaluated_array_items(
        child,
        context,
        values,
        evaluated,
        depth + 1,
      )
    }
  }
}

///|
fn validate_json_schema(
  schema : Json,
  root : JsonSchemaEvalContext,
  value : Json,
  path : String,
  depth : Int,
) -> String? {
  if depth > 128 {
    return Some(json_schema_error(path, "validation depth exceeded"))
  }
  let root = enter_schema_resource(root, schema)
  match schema {
    True => None
    False => Some(json_schema_error(path, "value is rejected by false schema"))
    Object(fields) => {
      if fields.get("$ref") is Some(String(reference)) {
        let referenced = match
          resolve_schema_reference(root.compiled, root.resource, reference) {
          Some(target) =>
            validate_json_schema(
              target.schema,
              reference_eval_context(root, target.resource),
              value,
              path,
              depth + 1,
            )
          None =>
            return Some(
              json_schema_error(path, "unresolved local $ref \{reference}"),
            )
        }
        if referenced is Some(_) || root_uses_draft_07(root.compiled.schema) {
          return referenced
        }
      }
      if fields.get("$dynamicRef") is Some(String(reference)) {
        let referenced = match
          resolve_dynamic_schema_reference(root, reference) {
          Some(target) =>
            validate_json_schema(
              target.schema,
              reference_eval_context(root, target.resource),
              value,
              path,
              depth + 1,
            )
          None =>
            return Some(
              json_schema_error(
                path,
                "unresolved local $dynamicRef \{reference}",
              ),
            )
        }
        if referenced is Some(_) {
          return referenced
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
          if fields.get("propertyNames") is Some(name_schema) {
            for key, _ in object {
              if validate_json_schema(
                  name_schema,
                  root,
                  Json::string(key),
                  "\{path}.\{key}",
                  depth + 1,
                )
                is Some(error) {
                return Some(error)
              }
            }
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
          let pattern_properties = match fields.get("patternProperties") {
            Some(Object(items)) => Some(items)
            _ => None
          }
          if pattern_properties is Some(patterns) {
            for pattern, child in patterns {
              for key, child_value in object {
                if json_schema_pattern_matches(pattern, key) &&
                  validate_json_schema(
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
          if !root_uses_draft_07(root.compiled.schema) {
            match fields.get("dependentRequired") {
              Some(Object(dependencies)) =>
                for key, dependency in dependencies {
                  if object.contains(key) && dependency is Array(names) {
                    for name in names {
                      if name is String(required) && !object.contains(required) {
                        return Some(
                          json_schema_error(
                            path,
                            "property \{key} requires property \{required}",
                          ),
                        )
                      }
                    }
                  }
                }
              _ => ()
            }
          }
          if !root_uses_draft_07(root.compiled.schema) {
            match fields.get("dependentSchemas") {
              Some(Object(dependencies)) =>
                for key, dependency in dependencies {
                  if object.contains(key) &&
                    validate_json_schema(
                      dependency,
                      root,
                      value,
                      path,
                      depth + 1,
                    )
                    is Some(error) {
                    return Some(error)
                  }
                }
              _ => ()
            }
          }
          if root_uses_draft_07(root.compiled.schema) {
            match fields.get("dependencies") {
              Some(Object(dependencies)) =>
                for key, dependency in dependencies {
                  if object.contains(key) {
                    match dependency {
                      Array(names) =>
                        for name in names {
                          if name is String(required) &&
                            !object.contains(required) {
                            return Some(
                              json_schema_error(
                                path,
                                "property \{key} requires property \{required}",
                              ),
                            )
                          }
                        }
                      child =>
                        if validate_json_schema(
                            child,
                            root,
                            value,
                            path,
                            depth + 1,
                          )
                          is Some(error) {
                          return Some(error)
                        }
                    }
                  }
                }
              _ => ()
            }
          }
          if fields.get("additionalProperties") is Some(False) {
            for key, _ in object {
              let known = properties is Some(items) && items.contains(key)
              let patterned = pattern_properties is Some(patterns) &&
                patterns
                .keys()
                .any(pattern => json_schema_pattern_matches(pattern, key))
              if !known && !patterned {
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
              let known = properties is Some(items) && items.contains(key)
              let patterned = pattern_properties is Some(patterns) &&
                patterns
                .keys()
                .any(pattern => json_schema_pattern_matches(pattern, key))
              if !known && !patterned {
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
          if fields.get("unevaluatedProperties") is Some(child) &&
            !root_uses_draft_07(root.compiled.schema) {
            let evaluated : Map[String, Bool] = Map([])
            collect_evaluated_object_properties(
              schema,
              root,
              object,
              evaluated,
              depth + 1,
            )
            for key, child_value in object {
              if !evaluated.contains(key) &&
                validate_json_schema(
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
          let prefix_items = if root_uses_draft_07(root.compiled.schema) {
            []
          } else {
            match fields.get("prefixItems") {
              Some(Array(items)) => items
              _ => []
            }
          }
          for index, child in prefix_items {
            if index < values.length() &&
              validate_json_schema(
                child,
                root,
                values[index],
                "\{path}[\{index}]",
                depth + 1,
              )
              is Some(error) {
              return Some(error)
            }
          }
          match fields.get("items") {
            Some(Array(tuple_items)) => {
              for index, child in tuple_items {
                if index < values.length() &&
                  validate_json_schema(
                    child,
                    root,
                    values[index],
                    "\{path}[\{index}]",
                    depth + 1,
                  )
                  is Some(error) {
                  return Some(error)
                }
              }
              if values.length() > tuple_items.length() &&
                fields.get("additionalItems") is Some(False) {
                return Some(
                  json_schema_error(
                    path, "additional array items are not allowed",
                  ),
                )
              }
              if fields.get("additionalItems") is Some(additional) &&
                !(additional is True) &&
                !(additional is False) {
                for index = tuple_items.length()
                    index < values.length()
                    index = index + 1 {
                  if validate_json_schema(
                      additional,
                      root,
                      values[index],
                      "\{path}[\{index}]",
                      depth + 1,
                    )
                    is Some(error) {
                    return Some(error)
                  }
                }
              }
            }
            Some(child) => {
              let start = prefix_items.length()
              for index = start; index < values.length(); index = index + 1 {
                let item = values[index]
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
            None => ()
          }
          if fields.get("contains") is Some(contains) {
            let mut matches = 0
            for item in values {
              if validate_json_schema(contains, root, item, path, depth + 1)
                is None {
                matches += 1
              }
            }
            let minimum = if root_uses_draft_07(root.compiled.schema) {
              1
            } else {
              match fields.get("minContains") {
                Some(Number(value, ..)) => value.to_int()
                _ => 1
              }
            }
            let maximum = if root_uses_draft_07(root.compiled.schema) {
              None
            } else {
              match fields.get("maxContains") {
                Some(Number(value, ..)) => Some(value.to_int())
                _ => None
              }
            }
            if matches < minimum || (maximum is Some(limit) && matches > limit) {
              return Some(
                json_schema_error(path, "array does not satisfy contains"),
              )
            }
          }
          if fields.get("unevaluatedItems") is Some(child) &&
            !root_uses_draft_07(root.compiled.schema) {
            let evaluated : Map[Int, Bool] = Map([])
            collect_evaluated_array_items(
              Json::object(fields),
              root,
              values,
              evaluated,
              depth + 1,
            )
            for index, item in values {
              if !evaluated.contains(index) &&
                validate_json_schema(
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
          if fields.get("multipleOf") is Some(Number(divisor, ..)) {
            let quotient = number / divisor
            let scale = if quotient.abs() > 1.0 { quotient.abs() } else { 1.0 }
            if divisor <= 0.0 ||
              (quotient - quotient.round()).abs() > 1.0e-12 * scale {
              return Some(
                json_schema_error(path, "number is not a multipleOf value"),
              )
            }
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
  validate_json_schema(self.schema, schema_eval_context(self), value, "$", 0)
}
