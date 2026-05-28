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

///|
test "resource descriptors encode annotations icons and size" {
  let annotations = @mcp.Annotations(audience=[@mcp.Role::Assistant])
  let icon = @mcp.Icon(
    src="data:image/svg+xml;base64,AA==",
    theme=@mcp.IconTheme::Light,
  )
  let resource = @mcp.Resource(
    uri="memory://report",
    name="report",
    title="Report",
    description="Generated report",
    mime_type="text/markdown",
    icons=[icon],
    annotations~,
    size=4096,
    meta=Json::object({ "owner": Json::string("test") }),
  ).to_json()
  guard resource is Object(resource_fields) else {
    fail("expected resource descriptor")
  }
  assert_true(resource_fields["uri"] == Json::string("memory://report"))
  assert_true(resource_fields["size"] == Json::number(4096.0, repr="4096"))
  guard resource_fields["icons"] is Array([Object(resource_icon)]) else {
    fail("expected resource icon")
  }
  assert_true(resource_icon["theme"] == Json::string("light"))
  guard resource_fields["annotations"] is Object(resource_annotations) else {
    fail("expected resource annotations")
  }
  assert_true(resource_annotations.contains("audience"))
  assert_true(
    resource_fields["_meta"] == Json::object({ "owner": Json::string("test") }),
  )

  let template = @mcp.ResourceTemplate(
    uri_template="memory://reports/{id}",
    name="report-template",
    title="Report template",
    description="Reports by id",
    mime_type="text/markdown",
    icons=[icon],
    annotations~,
    meta=Json::object({ "templated": Json::boolean(true) }),
  ).to_json()
  guard template is Object(template_fields) else {
    fail("expected resource template")
  }
  assert_true(
    template_fields["uriTemplate"] == Json::string("memory://reports/{id}"),
  )
  guard template_fields["icons"] is Array([Object(template_icon)]) else {
    fail("expected template icon")
  }
  assert_true(template_icon["theme"] == Json::string("light"))
  guard template_fields["annotations"] is Object(_) else {
    fail("expected template annotations")
  }
  assert_true(
    template_fields["_meta"] ==
    Json::object({ "templated": Json::boolean(true) }),
  )
}
