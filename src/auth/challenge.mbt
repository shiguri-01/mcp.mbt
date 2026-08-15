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
fn is_tchar(char : Char) -> Bool {
  char
  is ('a'..='z'
  | 'A'..='Z'
  | '0'..='9'
  | '!'
  | '#'
  | '$'
  | '%'
  | '&'
  | '\''
  | '*'
  | '+'
  | '-'
  | '.'
  | '^'
  | '_'
  | '`'
  | '|'
  | '~')
}

///|
fn validate_header_characters(value : String) -> Unit raise AuthError {
  for char in value {
    let code = char.to_int()
    if (code < 0x20 && char != '\t') || code == 0x7f {
      raise InvalidChallenge("WWW-Authenticate contains a control character")
    }
  }
}

///|
fn find_bearer_start(value : String) -> Int? {
  let mut quoted = false
  let mut escaped = false
  let mut index = 0
  while index + 6 <= value.length() {
    let char = value[index]
    if quoted {
      if escaped {
        escaped = false
      } else if char == '\\' {
        escaped = true
      } else if char == '"' {
        quoted = false
      }
      index += 1
      continue
    }
    if char == '"' {
      quoted = true
      index += 1
      continue
    }
    if value[index:index + 6].equal_ignore_ascii_case("Bearer") {
      let mut before = index - 1
      while before >= 0 && value[before] is (' ' | '\t') {
        before -= 1
      }
      let left_boundary = before < 0 || value[before] == ','
      let after = index + 6
      let right_boundary = after == value.length() ||
        value[after] is (' ' | '\t')
      if left_boundary && right_boundary {
        return Some(index)
      }
    }
    index += 1
  }
  None
}

///|
fn parse_token(value : String, index0 : Int) -> (String, Int) {
  let mut index = index0
  let start = index
  while index < value.length() {
    if !is_tchar(value.get_char(index).unwrap()) {
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
    if (char != '\t' && char.to_int() < 0x20) || char.to_int() == 0x7f {
      raise InvalidChallenge(
        "quoted Bearer parameter contains a control character",
      )
    }
    if char == '"' {
      return (builder.to_string(), index + 1)
    }
    if char == '\\' {
      index += 1
      if index >= value.length() {
        raise InvalidChallenge("unterminated quoted escape")
      }
      let escaped = value.get_char(index).unwrap()
      if (escaped != '\t' && escaped.to_int() < 0x20) ||
        escaped.to_int() == 0x7f {
        raise InvalidChallenge(
          "quoted Bearer escape contains a control character",
        )
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
pub fn BearerChallenge::parse(
  value : String,
) -> BearerChallenge raise AuthError {
  let source = value.trim().to_owned()
  validate_header_characters(source)
  let bearer_start = find_bearer_start(source)
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
      if after_name < trimmed.length() &&
        !(trimmed[after_name] is (' ' | '\t' | ',')) {
        raise InvalidChallenge("Bearer parameter name is not an HTTP token")
      }
      // A following auth-scheme belongs to another challenge.
      break
    }
    index = skip_ows(trimmed, index + 1)
    let (parameter_value, after_value) = if index < trimmed.length() &&
      trimmed[index] == '"' {
      parse_quoted(trimmed, index)
    } else {
      let parsed = parse_token(trimmed, index)
      if parsed.0.is_empty() {
        raise InvalidChallenge("Bearer parameter value is not a token")
      }
      parsed
    }
    if after_value < trimmed.length() &&
      !(trimmed[after_value] is (' ' | '\t' | ',')) {
      raise InvalidChallenge("Bearer parameter value is not an HTTP token")
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
