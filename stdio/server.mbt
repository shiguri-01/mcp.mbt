///|
pub async fn serve(server : @mcp.Server) -> Unit {
  while @async_stdio.stdin.read_until("\n") is Some(line) {
    let message = @json.parse(line.trim()) catch {
      error => {
        let response = @mcp.jsonrpc_error(
          None,
          @mcp.ParseError(error.to_string()),
        )
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
