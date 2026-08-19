///|
/// Validation helper for non-negative integer bounds.
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
fn set_description(fields : Map[String, Json], description : String?) -> Unit {
  if description is Some(desc) {
    fields["description"] = Json::string(desc)
  }
}

///|
/// A JSON Schema boolean schema: `true` (always pass) or `false` (always fail).
priv struct BooleanSchema {
  value : Bool
} derive(Debug)

///|
fn BooleanSchema::always() -> BooleanSchema {
  { value: true }
}

///|
fn BooleanSchema::never() -> BooleanSchema {
  { value: false }
}

///|
impl ToJson for BooleanSchema with fn to_json(self) -> Json {
  Json::boolean(self.value)
}

///|
impl SchemaNode for BooleanSchema with fn validate(
  self : BooleanSchema,
  _instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  ignore(depth)
  if !self.value {
    ctx.push_issue(path, "boolean schema is false")
  }
}

///|
/// A JSON Schema null type schema.
priv struct NullSchema {
  description : String?
} derive(Debug)

///|
fn NullSchema::NullSchema(description? : String) -> NullSchema {
  { description, }
}

///|
impl ToJson for NullSchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("null") }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for NullSchema with fn validate(
  _self : NullSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  ignore(depth)
  if !(instance is Null) {
    ctx.push_issue(path, "expected null")
  }
}

///|
/// A JSON Schema boolean type schema (`type: "boolean"`).
priv struct BoolTypeSchema {
  description : String?
} derive(Debug)

///|
fn BoolTypeSchema::BoolTypeSchema(description? : String) -> BoolTypeSchema {
  { description, }
}

///|
impl ToJson for BoolTypeSchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("boolean") }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for BoolTypeSchema with fn validate(
  _self : BoolTypeSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  ignore(depth)
  if !(instance is (True | False)) {
    ctx.push_issue(path, "expected boolean")
  }
}

///|
/// A JSON Schema string type schema with optional length constraints and description.
priv struct StringSchema {
  min_length : Int?
  max_length : Int?
  description : String?
} derive(Debug)

///|
fn StringSchema::StringSchema(
  min_length? : Int,
  max_length? : Int,
  description? : String,
) -> StringSchema raise SchemaError {
  validate_bounds(min_length, max_length, "Length")
  { min_length, max_length, description }
}

///|
impl ToJson for StringSchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("string") }
  if self.min_length is Some(value) {
    fields["minLength"] = Json::number(
      value.to_double(),
      repr=value.to_string(),
    )
  }
  if self.max_length is Some(value) {
    fields["maxLength"] = Json::number(
      value.to_double(),
      repr=value.to_string(),
    )
  }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for StringSchema with fn validate(
  self : StringSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  ignore(depth)
  if instance is String(s) {
    if self.min_length is Some(min) && s.length() < min {
      ctx.push_issue(path, "string is shorter than minLength")
    }
    if self.max_length is Some(max) && s.length() > max {
      ctx.push_issue(path, "string is longer than maxLength")
    }
  } else {
    ctx.push_issue(path, "value does not match type string")
  }
}

///|
/// A JSON Schema integer type schema.
priv struct IntegerSchema {
  minimum : Int?
  maximum : Int?
  description : String?
} derive(Debug)

///|
fn IntegerSchema::IntegerSchema(
  minimum? : Int,
  maximum? : Int,
  description? : String,
) -> IntegerSchema raise SchemaError {
  if minimum is Some(min) && maximum is Some(max) && min > max {
    raise InvalidSchema("minimum must not exceed maximum")
  }
  { minimum, maximum, description }
}

///|
impl ToJson for IntegerSchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("integer") }
  if self.minimum is Some(min) {
    fields["minimum"] = Json::number(min.to_double(), repr=min.to_string())
  }
  if self.maximum is Some(max) {
    fields["maximum"] = Json::number(max.to_double(), repr=max.to_string())
  }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for IntegerSchema with fn validate(
  self : IntegerSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  ignore(depth)
  if instance is Number(value, ..) && value == value.to_int().to_double() {
    if self.minimum is Some(min) && value.to_int() < min {
      ctx.push_issue(path, "number is less than minimum")
    }
    if self.maximum is Some(max) && value.to_int() > max {
      ctx.push_issue(path, "number is greater than maximum")
    }
  } else {
    ctx.push_issue(path, "value does not match type integer")
  }
}

///|
/// A JSON Schema number type schema.
priv struct NumberSchema {
  minimum : Double?
  maximum : Double?
  exclusive_minimum : Double?
  exclusive_maximum : Double?
  multiple_of : Double?
  description : String?
} derive(Debug)

///|
fn NumberSchema::NumberSchema(
  minimum? : Double,
  maximum? : Double,
  exclusive_minimum? : Double,
  exclusive_maximum? : Double,
  multiple_of? : Double,
  description? : String,
) -> NumberSchema raise SchemaError {
  if minimum is Some(min) && maximum is Some(max) && min > max {
    raise InvalidSchema("minimum must not exceed maximum")
  }
  if multiple_of is Some(m) && m <= 0.0 {
    raise InvalidSchema("multipleOf must be positive")
  }
  {
    minimum,
    maximum,
    exclusive_minimum,
    exclusive_maximum,
    multiple_of,
    description,
  }
}

///|
impl ToJson for NumberSchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("number") }
  if self.minimum is Some(min) {
    fields["minimum"] = Json::number(min)
  }
  if self.maximum is Some(max) {
    fields["maximum"] = Json::number(max)
  }
  if self.exclusive_minimum is Some(min) {
    fields["exclusiveMinimum"] = Json::number(min)
  }
  if self.exclusive_maximum is Some(max) {
    fields["exclusiveMaximum"] = Json::number(max)
  }
  if self.multiple_of is Some(m) {
    fields["multipleOf"] = Json::number(m)
  }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for NumberSchema with fn validate(
  self : NumberSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  ignore(depth)
  if instance is Number(value, ..) {
    if self.minimum is Some(min) && value < min {
      ctx.push_issue(path, "number is less than minimum")
    }
    if self.maximum is Some(max) && value > max {
      ctx.push_issue(path, "number is greater than maximum")
    }
    if self.exclusive_minimum is Some(min) && value <= min {
      ctx.push_issue(path, "number is not greater than exclusiveMinimum")
    }
    if self.exclusive_maximum is Some(max) && value >= max {
      ctx.push_issue(path, "number is not less than exclusiveMaximum")
    }
    if self.multiple_of is Some(divisor) && divisor > 0.0 {
      let quotient = value / divisor
      if quotient != quotient.to_int().to_double() {
        ctx.push_issue(path, "number is not a multipleOf value")
      }
    }
  } else {
    ctx.push_issue(path, "value does not match type number")
  }
}

///|
/// A JSON Schema array type schema.
priv struct ArraySchema {
  items : Schema?
  min_items : Int?
  max_items : Int?
  unique_items : Bool
  description : String?
} derive(Debug)

///|
fn ArraySchema::ArraySchema(
  items? : Schema,
  min_items? : Int,
  max_items? : Int,
  unique_items? : Bool = false,
  description? : String,
) -> ArraySchema raise SchemaError {
  validate_bounds(min_items, max_items, "Items")
  { items, min_items, max_items, unique_items, description }
}

///|
impl ToJson for ArraySchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = { "type": Json::string("array") }
  if self.items is Some(item_schema) {
    fields["items"] = item_schema.to_json()
  }
  if self.unique_items {
    fields["uniqueItems"] = Json::boolean(true)
  }
  if self.min_items is Some(n) {
    fields["minItems"] = Json::number(n.to_double(), repr=n.to_string())
  }
  if self.max_items is Some(n) {
    fields["maxItems"] = Json::number(n.to_double(), repr=n.to_string())
  }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for ArraySchema with fn validate(
  self : ArraySchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  if depth > ctx.max_depth {
    ctx.push_issue(path, "validation exceeded max_depth")
    return
  }
  if instance is Array(values) {
    if self.min_items is Some(min) && values.length() < min {
      ctx.push_issue(path, "array is shorter than minItems")
    }
    if self.max_items is Some(max) && values.length() > max {
      ctx.push_issue(path, "array is longer than maxItems")
    }
    if self.unique_items {
      let seen : Array[Json] = []
      for value in values {
        if seen.contains(value) {
          ctx.push_issue(path, "array items must be unique")
        }
        seen.push(value)
      }
    }
    if self.items is Some(item_schema) {
      for index, value in values {
        item_schema.node.validate(
          value,
          path=path.add_index(index),
          depth=depth + 1,
          ctx~,
        )
      }
    }
  } else {
    ctx.push_issue(path, "value does not match type array")
  }
}

///|
/// A JSON Schema object type schema.
priv struct ObjectSchema {
  properties : Map[String, Schema]
  required : Array[String]
  additional_properties : Bool
  min_properties : Int?
  max_properties : Int?
  description : String?
} derive(Debug)

///|
fn ObjectSchema::ObjectSchema(
  properties? : Map[String, Schema] = {},
  required? : Array[String] = [],
  additional_properties? : Bool = true,
  min_properties? : Int,
  max_properties? : Int,
  description? : String,
) -> ObjectSchema raise SchemaError {
  validate_bounds(min_properties, max_properties, "Properties")
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
  {
    properties,
    required: required.copy(),
    additional_properties,
    min_properties,
    max_properties,
    description,
  }
}

///|
impl ToJson for ObjectSchema with fn to_json(self) -> Json {
  let property_fields : Map[String, Json] = Map([])
  for name, schema in self.properties {
    property_fields[name] = schema.to_json()
  }
  let fields : Map[String, Json] = {
    "type": Json::string("object"),
    "properties": Json::object(property_fields),
    "required": self.required.to_json(),
    "additionalProperties": Json::boolean(self.additional_properties),
  }
  if self.min_properties is Some(n) {
    fields["minProperties"] = Json::number(n.to_double(), repr=n.to_string())
  }
  if self.max_properties is Some(n) {
    fields["maxProperties"] = Json::number(n.to_double(), repr=n.to_string())
  }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for ObjectSchema with fn validate(
  self : ObjectSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  if depth > ctx.max_depth {
    ctx.push_issue(path, "validation exceeded max_depth")
    return
  }
  if instance is Object(fields) {
    if self.min_properties is Some(min) && fields.length() < min {
      ctx.push_issue(path, "object has fewer than minProperties")
    }
    if self.max_properties is Some(max) && fields.length() > max {
      ctx.push_issue(path, "object has more than maxProperties")
    }
    for name in self.required {
      if fields.get(name) is None {
        ctx.push_issue(
          path.add_key(name),
          "required property is missing: \{name}",
        )
      }
    }
    for name, prop_schema in self.properties {
      if fields.get(name) is Some(prop_val) {
        prop_schema.node.validate(
          prop_val,
          path=path.add_key(name),
          depth=depth + 1,
          ctx~,
        )
      }
    }
    if !self.additional_properties {
      for name, _ in fields {
        if !self.properties.contains(name) {
          ctx.push_issue(
            path.add_key(name),
            "additional property is not allowed: \{name}",
          )
        }
      }
    }
  } else {
    ctx.push_issue(path, "value does not match type object")
  }
}

///|
/// A JSON Schema const assertion schema.
priv struct ConstSchema {
  value : Json
  description : String?
} derive(Debug)

///|
fn[T : ToJson] ConstSchema::from_value(
  value : T,
  description? : String,
) -> ConstSchema {
  { value: value.to_json(), description }
}

///|
impl ToJson for ConstSchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = { "const": self.value }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for ConstSchema with fn validate(
  self : ConstSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  ignore(depth)
  if instance != self.value {
    ctx.push_issue(path, "value does not match const")
  }
}

///|
/// A JSON Schema enum assertion schema.
priv struct EnumSchema {
  values : Array[Json]
  description : String?
} derive(Debug)

///|
fn EnumSchema::EnumSchema(
  values : Array[Json],
  description? : String,
) -> EnumSchema raise SchemaError {
  if values.is_empty() {
    raise InvalidSchema("JSON Schema enum must not be empty")
  }
  let seen : Array[Json] = []
  for value in values {
    if seen.contains(value) {
      raise InvalidSchema("JSON Schema enum values must be unique")
    }
    seen.push(value)
  }
  { values: values.copy(), description }
}

///|
fn[T : ToJson] EnumSchema::from_values(
  values : Array[T],
  description? : String,
) -> EnumSchema raise SchemaError {
  let encoded = values.map(fn(v) { v.to_json() })
  EnumSchema(encoded, description?)
}

///|
impl ToJson for EnumSchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = { "enum": self.values.to_json() }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for EnumSchema with fn validate(
  self : EnumSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  ignore(depth)
  if !self.values.contains(instance) {
    ctx.push_issue(path, "value is not in enum")
  }
}

///|
/// A JSON Schema allOf combinator schema.
priv struct AllOfSchema {
  values : Array[Schema]
  description : String?
} derive(Debug)

///|
fn AllOfSchema::AllOfSchema(
  values : Array[Schema],
  description? : String,
) -> AllOfSchema {
  { values: values.copy(), description }
}

///|
impl ToJson for AllOfSchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = {
    "allOf": self.values.map(fn(s) { s.to_json() }).to_json(),
  }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for AllOfSchema with fn validate(
  self : AllOfSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  for child in self.values {
    child.node.validate(instance, path~, depth=depth + 1, ctx~)
  }
}

///|
/// A JSON Schema anyOf combinator schema.
priv struct AnyOfSchema {
  values : Array[Schema]
  description : String?
} derive(Debug)

///|
fn AnyOfSchema::AnyOfSchema(
  values : Array[Schema],
  description? : String,
) -> AnyOfSchema raise SchemaError {
  if values.is_empty() {
    raise InvalidSchema("JSON Schema anyOf must not be empty")
  }
  { values: values.copy(), description }
}

///|
impl ToJson for AnyOfSchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = {
    "anyOf": self.values.map(fn(s) { s.to_json() }).to_json(),
  }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for AnyOfSchema with fn validate(
  self : AnyOfSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  let mut matched = false
  for child in self.values {
    let sub_ctx : ValidationContext = {
      defs: ctx.defs,
      max_depth: ctx.max_depth,
      issues: [],
    }
    child.node.validate(instance, path~, depth=depth + 1, ctx=sub_ctx)
    if sub_ctx.issues.is_empty() {
      matched = true
    }
  }
  if !matched {
    ctx.push_issue(path, "value does not match anyOf")
  }
}

///|
/// A JSON Schema oneOf combinator schema.
priv struct OneOfSchema {
  values : Array[Schema]
  description : String?
} derive(Debug)

///|
fn OneOfSchema::OneOfSchema(
  values : Array[Schema],
  description? : String,
) -> OneOfSchema raise SchemaError {
  if values.is_empty() {
    raise InvalidSchema("JSON Schema oneOf must not be empty")
  }
  { values: values.copy(), description }
}

///|
impl ToJson for OneOfSchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = {
    "oneOf": self.values.map(fn(s) { s.to_json() }).to_json(),
  }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for OneOfSchema with fn validate(
  self : OneOfSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  let mut matches = 0
  for child in self.values {
    let sub_ctx : ValidationContext = {
      defs: ctx.defs,
      max_depth: ctx.max_depth,
      issues: [],
    }
    child.node.validate(instance, path~, depth=depth + 1, ctx=sub_ctx)
    if sub_ctx.issues.is_empty() {
      matches += 1
    }
  }
  if matches != 1 {
    ctx.push_issue(path, "value must match exactly one oneOf branch")
  }
}

///|
/// A JSON Schema not combinator schema.
priv struct NotSchema {
  value : Schema
  description : String?
} derive(Debug)

///|
fn NotSchema::NotSchema(value : Schema, description? : String) -> NotSchema {
  { value, description }
}

///|
impl ToJson for NotSchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = { "not": self.value.to_json() }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for NotSchema with fn validate(
  self : NotSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  let sub_ctx : ValidationContext = {
    defs: ctx.defs,
    max_depth: ctx.max_depth,
    issues: [],
  }
  self.value.node.validate(instance, path~, depth=depth + 1, ctx=sub_ctx)
  if sub_ctx.issues.is_empty() {
    ctx.push_issue(path, "value matches a not schema")
  }
}

///|
/// A JSON Schema reference schema (`$ref`).
priv struct RefSchema {
  reference : String
  description : String?
} derive(Debug)

///|
fn RefSchema::RefSchema(
  reference : String,
  description? : String,
) -> RefSchema raise SchemaError {
  if !reference.has_prefix("#") {
    raise InvalidSchema("network JSON Schema references are disabled")
  }
  { reference, description }
}

///|
impl ToJson for RefSchema with fn to_json(self) -> Json {
  let fields : Map[String, Json] = { "$ref": Json::string(self.reference) }
  set_description(fields, self.description)
  Json::object(fields)
}

///|
impl SchemaNode for RefSchema with fn validate(
  self : RefSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  if depth > ctx.max_depth {
    ctx.push_issue(path, "validation exceeded max_depth")
    return
  }
  match ctx.defs.get(self.reference) {
    Some(target) => target.node.validate(instance, path~, depth=depth + 1, ctx~)
    None => ctx.push_issue(path, "unresolved reference: \{self.reference}")
  }
}

///|
/// An unconstrained escape hatch schema for raw JSON.
priv struct RawSchema {
  value : Json
  parsed : Schema
} derive(Debug)

///|
fn RawSchema::RawSchema(value : Json) -> RawSchema raise SchemaError {
  validate_document_syntax(value)
  let parsed = parse_schema_json(value) catch { _ => Schema::always() }
  { value, parsed }
}

///|
impl ToJson for RawSchema with fn to_json(self) -> Json {
  self.value
}

///|
impl SchemaNode for RawSchema with fn validate(
  self : RawSchema,
  instance : Json,
  path~ : @json.JsonPath,
  depth~ : Int,
  ctx~ : ValidationContext,
) -> Unit {
  self.parsed.node.validate(instance, path~, depth~, ctx~)
}
