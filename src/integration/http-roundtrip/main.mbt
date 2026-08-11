///|
async fn run_server() -> Unit {
  let server = try! @mcp.Server(
    name="integration-server",
    version="1",
    tool_list_changed=true,
  )
  try! server.json_tool(
    name="echo",
    input_schema=Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "text": Json::object({ "type": Json::string("string") }),
      }),
      "required": ["text"].to_json(),
      "additionalProperties": Json::boolean(false),
    }),
    fn(_context, arguments) -> @mcp.HandlerOutcome[@mcp.CallToolResult] {
      @mcp.Complete(@mcp.CallToolResult::text(arguments.stringify()))
    },
  )
  try! server.json_tool(
    name="progress",
    input_schema=Json::object({
      "type": Json::string("object"),
      "additionalProperties": Json::boolean(false),
    }),
    async fn(
      context,
      _arguments,
    ) -> @mcp.HandlerOutcome[@mcp.CallToolResult] raise @mcp.McpError {
      context.report_progress(progress=0.5, total=1.0, message="halfway")
      @async.sleep(500) catch {
        error => raise @mcp.InternalError(error.to_string())
      }
      @mcp.Complete(@mcp.CallToolResult::text("done"))
    },
  )
  let http_server = @async_http.Server(@socket.Addr::parse("127.0.0.1:18088"))
  @mcp_http.serve(
    http_server,
    server,
    options=@mcp_http.ServerOptions(
      endpoint_path="/mcp",
      stream_responses=true,
      on_subscription=async fn(subscription, emit) {
        emit(
          @mcp.tools_list_changed_notification(
            subscription_id=subscription.id(),
          ),
        )
        @async.sleep(1000)
      },
    ),
  )
}

///|
async fn run_client(executable : String) -> Unit {
  @async.with_task_group <| group => {
    let process = @process.spawn(
      group,
      executable,
      ["--http-server"],
      no_wait=true,
    )
    let client = try! @mcp_http.Client(
      "http://127.0.0.1:18088/mcp",
      name="integration-client",
      version="1",
    )
    let mut discovered : @mcp.DiscoverResult? = None
    for _ in 0..<50 {
      discovered = try client.discover() catch {
        _ => None
      } noraise {
        value => Some(value)
      }
      if discovered is Some(_) {
        break
      }
      @async.sleep(100)
    }
    guard discovered is Some(discovery) &&
      discovery.supported_versions.contains(@mcp.latest_protocol_version) else {
      process.cancel()
      abort("HTTP server did not become discoverable")
    }
    let outcome = try! client.call_tool_raw(
      name="echo",
      arguments=Json::object({ "text": Json::string("世界—😀") }),
    )
    guard outcome
      is @mcp.Complete(
        Object(
          {
            "content": Array(
              [Object({ "type": String("text"), "text": String(text), .. }), ..]
            ),
            ..
          }
        )
      ) &&
      text.contains("世界—😀") else {
      process.cancel()
      abort("HTTP tool round trip did not preserve UTF-8 content")
    }
    let progress_received = Ref(false)
    let core = @mcp.Client(name="integration-client", version="1")
    let progress_task = group.spawn(async fn() {
      ignore(
        try! client.request_with_notifications(
          core.call_tool_request(
            name="progress",
            options=@mcp.RequestOptions(
              progress_token=Json::string("integration-progress"),
            ),
          ),
          on_notification=fn(notification) {
            if notification
              is Object({ "method": String("notifications/progress"), .. }) {
              progress_received.val = true
            }
          },
        ),
      )
    })
    @async.sleep(200)
    if !progress_received.val {
      progress_task.cancel()
      process.cancel()
      abort("HTTP request progress was not delivered before the final response")
    }
    progress_task.wait() catch {
      error => {
        process.cancel()
        abort("HTTP request progress stream failed: \{error.to_string()}")
      }
    }
    let received_notification = Ref(false)
    let listen_task = group.spawn(async fn() {
      ignore(
        try! client.listen(
          notifications=@mcp.SubscriptionFilter(tools_list_changed=true),
          on_notification=fn(notification) {
            if notification
              is Object(
                { "method": String("notifications/tools/list_changed"), .. }
              ) {
              received_notification.val = true
            }
          },
        ),
      )
    })
    @async.sleep(300)
    if !received_notification.val {
      listen_task.cancel()
      process.cancel()
      abort("HTTP SSE notification was not delivered incrementally")
    }
    listen_task.wait() catch {
      error => {
        process.cancel()
        abort("HTTP subscription failed: \{error.to_string()}")
      }
    }
    process.cancel()
    println("HTTP roundtrip complete")
  }
}

///|
async fn main {
  let arguments = @env.args()
  if arguments.contains("--http-server") {
    run_server()
  } else {
    let executable = match @env.get_env_var("MCP_HTTP_INTEGRATION_SERVER") {
      Some(value) => value
      None =>
        abort(
          "MCP_HTTP_INTEGRATION_SERVER must name this integration executable",
        )
    }
    run_client(executable)
  }
}
