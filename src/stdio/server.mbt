///|
async fn write_frames(queue : @aqueue.Queue[String?]) -> Unit {
  while queue.get() is Some(frame) {
    @async_stdio.stdout.write(frame)
  }
}

///|
/// Serve newline-delimited MCP with concurrent request dispatch and one stdout writer.
pub async fn serve(
  server : @mcp.Server,
  on_subscription? : async (@mcp.Subscription, async (Json) -> Unit) -> Unit = fn(
    _,
    _,
  ) {
    ()
  },
) -> Unit {
  @async.with_task_group(group => {
    let output : @aqueue.Queue[String?] = Queue(kind=Unbounded)
    let writer = group.spawn(() => write_frames(output))
    server.serve_framed(
      read_message=async fn() {
        match @async_stdio.stdin.read_until("\n") {
          Some(line) => {
            let message = decode_frame(line) catch {
              error => @mcp.error_response_from_json_id(error)
            }
            Some(message)
          }
          None => None
        }
      },
      send_message=async fn(msg) { output.put(Some(encode_frame(msg))) },
      on_subscription~,
    )
    output.put(None)
    writer.wait()
  })
}
