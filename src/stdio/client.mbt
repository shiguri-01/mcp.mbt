///|
/// Stdio MCP client that owns the spawned server process and pipe handles.
pub struct Client {
  priv core : @mcp.Client
  priv process : @process.Process
  priv reader : @process.ReadFromProcess
  priv writer : @process.WriteToProcess
}

///|
/// Spawn a stdio MCP server process and connect stdin/stdout pipes.
pub async fn[X] Client::spawn(
  group : @async.TaskGroup[X],
  command : String,
  args? : Array[String] = [],
  cwd? : String,
) -> Client {
  let (server_stdin, client_writer) = @process.write_to_process()
  let (client_reader, server_stdout) = @process.read_from_process()
  let process = match cwd {
    Some(cwd) =>
      @process.spawn(
        group,
        command,
        args,
        stdin=server_stdin,
        stdout=server_stdout,
        cwd~,
      )
    None =>
      @process.spawn(
        group,
        command,
        args,
        stdin=server_stdin,
        stdout=server_stdout,
      )
  }
  { core: @mcp.Client(), process, reader: client_reader, writer: client_writer }
}

///|
/// Return the OS process id of the spawned server.
pub fn Client::pid(self : Client) -> Int {
  self.process.pid
}

///|
/// Close the client-side pipe handles.
pub fn Client::close(self : Client) -> Unit {
  self.writer.close()
  self.reader.close()
}

///|
fn request_id(request : Json) -> Json raise @mcp.McpError {
  match request {
    Object({ "id": id, .. }) => id
    _ => raise @mcp.InvalidRequest("JSON-RPC request id is required")
  }
}

///|
async fn Client::read_matching_response(
  self : Client,
  expected_id : Json,
) -> Json raise @mcp.McpError {
  let line = self.reader.read_until("\n") catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  let line = match line {
    Some(line) => line.trim()
    None => raise @mcp.InternalError("MCP server closed stdout")
  }
  let response = @json.parse(line) catch {
    error => raise @mcp.ParseError(error.to_string())
  }
  match response {
    Object({ "id": id, .. }) =>
      if id == expected_id {
        parse_response_result(response)
      } else {
        self.read_matching_response(expected_id)
      }
    _ => self.read_matching_response(expected_id)
  }
}

///|
fn parse_response_result(response : Json) -> Json raise @mcp.McpError {
  let fields = match response {
    Object(fields) => fields
    _ => raise @mcp.InvalidRequest("JSON-RPC response must be an object")
  }
  match fields.get("error") {
    Some(Object(error)) => {
      let message = match error.get("message") {
        Some(String(message)) => message
        _ => "JSON-RPC error"
      }
      raise @mcp.InternalError(message)
    }
    Some(_) => raise @mcp.InvalidRequest("JSON-RPC error must be an object")
    None => ()
  }
  match fields.get("result") {
    Some(result) => result
    None => raise @mcp.InvalidRequest("JSON-RPC response result is required")
  }
}

///|
pub async fn Client::request(
  self : Client,
  request : Json,
) -> Json raise @mcp.McpError {
  let id = request_id(request)
  self.writer.write(request.stringify() + "\n") catch {
    error => raise @mcp.InternalError(error.to_string())
  }
  self.read_matching_response(id)
}

///|
pub async fn Client::notify(
  self : Client,
  notification : Json,
) -> Unit raise @mcp.McpError {
  self.writer.write(notification.stringify() + "\n") catch {
    error => raise @mcp.InternalError(error.to_string())
  }
}

///|
/// Send `initialize` and then `notifications/initialized`.
pub async fn Client::initialize(
  self : Client,
  client_name~ : String,
  client_version~ : String,
) -> Json raise @mcp.McpError {
  let response = self.request(
    self.core.initialize_request(client_name~, client_version~),
  )
  self.notify(self.core.initialized_notification())
  response
}

///|
pub async fn Client::list_tools(
  self : Client,
  cursor? : String,
) -> Json raise @mcp.McpError {
  self.request(self.core.list_tools_request(cursor?))
}

///|
pub async fn Client::call_tool(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
) -> Json raise @mcp.McpError {
  self.request(self.core.call_tool_request(name~, arguments~))
}

///|
/// Decode a tool result's `structuredContent` through `FromJson`.
pub async fn[T : FromJson] Client::call_tool_as(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
) -> T raise @mcp.McpError {
  @mcp.decode_structured_content(self.call_tool(name~, arguments~))
}

///|
pub async fn Client::list_resources(
  self : Client,
  cursor? : String,
) -> Json raise @mcp.McpError {
  self.request(self.core.list_resources_request(cursor?))
}

///|
pub async fn Client::list_resource_templates(
  self : Client,
  cursor? : String,
) -> Json raise @mcp.McpError {
  self.request(self.core.list_resource_templates_request(cursor?))
}

///|
pub async fn Client::read_resource(
  self : Client,
  uri~ : String,
) -> Json raise @mcp.McpError {
  self.request(self.core.read_resource_request(uri~))
}

///|
pub async fn Client::list_prompts(
  self : Client,
  cursor? : String,
) -> Json raise @mcp.McpError {
  self.request(self.core.list_prompts_request(cursor?))
}

///|
pub async fn Client::get_prompt(
  self : Client,
  name~ : String,
  arguments? : Json = Json::object({}),
) -> Json raise @mcp.McpError {
  self.request(self.core.get_prompt_request(name~, arguments~))
}

///|
pub async fn Client::complete(
  self : Client,
  reference~ : @mcp.CompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String],
) -> Json raise @mcp.McpError {
  self.request(
    self.core.complete_request(
      reference~,
      argument_name~,
      argument_value~,
      context_arguments?,
    ),
  )
}

///|
pub async fn Client::set_logging_level(
  self : Client,
  level~ : @mcp.LoggingLevel,
) -> Json raise @mcp.McpError {
  self.request(self.core.set_logging_level_request(level~))
}

///|
pub async fn Client::ping(self : Client) -> Json raise @mcp.McpError {
  self.request(self.core.ping_request())
}
