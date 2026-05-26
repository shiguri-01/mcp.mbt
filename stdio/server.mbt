///|
/// Serve an MCP server over newline-delimited JSON-RPC on stdin/stdout.
pub async fn serve(server : @mcp.Server) -> Unit {
  while @async_stdio.stdin.read_until("\n") is Some(line) {
    let message = @json.parse(line.trim()) catch {
      error => {
        let response = Json::object({
          "jsonrpc": Json::string("2.0"),
          "id": Json::null(),
          "error": @mcp.ParseError(error.to_string()).to_json(),
        })
        @async_stdio.stdout.write(response.stringify() + "\n")
        continue
      }
    }
    match server.handle_jsonrpc(message) {
      Some(response) => @async_stdio.stdout.write(response.stringify() + "\n")
      None => ()
    }
  }
}
