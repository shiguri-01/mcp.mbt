///|
fn error_response(id : Json?, error : @mcp.McpError) -> Json {
  @mcp.error_response_from_json_id(id?, error)
}

///|
priv struct ActiveTask {
  cancelled : Array[Bool]
  task : @async.Task[Unit]
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
    let active_subscriptions : Map[String, ActiveTask] = Map([])
    let active_requests : Map[String, ActiveTask] = Map([])
    while @async_stdio.stdin.read_until("\n") is Some(line) {
      let message = decode_frame(line) catch {
        error => {
          output.put(Some(encode_frame(error_response(None, error))))
          continue
        }
      }
      let decoded = @mcp.decode_message_opt(message)
      match decoded {
        Some(Request(request)) if request.method_name == "subscriptions/listen" => {
          let subscription = try server.accept_subscription(message) catch {
            error => {
              output.put(
                Some(
                  encode_frame(
                    error_response(Some(request.id.as_json()), error),
                  ),
                ),
              )
              continue
            }
          } noraise {
            subscription => subscription
          }
          output.put(Some(encode_frame(subscription.acknowledgement())))
          let key = subscription.id.stringify()
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
            ignore(active_subscriptions.remove(key))
          })
          active_subscriptions[key] = { cancelled, task }
        }
        Some(Notification(notification)) if notification.method_name ==
          "notifications/cancelled" => {
          let params = Some(
            @mcp.CancelledNotificationParams::from_json(notification.params),
          ) catch {
            _ => None
          }
          match params {
            Some(params) => {
              let key = params.request_id.stringify()
              match active_subscriptions.get(key) {
                Some(active) => {
                  active_subscriptions.remove(key)
                  active.cancelled[0] = true
                  active.task.cancel()
                }
                None =>
                  match active_requests.get(key) {
                    Some(active) => {
                      active_requests.remove(key)
                      active.cancelled[0] = true
                      active.task.cancel()
                    }
                    None => ()
                  }
              }
            }
            None => ()
          }
        }
        _ => {
          let req_id = match decoded {
            Some(Request(request)) => Some(request.id.as_json())
            _ => None
          }
          let key_opt = req_id.map(fn(id) { id.stringify() })
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
            if key_opt is Some(key) {
              ignore(active_requests.remove(key))
            }
          })
          handlers.push(task)
          if key_opt is Some(key) {
            active_requests[key] = { cancelled, task }
          }
        }
      }
    }
    for _, active in active_requests {
      active.cancelled[0] = true
      active.task.cancel()
    }
    for _, active in active_subscriptions {
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
