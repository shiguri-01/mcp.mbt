///|
async fn main {
  let http_server = @async_http.Server(@socket.Addr::parse("127.0.0.1:8080"))
  let server = make_conformance_server()
  println("MCP conformance endpoint: http://127.0.0.1:8080/mcp")
  @mcp_http.serve(
    http_server,
    server,
    options=@mcp_http.ServerOptions(endpoint_path="/mcp", stream_responses=true),
  )
}

///|
fn make_conformance_server() -> @mcp_server.Server {
  let builder = try! @mcp_server.ServerBuilder(
    name="moonbit-mcp-conformance-fixture",
    version="2026.7.28",
    instructions="Deterministic fixture for the frozen MCP 2026-07-28 server conformance requirements.",
    cache_policy=@mcp.CachePolicy(ttl_ms=0L),
  )
  register_tool_fixtures(builder)
  register_resource_fixtures(builder)
  register_prompt_fixtures(builder)
  register_completion_fixture(builder)
  register_stateless_diagnostics(builder)
  register_mrtr_fixtures(builder)
  builder.build()
}
