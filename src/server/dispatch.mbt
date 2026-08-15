///|
fn parse_context(
  request : @jsonrpc.Request[Json],
  hooks? : @mcp.RequestHooks = @mcp.RequestHooks(),
) -> @mcp.RequestContext raise @mcp.McpError {
  guard request.params is Object(fields) else {
    raise @mcp.InvalidParams("request params must be an object")
  }
  let meta = match fields {
    { "_meta": value, .. } => @mcp.RequestMeta::from_json(value)
    _ => raise @mcp.InvalidParams("request params._meta is required")
  }
  let input_responses = match fields {
    { "inputResponses": value, .. } =>
      Some(@mcp.InputResponse::map_from_json(value))
    _ => None
  }
  let request_state = match fields {
    { "requestState": String(s), .. } => Some(s)
    { "requestState": Null, .. } => None
    { "requestState": _, .. } =>
      raise @mcp.InvalidParams("request params.requestState must be a string")
    _ => None
  }
  @mcp.RequestContext(
    request_id=request.id.as_json(),
    method_name=request.method_name,
    meta~,
    input_responses?,
    request_state?,
    hooks~,
  )
}

///|
fn required_elicitation_capability(
  request : @mcp.InputRequest,
) -> @mcp.ClientCapabilities {
  let is_url = request.params is Object({ "mode": String("url"), .. })
  @mcp.ClientCapabilities(
    elicitation=if is_url {
      @mcp.ElicitationCapability(url=Json::object({}))
    } else {
      @mcp.ElicitationCapability(form=Json::object({}))
    },
  )
}

///|
fn required_client_capability(method_name : String) -> @mcp.ClientCapabilities {
  match method_name {
    "roots/list" => @mcp.ClientCapabilities(roots=@mcp.RootsCapability())
    "sampling/createMessage" =>
      @mcp.ClientCapabilities(sampling=@mcp.SamplingCapability())
    _ => @mcp.ClientCapabilities()
  }
}

///|
fn Server::validate_input_requests(
  self : Server,
  context : @mcp.RequestContext,
  result : @mcp.InputRequiredResult,
) -> Unit raise @mcp.McpError {
  ignore(self)
  if result.input_requests is Some(requests) {
    for _, request in requests {
      match request.method_name {
        "elicitation/create" => {
          let required = required_elicitation_capability(request)
          let actual = context.meta.client_capabilities.elicitation
          let accepted = match (required.elicitation, actual) {
            (Some({ url: Some(_), .. }), Some({ url: Some(_), .. })) => true
            (Some({ form: Some(_), .. }), Some({ form: Some(_), .. })) => true
            (Some({ form: Some(_), .. }), Some({ form: None, url: None })) =>
              true
            _ => false
          }
          if !accepted {
            raise @mcp.MissingRequiredClientCapability(
              "Request requires client elicitation capability", required,
            )
          }
        }
        "roots/list" | "sampling/createMessage" as method_name => {
          let actual_roots = context.meta.client_capabilities.roots
          let actual_sampling = context.meta.client_capabilities.sampling
          let accepted = match method_name {
            "roots/list" => actual_roots is Some(_)
            "sampling/createMessage" => actual_sampling is Some(_)
            _ => false
          }
          if !accepted {
            raise @mcp.MissingRequiredClientCapability(
              "Request requires client capability: \{method_name}",
              required_client_capability(method_name),
            )
          }
        }
        method_name =>
          raise @mcp.InvalidRequest(
            "unsupported MRTR input request: \{method_name}",
          )
      }
    }
  }
}

///|
fn Server::input_required_json(
  self : Server,
  context : @mcp.RequestContext,
  result : @mcp.InputRequiredResult,
) -> Json raise @mcp.McpError {
  self.validate_input_requests(context, result)
  @mcp.stamp_result_meta(result.to_json(), server_info=self.info)
}

///|
fn Server::extension_result_json(
  self : Server,
  result_type : String,
  result : Json,
) -> Json raise @mcp.McpError {
  if !self.extension_result_types.contains(result_type) {
    raise @mcp.InvalidRequest(
      "handler returned unregistered extension result type \{result_type}",
    )
  }
  guard result is Object(fields) else {
    raise @mcp.InvalidParams("extension result must be an object")
  }
  let fields = fields.copy_json()
  fields["resultType"] = Json::string(result_type)
  @mcp.stamp_result_meta(Json::object(fields), server_info=self.info)
}

///|
fn[T : ToJson] Server::outcome_json(
  self : Server,
  context : @mcp.RequestContext,
  method_name : String,
  outcome : @mcp.HandlerOutcome[T],
) -> Json raise @mcp.McpError {
  match outcome {
    @mcp.Complete(value) =>
      @mcp.complete_result(value.to_json(), server_info=self.info)
    @mcp.InputRequired(result) => {
      if method_name != "tools/call" &&
        method_name != "resources/read" &&
        method_name != "prompts/get" {
        raise @mcp.InvalidRequest(
          "input_required is not allowed for \{method_name}",
        )
      }
      self.input_required_json(context, result)
    }
    @mcp.ExtensionResult(result_type, result) =>
      self.extension_result_json(result_type, result)
  }
}

///|
fn Server::cacheable_complete(
  self : Server,
  payload : Json,
) -> Json raise @mcp.McpError {
  guard payload is Object(fields) else {
    raise @mcp.InvalidParams("cacheable result must be an object")
  }
  let fields = fields.copy_json()
  fields["ttlMs"] = Json::number(
    self.cache_policy.ttl_ms.to_double(),
    repr="\{self.cache_policy.ttl_ms}",
  )
  fields["cacheScope"] = self.cache_policy.scope.to_json()
  @mcp.complete_result(Json::object(fields), server_info=self.info)
}

///|
fn Server::discover(self : Server) -> Json raise @mcp.McpError {
  @mcp.DiscoverResult(
    supported_versions=self.supported_versions,
    capabilities=self.capabilities(),
    instructions?=self.instructions,
    cache_policy=self.cache_policy,
    meta=@mcp.ResultMeta(server_info=self.info),
  ).to_json()
}

///|
priv struct Page[T] {
  items : Array[T]
  next_cursor : String?
}

///|
fn parse_cursor(cursor : String?, total : Int) -> Int raise @mcp.McpError {
  match cursor {
    None => 0
    Some(cursor) => {
      let mut offset = 0
      if cursor.length() == 0 {
        return 0
      }
      if cursor.length() > 20 {
        raise @mcp.InvalidParams("cursor exceeds the supported length")
      }
      for c in cursor {
        if c < '0' || c > '9' {
          raise @mcp.InvalidParams(
            "cursor must be an opaque cursor returned by the server",
          )
        }
        let digit = c.to_int() - '0'.to_int()
        if digit > total || offset > (total - digit) / 10 {
          raise @mcp.InvalidParams("cursor is out of range")
        }
        offset = offset * 10 + digit
      }
      if offset < 0 || offset > total {
        raise @mcp.InvalidParams("cursor is out of range")
      }
      offset
    }
  }
}

///|
fn[T] paginate(
  items : Array[T],
  cursor? : String,
  page_size? : Int = 100,
) -> Page[T] raise @mcp.McpError {
  let total = items.length()
  let start = parse_cursor(cursor, total)
  let limit = if page_size <= 0 { total } else { page_size }
  let stop = if start + limit < total { start + limit } else { total }
  let page = Array::makei(stop - start, fn(i) { items[start + i] })
  let next_cursor = if stop < total { Some("\{stop}") } else { None }
  { items: page, next_cursor }
}

///|
fn Server::list_tools(
  self : Server,
  params : @mcp.ListParams,
) -> Json raise @mcp.McpError {
  if self.tools.is_empty() {
    raise @mcp.MethodNotFound("tools/list")
  }
  let page = paginate(
    Array::from_iter(self.tools.values().map(item => item.tool)),
    cursor?=params.cursor,
  )
  let payload : Map[String, Json] = {
    "tools": page.items.map(item => item.to_json()).to_json(),
  }
  payload.set_opt("nextCursor", page.next_cursor.map(Json::string))
  self.cacheable_complete(Json::object(payload))
}

///|
async fn Server::call_tool(
  self : Server,
  context : @mcp.RequestContext,
  params : @mcp.CallToolParams,
) -> Json raise @mcp.McpError {
  if self.tools.is_empty() {
    raise @mcp.MethodNotFound("tools/call")
  }
  let name = params.name
  let arguments = params.arguments
  guard self.tools.get(name) is Some(registered) else {
    raise @mcp.InvalidParams("unknown tool: \{name}")
  }
  if schema_validation_error(registered.input_validator, arguments)
    is Some(error) {
    return self.outcome_json(
      context,
      "tools/call",
      @mcp.Complete(
        @mcp.CallToolResult::error_text(
          "Invalid tool arguments: inputSchema validation failed: \{error}",
        ),
      ),
    )
  }
  let outcome = (registered.handler)(context, arguments)
  match outcome {
    @mcp.Complete(result) =>
      if registered.output_validator is Some(validator) && !result.is_error {
        guard result.structured_content is Some(value) else {
          raise @mcp.InternalError(
            "tool declares outputSchema but returned no structuredContent",
          )
        }
        if schema_validation_error(validator, value) is Some(error) {
          raise @mcp.InternalError(
            "tool structuredContent does not match outputSchema: \{error}",
          )
        }
      }
    @mcp.InputRequired(_) => ()
    @mcp.ExtensionResult(_, _) => ()
  }
  self.outcome_json(context, "tools/call", outcome)
}

///|
fn Server::list_resources(
  self : Server,
  params : @mcp.ListParams,
) -> Json raise @mcp.McpError {
  if self.resources.is_empty() && self.resource_templates.is_empty() {
    raise @mcp.MethodNotFound("resources/list")
  }
  let page = paginate(
    Array::from_iter(self.resources.values().map(item => item.resource)),
    cursor?=params.cursor,
  )
  let payload : Map[String, Json] = {
    "resources": page.items.map(item => item.to_json()).to_json(),
  }
  payload.set_opt("nextCursor", page.next_cursor.map(Json::string))
  self.cacheable_complete(Json::object(payload))
}

///|
fn Server::list_resource_templates(
  self : Server,
  params : @mcp.ListParams,
) -> Json raise @mcp.McpError {
  if self.resource_templates.is_empty() {
    raise @mcp.MethodNotFound("resources/templates/list")
  }
  let page = paginate(
    Array::from_iter(
      self.resource_templates.values().map(item => item.template),
    ),
    cursor?=params.cursor,
  )
  let payload : Map[String, Json] = {
    "resourceTemplates": page.items.map(item => item.to_json()).to_json(),
  }
  payload.set_opt("nextCursor", page.next_cursor.map(Json::string))
  self.cacheable_complete(Json::object(payload))
}

///|
async fn Server::read_resource(
  self : Server,
  context : @mcp.RequestContext,
  params : @mcp.ReadResourceParams,
) -> Json raise @mcp.McpError {
  if self.resources.is_empty() && self.resource_templates.is_empty() {
    raise @mcp.MethodNotFound("resources/read")
  }
  let uri = params.uri
  if self.resources.get(uri) is Some(registered) {
    return match (registered.handler)(context, uri) {
      @mcp.Complete(value) => self.cacheable_complete(value.to_json())
      @mcp.InputRequired(value) => self.input_required_json(context, value)
      @mcp.ExtensionResult(result_type, value) =>
        self.extension_result_json(result_type, value)
    }
  }
  for registered in self.resource_templates.values() {
    if registered.captures(uri) is Some(captures) {
      return match (registered.handler)(context, uri, captures) {
        @mcp.Complete(value) => self.cacheable_complete(value.to_json())
        @mcp.InputRequired(value) => self.input_required_json(context, value)
        @mcp.ExtensionResult(result_type, value) =>
          self.extension_result_json(result_type, value)
      }
    }
  }
  raise @mcp.InvalidParamsWithData(
    "resource not found: \{uri}",
    Json::object({ "uri": Json::string(uri) }),
  )
}

///|
fn Server::list_prompts(
  self : Server,
  params : @mcp.ListParams,
) -> Json raise @mcp.McpError {
  if self.prompts.is_empty() {
    raise @mcp.MethodNotFound("prompts/list")
  }
  let page = paginate(
    Array::from_iter(self.prompts.values().map(item => item.prompt)),
    cursor?=params.cursor,
  )
  let payload : Map[String, Json] = {
    "prompts": page.items.map(item => item.to_json()).to_json(),
  }
  payload.set_opt("nextCursor", page.next_cursor.map(Json::string))
  self.cacheable_complete(Json::object(payload))
}

///|
async fn Server::get_prompt(
  self : Server,
  context : @mcp.RequestContext,
  params : @mcp.GetPromptParams,
) -> Json raise @mcp.McpError {
  if self.prompts.is_empty() {
    raise @mcp.MethodNotFound("prompts/get")
  }
  let name = params.name
  guard self.prompts.get(name) is Some(registered) else {
    raise @mcp.InvalidParams("unknown prompt: \{name}")
  }
  let arguments = params.arguments
  for argument in registered.prompt.arguments {
    if argument.required && !arguments.contains(argument.name) {
      raise @mcp.InvalidParams(
        "prompts/get required argument is missing: \{argument.name}",
      )
    }
  }
  self.outcome_json(
    context,
    "prompts/get",
    (registered.handler)(context, arguments),
  )
}

///|
async fn Server::complete(
  self : Server,
  context : @mcp.RequestContext,
  request : @mcp.CompletionRequest,
) -> Json raise @mcp.McpError {
  if self.completions.is_empty() {
    raise @mcp.MethodNotFound("completion/complete")
  }
  let key = completion_key(request.reference)
  guard self.completions.get(key) is Some(handler) else {
    raise @mcp.InvalidParams("no completion handler registered for \{key}")
  }
  @mcp.complete_result(
    handler(context, request).to_json(),
    server_info=self.info,
  )
}

///|
async fn Server::dispatch_request(
  self : Server,
  request : @jsonrpc.Request[Json],
  hooks? : @mcp.RequestHooks = @mcp.RequestHooks(),
) -> Json raise @mcp.McpError {
  self.registry_frozen = true
  let context = parse_context(request, hooks~)
  self.ensure_supported_version(context)
  match request.method_name {
    "server/discover" => self.discover()
    "tools/list" => self.list_tools(@mcp.ListParams::from_json(request.params))
    "tools/call" =>
      self.call_tool(context, @mcp.CallToolParams::from_json(request.params))
    "resources/list" =>
      self.list_resources(@mcp.ListParams::from_json(request.params))
    "resources/templates/list" =>
      self.list_resource_templates(@mcp.ListParams::from_json(request.params))
    "resources/read" =>
      self.read_resource(
        context,
        @mcp.ReadResourceParams::from_json(request.params),
      )
    "prompts/list" =>
      self.list_prompts(@mcp.ListParams::from_json(request.params))
    "prompts/get" =>
      self.get_prompt(context, @mcp.GetPromptParams::from_json(request.params))
    "completion/complete" =>
      self.complete(context, @mcp.CompletionRequest::from_json(request.params))
    "subscriptions/listen" =>
      raise @mcp.InvalidRequest(
        "subscriptions/listen must be handled as a transport stream",
      )
    method_name => {
      guard self.raw_handlers.get(method_name) is Some(handler) else {
        raise @mcp.MethodNotFound(method_name)
      }
      self.outcome_json(context, method_name, handler(context, request.params))
    }
  }
}

///|
/// Handle one MCP JSON-RPC request. Batches and client-sent responses are
/// rejected. The stdio transport consumes cancellation notifications itself.
pub async fn Server::handle_jsonrpc(self : Server, message : Json) -> Json? {
  self.handle_jsonrpc_with_hooks(message, hooks=@mcp.RequestHooks())
}

///|
/// Dispatch one request with transport-owned progress, cancellation, and
/// authentication metadata hooks.
pub async fn Server::handle_jsonrpc_with_hooks(
  self : Server,
  message : Json,
  hooks~ : @mcp.RequestHooks,
) -> Json? {
  let decoded = @jsonrpc.decode(message) catch {
    error =>
      return Some(
        @mcp.error_response(
          @mcp.InvalidRequest(
            match error {
              InvalidMessage(msg) => msg
            },
          ),
        ),
      )
  }
  match decoded {
    @jsonrpc.Message::Notification(_) => None
    @jsonrpc.Message::Response(_) =>
      Some(
        @mcp.error_response(
          @mcp.InvalidRequest("MCP server expected a request"),
        ),
      )
    @jsonrpc.Message::Request(request) =>
      try {
        let result = self.dispatch_request(request, hooks~)
        Some(@mcp.success_response(request.id, result))
      } catch {
        error => Some(@mcp.error_response(id=request.id, error))
      } noraise {
        response => response
      }
  }
}
