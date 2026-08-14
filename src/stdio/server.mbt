///|
fn inbound_id(message : Json) -> Json? {
  match @mcp.decode_message_opt(message) {
    Some(Request({ id, .. })) => Some(id.as_json())
    _ => None
  }
}

///|
fn error_response(id : Json?, error : @mcp.McpError) -> Json {
  @mcp.error_response_from_json_id(id?, error)
}

///|
fn is_listen_request(message : Json) -> Bool {
  match @mcp.decode_message_opt(message) {
    Some(Request({ method_name: "subscriptions/listen", .. })) => true
    _ => false
  }
}

///|
fn cancelled_request_id(message : Json) -> Json? {
  match @mcp.decode_message_opt(message) {
    Some(
      Notification(
        { method_name: "notifications/cancelled", params: Object(params) }
      )
    ) =>
      match params.get("requestId") {
        Some(String(_) | Number(_) as id) => Some(id)
        _ => None
      }
    _ => None
  }
}

///|
fn find_subscription(
  subscriptions : Array[ActiveSubscription],
  id : Json,
) -> Int? {
  for index, active in subscriptions {
    if active.subscription.id == id {
      return Some(index)
    }
  }
  None
}

///|
priv struct ActiveSubscription {
  subscription : @mcp.Subscription
  cancelled : Array[Bool]
  task : @async.Task[Unit]
}

///|
priv struct ActiveRequest {
  id : Json
  cancelled : Array[Bool]
  task : @async.Task[Unit]
}

///|
fn find_request(requests : Array[ActiveRequest], id : Json) -> Int? {
  for index, active in requests {
    if active.id == id {
      return Some(index)
    }
  }
  None
}

///|
async fn write_frames(queue : @aqueue.Queue[String?]) -> Unit {
  while queue.get() is Some(frame) {
    @async_stdio.stdout.write(frame)
  }
}

///|
/// Serve newline-delimited MCP with concurrent request dispatch and one stdout
/// writer. Listen requests remain transport-owned: acknowledgement is always
/// the first stream event; client cancellation sends no final response.
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
    let handlers : Array[@async.Task[Unit]] = []
    let subscriptions : Array[ActiveSubscription] = []
    let requests : Array[ActiveRequest] = []
    while @async_stdio.stdin.read_until("\n") is Some(line) {
      let message = decode_frame(line) catch {
        error => {
          output.put(Some(encode_frame(error_response(None, error))))
          continue
        }
      }
      if is_listen_request(message) {
        let subscription = try server.accept_subscription(message) catch {
          error => {
            output.put(
              Some(encode_frame(error_response(inbound_id(message), error))),
            )
            continue
          }
        } noraise {
          subscription => subscription
        }
        // Queue the acknowledgement before starting application work.
        output.put(Some(encode_frame(subscription.acknowledgement())))
        let cancelled = [false]
        let task = group.spawn(() => {
          on_subscription(subscription, async fn(notification) {
            if subscription.allows_event(notification) {
              output.put(Some(encode_frame(notification)))
            }
          }) catch {
            _ => ()
          }
          if !cancelled[0] {
            output.put(Some(encode_frame(subscription.close_response())))
          }
          if find_subscription(subscriptions, subscription.id) is Some(index) {
            ignore(subscriptions.remove(index))
          }
        })
        subscriptions.push({ subscription, cancelled, task })
        continue
      }
      if cancelled_request_id(message) is Some(id) {
        if find_subscription(subscriptions, id) is Some(index) {
          let active = subscriptions.remove(index)
          active.cancelled[0] = true
          active.task.cancel()
        } else if find_request(requests, id) is Some(index) {
          let active = requests.remove(index)
          active.cancelled[0] = true
          active.task.cancel()
        }
        continue
      }
      let id = inbound_id(message)
      let cancelled = [false]
      let task = group.spawn(() => {
        let hooks = @mcp.RequestHooks(
          emit_notification=async fn(notification) raise @mcp.McpError {
            output.put(Some(encode_frame(notification))) catch {
              error => raise InternalError(error.to_string())
            }
          },
          is_cancelled=fn() { cancelled[0] },
        )
        match server.handle_jsonrpc_with_hooks(message, hooks~) {
          Some(response) => output.put(Some(encode_frame(response)))
          None => ()
        }
        if id is Some(request_id) &&
          find_request(requests, request_id) is Some(index) {
          ignore(requests.remove(index))
        }
      })
      handlers.push(task)
      if id is Some(request_id) {
        requests.push({ id: request_id, cancelled, task })
      }
    }
    // EOF cancels all work before joining so a disconnected client cannot
    // leave the server process blocked in an application handler.
    for active in requests {
      active.cancelled[0] = true
      active.task.cancel()
    }
    while subscriptions.pop() is Some(active) {
      active.cancelled[0] = true
      active.task.cancel()
    }
    for task in handlers {
      task.wait() catch {
        _ => ()
      }
    }
    output.put(None)
    writer.wait()
  })
}
