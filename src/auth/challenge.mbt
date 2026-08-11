///|
/// Parameters from an OAuth Bearer challenge. Unknown parameters are retained
/// so extensions do not need a new parser.
pub struct BearerChallenge {
  priv parameters : Map[String, String]
}

///|
pub fn BearerChallenge::parameter(
  self : BearerChallenge,
  name : String,
) -> String? {
  self.parameters.get(name.to_lower())
}

///|
pub fn BearerChallenge::resource_metadata(self : BearerChallenge) -> String? {
  self.parameter("resource_metadata")
}

///|
pub fn BearerChallenge::scope(self : BearerChallenge) -> String? {
  self.parameter("scope")
}

///|
pub fn BearerChallenge::error(self : BearerChallenge) -> String? {
  self.parameter("error")
}

///|
fn skip_ows(value : String, index0 : Int) -> Int {
  let mut index = index0
  while index < value.length() && value[index] is (' ' | '\t' | ',') {
    index += 1
  }
  index
}

///|
fn parse_token(value : String, index0 : Int) -> (String, Int) {
  let mut index = index0
  let start = index
  while index < value.length() {
    let char = value[index]
    if char is (' ' | '\t' | '=' | ',') {
      break
    }
    index += 1
  }
  (value[start:index].to_owned(), index)
}

///|
fn parse_quoted(value : String, index0 : Int) -> (String, Int) raise AuthError {
  let builder = StringBuilder()
  let mut index = index0
  index += 1
  while index < value.length() {
    let char = value[index]
    if char == '"' {
      return (builder.to_string(), index + 1)
    }
    if char == '\\' {
      index += 1
      if index >= value.length() {
        raise InvalidChallenge("unterminated quoted escape")
      }
      builder.write_char(value.get_char(index).unwrap())
    } else {
      builder.write_char(value.get_char(index).unwrap())
    }
    index += 1
  }
  raise InvalidChallenge("unterminated quoted value")
}

///|
/// Parse one Bearer challenge. Attribute names are case-insensitive; quoted
/// values support HTTP quoted-pair escaping.
pub fn parse_bearer_challenge(
  value : String,
) -> BearerChallenge raise AuthError {
  let source = value.trim().to_owned()
  let lower = source.to_lower()
  let mut search_from = 0
  let mut bearer_start : Int? = None
  while search_from < lower.length() {
    match lower[search_from:].find("bearer") {
      Some(relative) => {
        let candidate = search_from + relative
        let left_boundary = candidate == 0 ||
          source[candidate - 1] is (' ' | '\t' | ',')
        let after = candidate + 6
        let right_boundary = after == source.length() ||
          source[after] is (' ' | '\t')
        if left_boundary && right_boundary {
          bearer_start = Some(candidate)
          break
        }
        search_from = candidate + 6
      }
      None => break
    }
  }
  guard bearer_start is Some(start) else {
    raise InvalidChallenge(
      "WWW-Authenticate does not contain a Bearer challenge",
    )
  }
  let trimmed = source[start:].to_owned()
  let parameters : Map[String, String] = Map([])
  let mut index = skip_ows(trimmed, 6)
  while index < trimmed.length() {
    let (name, after_name) = parse_token(trimmed, index)
    if name.is_empty() {
      raise InvalidChallenge("challenge parameter name is empty")
    }
    index = skip_ows(trimmed, after_name)
    guard index < trimmed.length() && trimmed[index] == '=' else {
      // A following auth-scheme belongs to another challenge.
      break
    }
    index = skip_ows(trimmed, index + 1)
    let (parameter_value, after_value) = if index < trimmed.length() &&
      trimmed[index] == '"' {
      parse_quoted(trimmed, index)
    } else {
      parse_token(trimmed, index)
    }
    let key = name.to_lower()
    if parameters.contains(key) {
      raise InvalidChallenge("duplicate Bearer parameter: " + name)
    }
    parameters[key] = parameter_value
    index = skip_ows(trimmed, after_value)
  }
  { parameters, }
}

///|
pub fn scope_words(value : String) -> Array[String] {
  [
    for part in value.split(" ") if !part.is_empty() => part.to_owned()
  ]
}
