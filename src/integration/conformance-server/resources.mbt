///|
fn register_resource_fixtures(server : @mcp.Server) -> Unit {
  try! server.simple_resource(
    uri="test://static-text",
    name="Static text resource",
    description="Deterministic UTF-8 text used by conformance checks.",
    mime_type="text/plain",
    fn(uri) {
      @mcp.ReadResourceResult::text(
        uri~,
        text="This is the content of the static text resource.",
        mime_type="text/plain",
      )
    },
  )
  try! server.resource(
    uri="test://static-binary",
    name="Static binary resource",
    description="Deterministic PNG bytes encoded as base64.",
    mime_type="image/png",
    fn(_context, uri) {
      @mcp.Complete({
        contents: [
          @mcp.ResourceContent::blob(
            uri~,
            blob=pixel_png,
            mime_type="image/png",
          ),
        ],
      })
    },
  )
  try! server.resource_template(
    uri_template="test://template/{id}/data",
    name="Parameterized data resource",
    description="Substitute the id captured from the requested URI.",
    mime_type="application/json",
    fn(_context, uri, captures) {
      let id = captures.get("id").unwrap_or("")
      @mcp.Complete(
        @mcp.ReadResourceResult::text(
          uri~,
          text="{\"id\":\"\{id}\",\"templateTest\":true,\"data\":\"Data for ID: \{id}\"}",
          mime_type="application/json",
        ),
      )
    },
  )
}
