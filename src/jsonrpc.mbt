///|
fn McpError::to_rpc_error(self : McpError) -> @jsonrpc.RpcError {
  @jsonrpc.RpcError(code=self.code(), message=self.message())
}

///|
fn dispatch_jsonrpc_result(
  server : Server,
  method_name : String,
  params : Json?,
) -> Json raise @jsonrpc.RpcError {
  try server.dispatch(method_name, params) catch {
    error => raise error.to_rpc_error()
  } noraise {
    result =>
      match result {
        Some(result) => result
        None =>
          raise InvalidRequest("request method returned no result").to_rpc_error()
      }
  }
}

///|
fn Server::jsonrpc_endpoint(self : Server) -> @jsonrpc.Endpoint {
  try! @jsonrpc.EndpointBuilder()
  .handle("initialize", fn(params) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "initialize", params)
  })
  .handle("notifications/initialized", fn(
    params,
  ) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "notifications/initialized", params)
  })
  .handle("notifications/cancelled", fn(
    params,
  ) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "notifications/cancelled", params)
  })
  .handle("ping", fn(params) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "ping", params)
  })
  .handle("logging/setLevel", fn(params) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "logging/setLevel", params)
  })
  .handle("tools/list", fn(params) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "tools/list", params)
  })
  .handle("tools/call", fn(params) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "tools/call", params)
  })
  .handle("resources/list", fn(params) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "resources/list", params)
  })
  .handle("resources/templates/list", fn(
    params,
  ) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "resources/templates/list", params)
  })
  .handle("resources/read", fn(params) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "resources/read", params)
  })
  .handle("resources/subscribe", fn(params) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "resources/subscribe", params)
  })
  .handle("resources/unsubscribe", fn(params) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "resources/unsubscribe", params)
  })
  .handle("prompts/list", fn(params) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "prompts/list", params)
  })
  .handle("prompts/get", fn(params) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "prompts/get", params)
  })
  .handle("completion/complete", fn(params) -> Json raise @jsonrpc.RpcError {
    dispatch_jsonrpc_result(self, "completion/complete", params)
  })
  .build()
}

///|
/// Handle one JSON-RPC message for transport implementations.
pub async fn Server::handle_jsonrpc(self : Server, message : Json) -> Json? {
  let received = self.jsonrpc_endpoint().receive_json(message)
  match received.outgoing {
    [response] => Some(response)
    [] => None
    responses => Some(@jsonrpc.batch(responses))
  }
}
