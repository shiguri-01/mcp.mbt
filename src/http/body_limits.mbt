///|
/// The built-in HTTP adapter accepts at most 4 MiB for one MCP JSON request
/// unless the host selects another limit.
pub let default_max_request_body_bytes : Int = 4 * 1024 * 1024

///|
/// The HTTP client retains at most 4 MiB for one non-streaming response unless
/// the caller selects another limit.
pub let default_max_response_body_bytes : Int = 4 * 1024 * 1024

///|
/// A streaming response may contain any number of SSE events, but the client
/// retains at most 1 MiB for one event unless the caller selects another limit.
pub let default_max_sse_event_bytes : Int = 1024 * 1024

///|
priv suberror BodyReadError {
  BodyTooLarge(subject~ : String, limit~ : Int)
  BodyInvalidUtf8(subject~ : String)
  BodyReadFailed(subject~ : String, message~ : String)
}

///|
fn body_read_error_to_mcp(error : BodyReadError) -> @mcp.McpError {
  match error {
    BodyTooLarge(subject~, limit~) =>
      @mcp.InvalidRequest(
        "\{subject} exceeds the configured limit of \{limit} bytes",
      )
    BodyInvalidUtf8(subject~) =>
      @mcp.ParseError("\{subject} is not valid UTF-8")
    BodyReadFailed(subject~, message~) =>
      @mcp.InternalError("could not read \{subject}: \{message}")
  }
}

///|
async fn read_bounded_text(
  reader : &@io.Reader,
  limit : Int,
  subject : String,
) -> String raise BodyReadError {
  let bytes : Array[Byte] = []
  while true {
    let remaining = limit - bytes.length()
    let read_size = if remaining >= 8192 { 8192 } else { remaining + 1 }
    let chunk = reader.read_some(max_len=read_size) catch {
      error => raise BodyReadFailed(subject~, message=error.to_string())
    }
    guard chunk is Some(chunk) else { break }
    if chunk.length() > remaining {
      raise BodyTooLarge(subject~, limit~)
    }
    bytes.append(chunk.to_array())
  }
  @utf8.decode(Bytes::from_array(bytes)) catch {
    _ => raise BodyInvalidUtf8(subject~)
  }
}

///|
fn decimal_header_exceeds(value : String, limit : Int) -> Bool {
  let value = value.trim()
  if value.is_empty() {
    return false
  }
  let mut parsed = 0
  for char in value {
    guard char is ('0'..='9') else { return false }
    let digit = char.to_int() - '0'.to_int()
    if parsed > (limit - digit) / 10 {
      return true
    }
    parsed = parsed * 10 + digit
  }
  parsed > limit
}

///|
priv struct SseReadState {
  mut pending : Array[Byte]
  mut data_lines : Array[String]
  mut event_bytes : Int
  mut eof : Bool
}

///|
fn SseReadState::new() -> SseReadState {
  { pending: [], data_lines: [], event_bytes: 0, eof: false }
}

///|
fn first_lf(bytes : Array[Byte]) -> Int? {
  for index, byte in bytes {
    if byte == b'\n' {
      return Some(index)
    }
  }
  None
}

///|
async fn read_sse_line(
  reader : &@io.Reader,
  state : SseReadState,
  limit : Int,
) -> String? raise BodyReadError {
  while true {
    if first_lf(state.pending) is Some(index) {
      state.event_bytes += index + 1
      if state.event_bytes > limit {
        raise BodyTooLarge(subject="MCP SSE event", limit~)
      }
      let end = if index > 0 && state.pending[index - 1] == b'\r' {
        index - 1
      } else {
        index
      }
      let line = @utf8.decode(Bytes::from_array(state.pending[:end])) catch {
        _ => raise BodyInvalidUtf8(subject="MCP SSE event")
      }
      state.pending = state.pending[index + 1:].to_owned()
      return Some(line)
    }
    if state.eof {
      if state.pending.is_empty() {
        return None
      }
      state.event_bytes += state.pending.length()
      if state.event_bytes > limit {
        raise BodyTooLarge(subject="MCP SSE event", limit~)
      }
      let line = @utf8.decode(Bytes::from_array(state.pending)) catch {
        _ => raise BodyInvalidUtf8(subject="MCP SSE event")
      }
      state.pending = []
      return Some(line)
    }
    if state.event_bytes + state.pending.length() > limit {
      raise BodyTooLarge(subject="MCP SSE event", limit~)
    }
    let chunk = reader.read_some(max_len=8192) catch {
      error =>
        raise BodyReadFailed(subject="MCP SSE event", message=error.to_string())
    }
    match chunk {
      Some(bytes) => state.pending.append(bytes.to_array())
      None => state.eof = true
    }
  }
  None
}

///|
async fn read_sse_data(
  reader : &@io.Reader,
  state : SseReadState,
  limit : Int,
) -> String? raise BodyReadError {
  while read_sse_line(reader, state, limit) is Some(line) {
    if line == "" {
      let data = state.data_lines.join("\n")
      state.data_lines = []
      state.event_bytes = 0
      if data != "" {
        return Some(data)
      }
    } else if line.has_prefix("data:"[:]) {
      let value = line[5:]
      state.data_lines.push(
        if value.has_prefix(" "[:]) {
          value[1:].to_owned()
        } else {
          value.to_owned()
        },
      )
    }
  }
  if !state.data_lines.is_empty() {
    let data = state.data_lines.join("\n")
    state.data_lines = []
    state.event_bytes = 0
    if data != "" {
      return Some(data)
    }
  }
  None
}
