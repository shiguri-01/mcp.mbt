///|
let pixel_png : String = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z4x8AAAAASUVORK5CYII="

///|
let silent_wav : String = "UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="

///|
fn register_tool_fixtures(server : @mcp.Server) -> Unit {
  try! server.json_tool(
    name="test_simple_text",
    description="Return one deterministic text content block.",
    input_schema=empty_object_schema(),
    fn(_context, _arguments) {
      @mcp.Complete(
        @mcp.CallToolResult::text("This is a simple text response for testing."),
      )
    },
  )
  try! server.json_tool(
    name="test_image_content",
    description="Return a minimal PNG image content block.",
    input_schema=empty_object_schema(),
    fn(_context, _arguments) {
      @mcp.Complete({
        content: [
          @mcp.ContentBlock::image(data=pixel_png, mime_type="image/png"),
        ],
        structured_content: None,
        is_error: false,
      })
    },
  )
  try! server.json_tool(
    name="test_audio_content",
    description="Return a minimal WAV audio content block.",
    input_schema=empty_object_schema(),
    fn(_context, _arguments) {
      @mcp.Complete({
        content: [
          @mcp.ContentBlock::audio(data=silent_wav, mime_type="audio/wav"),
        ],
        structured_content: None,
        is_error: false,
      })
    },
  )
  try! server.json_tool(
    name="test_embedded_resource",
    description="Return one embedded text resource.",
    input_schema=empty_object_schema(),
    fn(_context, _arguments) {
      @mcp.Complete({
        content: [
          @mcp.ContentBlock::embedded_resource(
            resource=@mcp.ResourceContent::text(
              uri="test://embedded-resource",
              text="This is an embedded resource content.",
              mime_type="text/plain",
            ),
          ),
        ],
        structured_content: None,
        is_error: false,
      })
    },
  )
  try! server.json_tool(
    name="test_multiple_content_types",
    description="Return text, image, and embedded resource content together.",
    input_schema=empty_object_schema(),
    fn(_context, _arguments) {
      @mcp.Complete({
        content: [
          @mcp.ContentBlock::text("Multiple content types test:"),
          @mcp.ContentBlock::image(data=pixel_png, mime_type="image/png"),
          @mcp.ContentBlock::embedded_resource(
            resource=@mcp.ResourceContent::text(
              uri="test://mixed-content-resource",
              text="{\"test\":\"data\",\"value\":123}",
              mime_type="application/json",
            ),
          ),
        ],
        structured_content: None,
        is_error: false,
      })
    },
  )
  try! server.json_tool(
    name="test_error_handling",
    description="Return an application-level tool error result.",
    input_schema=empty_object_schema(),
    fn(_context, _arguments) {
      @mcp.Complete(
        @mcp.CallToolResult::error_text(
          "This tool intentionally returns an error for testing",
        ),
      )
    },
  )
  try! server.json_tool(
    name="test_tool_with_progress",
    description="Report monotonic progress before returning text.",
    input_schema=empty_object_schema(),
    async fn(
      context,
      _arguments,
    ) -> @mcp.HandlerOutcome[@mcp.CallToolResult] raise @mcp.McpError {
      context.report_progress(progress=0.0, total=100.0)
      context.report_progress(progress=50.0, total=100.0)
      context.report_progress(progress=100.0, total=100.0)
      @mcp.Complete(@mcp.CallToolResult::text("Progress test completed"))
    },
  )
}
