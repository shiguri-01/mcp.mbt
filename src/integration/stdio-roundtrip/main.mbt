///|
async fn run_server() -> Unit {
  let server = try! @mcp_server.Server(name="integration-server", version="1")
  try! server.tool_raw(
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
  try! server.tool_raw(
    name="wait",
    input_schema=Json::object({
      "type": Json::string("object"),
      "additionalProperties": Json::boolean(false),
    }),
    async fn(
      _context,
      _arguments,
    ) -> @mcp.HandlerOutcome[@mcp.CallToolResult] raise @mcp.McpError {
      @async.sleep(30000) catch {
        error => raise @mcp.InternalError(error.to_string())
      }
      @mcp.Complete(@mcp.CallToolResult::text("done"))
    },
  )
  @mcp_stdio.serve(server)
}

///|
async fn run_client(executable : String) -> Unit {
  @async.with_task_group <| group => {
    let client = try! @mcp_stdio.Client::spawn(
      group,
      executable,
      name="integration-client",
      version="1",
      args=["--stdio-server"],
    )
    let discovery = client.discover() catch {
      error => abort("stdio discovery failed: \{error.message()}")
    }
    if !discovery.supported_versions.contains(@mcp.LATEST_PROTOCOL_VERSION) {
      abort("server did not advertise the current protocol version")
    }
    let outcome = client.call_tool_raw(
      name="echo",
      arguments=Json::object({ "text": Json::string("世界—😀") }),
    ) catch {
      error => abort("stdio tool call failed: \{error.message()}")
    }
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
      abort("stdio tool round trip did not return content")
    }
    println("roundtrip complete")
    try! client.shutdown()
    println("shutdown complete")
    let closing_client = try! @mcp_stdio.Client::spawn(
      group,
      executable,
      name="closing-client",
      version="1",
      args=["--stdio-server"],
    )
    let pending = group.spawn(
      async fn() { closing_client.call_tool(name="wait") },
      allow_failure=true,
    )
    @async.sleep(200)
    try! closing_client.close_and_wait()
    try pending.wait() catch {
      _ => println("in-flight close complete")
    } noraise {
      _ => abort("closing an in-flight stdio client returned a result")
    }
  }
}

///|
async fn main {
  let arguments = @env.args()
  if arguments.contains("--stdio-server") {
    run_server()
  } else {
    let executable = match @env.get_env_var("MCP_STDIO_INTEGRATION_SERVER") {
      Some(value) => value
      None =>
        abort(
          "MCP_STDIO_INTEGRATION_SERVER must name this integration executable",
        )
    }
    run_client(executable)
  }
}
