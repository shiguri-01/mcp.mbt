///|
/// Encode exactly one JSON-RPC message as one stdio frame.
fn encode_frame(message : Json) -> String {
  message.stringify() + "\n"
}

///|
/// Decode one newline-delimited stdio frame. Surrounding line whitespace is
/// ignored, but framing remains one JSON value per line.
fn decode_frame(line : StringView) -> Json raise @mcp.McpError {
  @json.parse(line.trim()) catch {
    error => raise ParseError(error.to_string())
  }
}
