///|
priv struct ActiveSessionTask {
  cancelled : Ref[Bool]
  task : @async.Task[Unit]
}

///|
fn ActiveSessionTask::cancel(self : ActiveSessionTask) -> Unit {
  self.cancelled.val = true
  self.task.cancel()
}

///|
priv struct ServerSession {
  server : Server
  group : @async.TaskGroup[Unit]
  output : @aqueue.Queue[Json?]
  active_tasks : Map[String, ActiveSessionTask]
  handlers : Array[@async.Task[Unit]]
  on_subscription : async (Subscription, async (Json) -> Unit) -> Unit
}

///|
async fn ServerSession::emit(self : ServerSession, message : Json) -> Unit {
  self.output.put(Some(message)) catch {
    _ => ()
  }
}

///|
fn ServerSession::dispatch_subscription(
  self : ServerSession,
  request_id : @jsonrpc.RequestId,
  message : Json,
) -> Unit {
  let subscription = self.server.accept_subscription(message) catch {
    error => {
      ignore(
        self.group.spawn(() => {
          self.emit(error.to_response(id=request_id).to_json())
        }),
      )
      return
    }
  }
  let key = subscription.id.stringify()
  let cancelled = Ref(false)
  let task = self.group.spawn(() => {
    self.emit(subscription.acknowledgement())
    let emit_event = async fn(notification : Json) {
      if subscription.allows_event(notification) {
        self.emit(notification)
      }
    }
    (self.on_subscription)(subscription, emit_event) catch {
      _ => ()
    }
    if !cancelled.val {
      self.emit(subscription.close_response())
    }
    self.active_tasks.remove(key)
  })
  self.active_tasks[key] = { cancelled, task }
}

///|
fn ServerSession::cancel_task(self : ServerSession, message : Json) -> Unit {
  try {
    guard @jsonrpc.decode(message) is Notification({ params, .. }) else {
      return
    }
    let params = @mcp.CancelledNotificationParams::from_json(params)
    let key = params.request_id.stringify()
    if self.active_tasks.get(key) is Some(active) {
      self.active_tasks.remove(key)
      active.cancel()
    }
  } catch {
    _ => ()
  }
}

///|
fn ServerSession::dispatch_rpc(
  self : ServerSession,
  request_id : @jsonrpc.RequestId?,
  message : Json,
) -> Unit {
  let key_opt = request_id.map(fn(id) { id.to_routing_key() })
  let cancelled = Ref(false)
  let task = self.group.spawn(() => {
    let hooks = @mcp.RequestHooks(
      emit_notification=async fn(notification) raise @mcp.McpError {
        self.emit(notification) catch {
          error => raise @mcp.InternalError(error.to_string())
        }
      },
      is_cancelled=fn() { cancelled.val },
    )
    if self.server.handle_jsonrpc_with_hooks(message, hooks~) is Some(response) {
      self.emit(response)
    }
    if key_opt is Some(key) {
      self.active_tasks.remove(key)
    }
  })
  self.handlers.push(task)
  if key_opt is Some(key) {
    self.active_tasks[key] = { cancelled, task }
  }
}

///|
fn ServerSession::handle_message(self : ServerSession, message : Json) -> Unit {
  let decoded = Some(@jsonrpc.decode(message)) catch { _ => None }
  match decoded {
    Some(Request({ id, method_name: "subscriptions/listen", .. })) =>
      self.dispatch_subscription(id, message)
    Some(Notification({ method_name: "notifications/cancelled", .. })) =>
      self.cancel_task(message)
    Some(Request({ id, .. })) => self.dispatch_rpc(Some(id), message)
    _ => self.dispatch_rpc(None, message)
  }
}

///|
async fn ServerSession::shutdown(self : ServerSession) -> Unit {
  for _, active in self.active_tasks {
    active.cancel()
  }
  for task in self.handlers {
    task.wait() catch {
      _ => ()
    }
  }
  self.output.put(None) catch {
    _ => ()
  }
}

///|
/// Serve a bidirectional stream of MCP messages.
///
/// Handles concurrent request dispatch, `subscriptions/listen` stream lifecycles,
/// `notifications/cancelled` task cancellation, and progress notifications.
pub async fn Server::serve_framed(
  self : Server,
  read_message~ : async () -> Json?,
  send_message~ : async (Json) -> Unit,
  on_subscription? : async (Subscription, async (Json) -> Unit) -> Unit = fn(
    _,
    _,
  ) {
    ()
  },
) -> Unit {
  @async.with_task_group(group => {
    let output : @aqueue.Queue[Json?] = Queue(kind=Unbounded)
    let writer = group.spawn(() => {
      while output.get() is Some(msg) {
        send_message(msg)
      }
    })
    let session = ServerSession::{
      server: self,
      group,
      output,
      active_tasks: Map([]),
      handlers: [],
      on_subscription,
    }
    while read_message() is Some(message) {
      session.handle_message(message)
    }
    session.shutdown()
    writer.wait() catch {
      _ => ()
    }
  })
}
