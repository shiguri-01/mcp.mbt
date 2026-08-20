///|
pub using @client {type Client}

///|
/// Native stdio transport for the self-contained MCP 2026-07-28 protocol.
pub struct Transport {
  process : @process.Process
  pid : Int
  priv outbound : @aqueue.Queue[String?]
  priv pending : Map[String, @aqueue.Queue[Inbound]]
  priv progress_routes : Map[String, String]
  priv writer_task : @async.Task[Unit]
  priv reader_task : @async.Task[Unit]
}

///|
priv enum Inbound {
  Message(Json)
  Failed(@mcp.McpError)
}

///|
/// Spawn a server process and return its transport.
pub async fn[X] Transport::Transport(
  group : @async.TaskGroup[X],
  command : String,
  args? : Array[String] = [],
  cwd? : String,
) -> Transport raise @mcp.McpError {
  let (server_stdin, client_writer) = @process.write_to_process() catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  let (client_reader, server_stdout) = @process.read_from_process() catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  let process = match cwd {
    Some(cwd) =>
      @process.spawn(
        group,
        command,
        args,
        stdin=server_stdin,
        stdout=server_stdout,
        cwd~,
        cancel_handler=@process.hard_cancel(),
        no_wait=true,
      ) catch {
        error => raise @mcp.InternalError(error.to_string())
      }
    None =>
      @process.spawn(
        group,
        command,
        args,
        stdin=server_stdin,
        stdout=server_stdout,
        cancel_handler=@process.hard_cancel(),
        no_wait=true,
      ) catch {
        error => raise @mcp.InternalError(error.to_string())
      }
  }
  let outbound : @aqueue.Queue[String?] = Queue(kind=Unbounded)
  let pending : Map[String, @aqueue.Queue[Inbound]] = Map([])
  let progress_routes : Map[String, String] = Map([])
  let writer_task = group.spawn(() => write_messages(client_writer, outbound))
  let reader_task = group.spawn(() => {
    read_messages(client_reader, pending, progress_routes)
  })
  {
    process,
    pid: process.pid,
    outbound,
    pending,
    progress_routes,
    writer_task,
    reader_task,
  }
}

///|
pub impl @client.ClientTransport for Transport with fn close(self : Transport) -> Unit {
  fail_pending_now(self.pending, "MCP stdio client was closed")
  self.progress_routes.clear()
  ignore(self.outbound.try_put(None) catch { _ => false })
}

///|
/// Cancel the transport and wait until the child process has terminated.
pub async fn Transport::close_and_wait(
  self : Transport,
) -> Unit raise @mcp.McpError {
  @client.ClientTransport::close(self)
  self.writer_task.wait() catch {
    error => raise InternalError(error.to_string())
  }
  ignore(
    self.process.wait() catch {
      error => raise InternalError(error.to_string())
    },
  )
  self.reader_task.wait() catch {
    error => raise InternalError(error.to_string())
  }
}

///|
fn fail_pending_now(
  pending : Map[String, @aqueue.Queue[Inbound]],
  message : String,
) -> Unit {
  for queue in pending.values() {
    ignore(queue.try_put(Failed(InternalError(message))) catch { _ => false })
  }
  pending.clear()
}

///|
/// Close stdin, wait for the server to observe EOF, and join transport tasks.
pub async fn Transport::shutdown(self : Transport) -> Unit raise @mcp.McpError {
  self.outbound.put(None) catch {
    error => raise InternalError(error.to_string())
  }
  self.writer_task.wait() catch {
    error => raise InternalError(error.to_string())
  }
  let exit_code = self.process.wait() catch {
    error => raise InternalError(error.to_string())
  }
  self.reader_task.wait() catch {
    error => raise InternalError(error.to_string())
  }
  if exit_code != 0 {
    raise InternalError("MCP server exited with status \{exit_code}")
  }
}

///|
async fn write_messages(
  writer : @process.WriteToProcess,
  outbound : @aqueue.Queue[String?],
) -> Unit {
  while outbound.get() is Some(frame) {
    writer.write(frame)
  }
  writer.close()
}

///|
async fn broadcast_failure(
  pending : Map[String, @aqueue.Queue[Inbound]],
  error : @mcp.McpError,
) -> Unit {
  let queues = pending.values().collect()
  for queue in queues {
    queue.put(Failed(error))
  }
}

///|
async fn put_inbound(
  queue : @aqueue.Queue[Inbound],
  item : Inbound,
) -> Unit raise @mcp.McpError {
  queue.put(item) catch {
    error => raise InternalError(error.to_string())
  }
}

///|
async fn get_inbound(
  queue : @aqueue.Queue[Inbound],
) -> Inbound raise @mcp.McpError {
  queue.get() catch {
    error => raise InternalError(error.to_string())
  }
}

///|

///|
async fn route_message(
  pending : Map[String, @aqueue.Queue[Inbound]],
  progress_routes : Map[String, String],
  message : Json,
) -> Unit raise @mcp.McpError {
  let decoded = @jsonrpc.decode(message) catch {
    error => raise @mcp.McpError::from_jsonrpc_decode_error(error)
  }
  match decoded {
    Response(Success(id~, ..)) | Response(Failure(id=Some(id), ..)) =>
      if pending.get(id.to_routing_key()) is Some(queue) {
        put_inbound(queue, Message(message))
      }
    Response(Failure(id=None, ..)) => ()
    Notification({ method_name: "notifications/progress", params }) =>
      try {
        let progress_params = @mcp.ProgressNotificationParams::from_json(params)
        let token_key = match progress_params.progress_token {
          String(s) => "string:\{s}"
          Number(num, repr~) => "number:" + repr.unwrap_or(num.to_string())
          _ => progress_params.progress_token.stringify()
        }
        if progress_routes.get(token_key) is Some(request_key) &&
          pending.get(request_key) is Some(queue) {
          put_inbound(queue, Message(message))
        }
      } catch {
        _ => ()
      }
    Notification(_) =>
      match @client.extract_subscription_id(message) {
        Some(sub_id) => {
          let sub_key = match sub_id {
            String(s) => "string:\{s}"
            Number(num, repr~) => "number:" + repr.unwrap_or(num.to_string())
            _ => sub_id.stringify()
          }
          if pending.get(sub_key) is Some(queue) {
            put_inbound(queue, Message(message))
          }
        }
        None =>
          if pending.length() == 1 {
            for _, queue in pending {
              put_inbound(queue, Message(message))
            }
          }
      }
    Request(_) =>
      raise InvalidRequest(
        "server-to-client JSON-RPC requests are not valid in MCP 2026-07-28",
      )
  }
}

///|
async fn read_messages(
  reader : @process.ReadFromProcess,
  pending : Map[String, @aqueue.Queue[Inbound]],
  progress_routes : Map[String, String],
) -> Unit {
  while true {
    let line = reader.read_until("\n") catch {
      error => {
        broadcast_failure(pending, InternalError(error.to_string()))
        return
      }
    }
    guard line is Some(line) else { break }
    let message = decode_frame(line) catch {
      error => {
        broadcast_failure(pending, error)
        continue
      }
    }
    route_message(pending, progress_routes, message) catch {
      error => broadcast_failure(pending, error)
    }
  }
  broadcast_failure(pending, InternalError("MCP server closed stdout"))
}

///|
fn decode_raw_response(
  message : Json,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  @mcp.HandlerOutcome::decode_response(message)
}

///|
async fn Transport::read_response(
  self : Transport,
  queue : @aqueue.Queue[Inbound],
  expected_id : @jsonrpc.RequestId,
  on_notification : (Json) -> Unit,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  match get_inbound(queue) {
    Failed(error) => raise error
    Message(message) => {
      let decoded = @jsonrpc.decode(message) catch {
        error => raise @mcp.McpError::from_jsonrpc_decode_error(error)
      }
      match decoded {
        Notification(_) => {
          on_notification(message)
          self.read_response(queue, expected_id, on_notification)
        }
        Response(Success(id~, ..)) | Response(Failure(id=Some(id), ..)) => {
          if id != expected_id {
            raise InvalidRequest("stdio response id does not match request id")
          }
          decode_raw_response(message)
        }
        Response(Failure(id=None, ..)) => decode_raw_response(message)
        Request(_) =>
          raise InvalidRequest(
            "server-to-client JSON-RPC requests are not valid in MCP 2026-07-28",
          )
      }
    }
  }
}

///|
/// Send one request while observing progress or subscription notifications
/// that arrive before its final response.
pub impl @client.ClientTransport for Transport with fn request_with_notifications(
  self : Transport,
  request : Json,
  on_notification~ : (Json) -> Unit,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  let decoded = @jsonrpc.decode(request) catch {
    _ => raise InvalidRequest("request is not a valid JSON-RPC message")
  }
  guard decoded is Request(req) else {
    raise InvalidRequest("message must be a JSON-RPC request")
  }
  let id = req.id
  let key = id.to_routing_key()
  if self.pending.contains(key) {
    raise InvalidRequest("stdio request id is already active")
  }
  let progress_token = match decoded {
    Request(
      {
        params: Object(
          {
            "_meta": Object(
              { "progressToken": String(_) | Number(_) as token, .. }
            ),
            ..
          }
        ),
        ..,
      }
    ) => Some(token)
    _ => None
  }
  let progress_key = match progress_token {
    Some(String(s)) => Some("string:\{s}")
    Some(Number(num, repr~)) =>
      Some("number:" + repr.unwrap_or(num.to_string()))
    _ => None
  }
  if progress_key is Some(token_key) && self.progress_routes.contains(token_key) {
    raise InvalidRequest("stdio progress token is already active")
  }
  let queue : @aqueue.Queue[Inbound] = Queue(kind=Unbounded)
  self.pending[key] = queue
  if progress_key is Some(token_key) {
    self.progress_routes[token_key] = key
  }
  defer {
    ignore(self.pending.remove(key))
    if progress_key is Some(token_key) {
      ignore(self.progress_routes.remove(token_key))
    }
  }
  self.outbound.put(Some(encode_frame(request))) catch {
    error => raise InternalError(error.to_string())
  }
  self.read_response(queue, id, on_notification)
}

///|
pub impl @client.ClientTransport for Transport with fn notify(
  self : Transport,
  notification : Json,
) -> Unit raise @mcp.McpError {
  let decoded = @jsonrpc.decode(notification) catch {
    _ => raise InvalidRequest("stdio notify requires a JSON-RPC notification")
  }
  guard decoded is Notification(_) else {
    raise InvalidRequest("stdio notify requires a JSON-RPC notification")
  }
  self.outbound.put(Some(encode_frame(notification))) catch {
    error => raise InternalError(error.to_string())
  }
}
