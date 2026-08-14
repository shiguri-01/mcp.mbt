///|
/// Native stdio client for the self-contained MCP 2026-07-28 protocol.
pub struct Client {
  priv core : @mcp.Client
  priv process : @process.Process
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
/// Spawn a server process. Client identity and capabilities are copied into
/// every request; no initialize handshake is performed.
pub async fn[X] Client::spawn(
  group : @async.TaskGroup[X],
  command : String,
  name~ : String,
  version~ : String,
  capabilities? : @mcp.ClientCapabilities = @mcp.ClientCapabilities::empty(),
  extension_result_types? : Map[String, String] = Map([]),
  args? : Array[String] = [],
  cwd? : String,
) -> Client raise @mcp.McpError {
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
    core: Client(name~, version~, capabilities~, extension_result_types~),
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
pub fn Client::close(self : Client) -> Unit {
  fail_pending_now(self.pending, "MCP stdio client was closed")
  self.progress_routes.clear()
  ignore(self.outbound.try_put(None) catch { _ => false })
}

///|
/// Cancel the transport and wait until the child process has terminated.
pub async fn Client::close_and_wait(self : Client) -> Unit raise @mcp.McpError {
  self.close()
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
pub async fn Client::shutdown(self : Client) -> Unit raise @mcp.McpError {
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
async fn route_message(
  pending : Map[String, @aqueue.Queue[Inbound]],
  progress_routes : Map[String, String],
  message : Json,
) -> Unit raise @mcp.McpError {
  match @mcp.response_id(message) {
    Some(id) =>
      if pending.get(@mcp.routing_key(id)) is Some(queue) {
        put_inbound(queue, Message(message))
      }
    None =>
      match @mcp.extract_subscription_id(message) {
        Some(id) =>
          if pending.get(@mcp.routing_key(id)) is Some(queue) {
            put_inbound(queue, Message(message))
          }
        None =>
          match @mcp.extract_notification_progress_token(message) {
            Some(token) =>
              if progress_routes.get(@mcp.routing_key(token))
                is Some(request_key) &&
                pending.get(request_key) is Some(queue) {
                put_inbound(queue, Message(message))
              }
            None if pending.length() == 1 =>
              for _, queue in pending {
                put_inbound(queue, Message(message))
              }
            None => ()
          }
      }
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
async fn Client::read_response(
  self : Client,
  queue : @aqueue.Queue[Inbound],
  expected_id : Json,
  on_notification : (Json) -> Unit,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  match get_inbound(queue) {
    Failed(error) => raise error
    Message(message) =>
      match @mcp.response_id(message) {
        None => {
          on_notification(message)
          self.read_response(queue, expected_id, on_notification)
        }
        Some(actual_id) => {
          if actual_id != expected_id {
            raise InvalidRequest("stdio response id does not match request id")
          }
          self.core.decode_response(message)
        }
      }
  }
}

///|
/// Send one request while observing progress or subscription notifications
/// that arrive before its final response.
pub async fn Client::request_with_notifications(
  self : Client,
  request : Json,
  on_notification~ : (Json) -> Unit,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  let id = @mcp.request_id(request)
  let key = @mcp.routing_key(id)
  if self.pending.contains(key) {
    raise InvalidRequest("stdio request id is already active")
  }
  let progress_key = @mcp.extract_request_progress_token(request).map(
    @mcp.routing_key,
  )
  if progress_key is Some(token_key) && self.progress_routes.contains(token_key) {
    raise InvalidRequest("stdio progress token is already active")
  }
  let queue : @aqueue.Queue[Inbound] = Queue(kind=Unbounded)
  self.pending[key] = queue
  if progress_key is Some(token_key) {
    self.progress_routes[token_key] = key
  }
  self.outbound.put(Some(encode_frame(request))) catch {
    error => {
      ignore(self.pending.remove(key))
      if progress_key is Some(token_key) {
        ignore(self.progress_routes.remove(token_key))
      }
      raise InternalError(error.to_string())
    }
  }
  let result = self.read_response(queue, id, on_notification) catch {
    error => {
      ignore(self.pending.remove(key))
      if progress_key is Some(token_key) {
        ignore(self.progress_routes.remove(token_key))
      }
      raise error
    }
  }
  ignore(self.pending.remove(key))
  if progress_key is Some(token_key) {
    ignore(self.progress_routes.remove(token_key))
  }
  result
}

///|
pub async fn Client::request(
  self : Client,
  request : Json,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.request_with_notifications(request, on_notification=fn(_) { () })
}

///|
pub async fn Client::notify(
  self : Client,
  notification : Json,
) -> Unit raise @mcp.McpError {
  let decoded = @jsonrpc.decode(notification) catch {
    _ => raise InvalidRequest("stdio notify requires a JSON-RPC notification")
  }
  guard decoded is @jsonrpc.Message::Notification(_) else {
    raise InvalidRequest("stdio notify requires a JSON-RPC notification")
  }
  self.outbound.put(Some(encode_frame(notification))) catch {
    error => raise InternalError(error.to_string())
  }
}

///|
/// Cancel an in-flight request or long-lived subscription.
pub async fn Client::cancel(
  self : Client,
  request_id~ : Json,
  reason? : String,
) -> Unit raise @mcp.McpError {
  self.notify(@mcp.cancelled_notification(request_id~, reason?))
  if self.pending.get(@mcp.routing_key(request_id)) is Some(queue) {
    put_inbound(queue, Failed(InternalError("request was cancelled")))
  }
}

///|
pub impl @mcp.ClientTransport for Client with fn request_with_notifications(
  self : Client,
  request : Json,
  on_notification~ : (Json) -> Unit,
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.request_with_notifications(request, on_notification~)
}

///|
pub impl @mcp.ClientTransport for Client with fn notify(
  self : Client,
  notification : Json,
) -> Unit raise @mcp.McpError {
  self.notify(notification)
}

///|
pub async fn Client::discover(
  self : Client,
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.DiscoverResult raise @mcp.McpError {
  self.core.discover(self, options~)
}

///|
pub async fn Client::list_tools_raw(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = RequestOptions(),
) -> Json raise @mcp.McpError {
  self.core.list_tools_raw(self, cursor?, options~)
}

///|
/// List tools as the canonical domain result. Use `list_tools_raw` for
/// transport-level extension inspection.
pub async fn Client::list_tools(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.ListToolsResult raise @mcp.McpError {
  self.core.list_tools(self, cursor?, options~)
}

///|
pub async fn Client::call_tool_raw(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.core.call_tool_raw(self, name~, arguments~, options~)
}

///|
pub async fn Client::call_tool(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.HandlerOutcome[@mcp.CallToolResult] raise @mcp.McpError {
  self.core.call_tool(self, name~, arguments~, options~)
}

///|
pub async fn[T : FromJson] Client::call_tool_as(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.HandlerOutcome[T] raise @mcp.McpError {
  self.core.call_tool_as(self, name~, arguments~, options~)
}

///|
pub async fn Client::list_resources_raw(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = RequestOptions(),
) -> Json raise @mcp.McpError {
  self.core.list_resources_raw(self, cursor?, options~)
}

///|
pub async fn Client::list_resources(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.ListResourcesResult raise @mcp.McpError {
  self.core.list_resources(self, cursor?, options~)
}

///|
pub async fn Client::list_resource_templates_raw(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = RequestOptions(),
) -> Json raise @mcp.McpError {
  self.core.list_resource_templates_raw(self, cursor?, options~)
}

///|
pub async fn Client::list_resource_templates(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.ListResourceTemplatesResult raise @mcp.McpError {
  self.core.list_resource_templates(self, cursor?, options~)
}

///|
pub async fn Client::read_resource_raw(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.core.read_resource_raw(self, uri~, options~)
}

///|
pub async fn Client::read_resource(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.HandlerOutcome[@mcp.ReadResourceResult] raise @mcp.McpError {
  self.core.read_resource(self, uri~, options~)
}

///|
pub async fn Client::list_prompts_raw(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = RequestOptions(),
) -> Json raise @mcp.McpError {
  self.core.list_prompts_raw(self, cursor?, options~)
}

///|
pub async fn Client::list_prompts(
  self : Client,
  cursor? : String,
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.ListPromptsResult raise @mcp.McpError {
  self.core.list_prompts(self, cursor?, options~)
}

///|
pub async fn Client::get_prompt_raw(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.HandlerOutcome[Json] raise @mcp.McpError {
  self.core.get_prompt_raw(self, name~, arguments~, options~)
}

///|
pub async fn Client::get_prompt(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.HandlerOutcome[@mcp.GetPromptResult] raise @mcp.McpError {
  self.core.get_prompt(self, name~, arguments~, options~)
}

///|
pub async fn Client::complete_raw(
  self : Client,
  reference~ : @mcp.CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
  options? : @mcp.RequestOptions = RequestOptions(),
) -> Json raise @mcp.McpError {
  self.core.complete_raw(
    self,
    reference~,
    argument_name~,
    argument_value~,
    context_arguments?,
    options~,
  )
}

///|
pub async fn Client::complete(
  self : Client,
  reference~ : @mcp.CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
  options? : @mcp.RequestOptions = RequestOptions(),
) -> @mcp.CompleteResult raise @mcp.McpError {
  self.core.complete(
    self,
    reference~,
    argument_name~,
    argument_value~,
    context_arguments?,
    options~,
  )
}

///|
/// Open a long-lived subscription and deliver stream notifications until the
/// server returns its final result. Use `cancel` from another task to stop it.
pub async fn Client::listen(
  self : Client,
  notifications~ : @mcp.SubscriptionFilter,
  on_notification~ : (Json) -> Unit,
  options? : @mcp.RequestOptions = RequestOptions(),
) -> Json raise @mcp.McpError {
  self.core.listen(self, notifications~, on_notification~, options~)
}

///|
/// Resolve bounded multi round-trip input requests for a tool call. Every
/// retry has a fresh JSON-RPC id and preserves opaque server request state.
pub async fn Client::call_tool_resolving_raw(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> Json raise @mcp.McpError {
  self.core.call_tool_resolving_raw(
    self,
    name~,
    arguments~,
    options~,
    max_rounds~,
    resolve~,
  )
}

///|
pub async fn Client::call_tool_resolving(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> @mcp.CallToolResult raise @mcp.McpError {
  self.core.call_tool_resolving(
    self,
    name~,
    arguments~,
    options~,
    max_rounds~,
    resolve~,
  )
}

///|
pub async fn Client::read_resource_resolving_raw(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> Json raise @mcp.McpError {
  self.core.read_resource_resolving_raw(
    self,
    uri~,
    options~,
    max_rounds~,
    resolve~,
  )
}

///|
pub async fn Client::read_resource_resolving(
  self : Client,
  uri~ : String,
  options? : @mcp.RequestOptions = RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> @mcp.ReadResourceResult raise @mcp.McpError {
  self.core.read_resource_resolving(self, uri~, options~, max_rounds~, resolve~)
}

///|
pub async fn Client::get_prompt_resolving_raw(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> Json raise @mcp.McpError {
  self.core.get_prompt_resolving_raw(
    self,
    name~,
    arguments~,
    options~,
    max_rounds~,
    resolve~,
  )
}

///|
pub async fn Client::get_prompt_resolving(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
  options? : @mcp.RequestOptions = RequestOptions(),
  max_rounds? : Int = 8,
  resolve~ : async (Map[String, @mcp.InputRequest]) -> Map[
    String,
    @mcp.InputResponse,
  ] raise @mcp.McpError,
) -> @mcp.GetPromptResult raise @mcp.McpError {
  self.core.get_prompt_resolving(
    self,
    name~,
    arguments~,
    options~,
    max_rounds~,
    resolve~,
  )
}
