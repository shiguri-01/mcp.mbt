///|
test "content blocks encode annotations meta and resources" {
  let annotations = @mcp.Annotations(
    audience=[@mcp.Role::User, @mcp.Role::Assistant],
    priority=0.75,
    last_modified="2026-05-26T00:00:00Z",
  )
  let text = @mcp.ContentBlock::text(
    "hello",
    annotations~,
    meta=Json::object({ "source": Json::string("test") }),
  ).to_json()
  guard text is Object(text_fields) else { fail("expected text content") }
  assert_true(text_fields["type"] == Json::string("text"))
  guard text_fields["annotations"] is Object(text_annotations) else {
    fail("expected text annotations")
  }
  assert_true(text_annotations["priority"] == Json::number(0.75))
  assert_true(
    text_fields["_meta"] == Json::object({ "source": Json::string("test") }),
  )

  let embedded = @mcp.ContentBlock::embedded_resource(
    resource=@mcp.ResourceContent::text(
      uri="memory://status",
      text="ready",
      mime_type="text/plain",
      meta=Json::object({ "etag": Json::string("abc") }),
    ),
  ).to_json()
  guard embedded
    is Object({ "type": String("resource"), "resource": Object(resource), .. }) else {
    fail("expected embedded resource")
  }
  assert_true(resource["text"] == Json::string("ready"))
  assert_true(
    resource["_meta"] == Json::object({ "etag": Json::string("abc") }),
  )

  let link = @mcp.ContentBlock::resource_link(
    @mcp.ResourceLink(
      uri="file:///tmp/report.md",
      name="report",
      title="Report",
      description="Generated report",
      mime_type="text/markdown",
      icons=[
        @mcp.Icon(src="data:image/png;base64,AA==", theme=@mcp.IconTheme::Dark),
      ],
      annotations~,
      size=2048,
      meta=Json::object({ "kind": Json::string("artifact") }),
    ),
  ).to_json()
  guard link is Object(link_fields) else { fail("expected resource link") }
  assert_true(link_fields["type"] == Json::string("resource_link"))
  assert_true(link_fields["uri"] == Json::string("file:///tmp/report.md"))
  assert_true(link_fields["size"] == Json::number(2048.0, repr="2048"))
  guard link_fields["icons"] is Array([Object(icon)]) else {
    fail("expected icon")
  }
  assert_true(icon["theme"] == Json::string("dark"))
}
