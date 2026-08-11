///|
fn register_prompt_fixtures(server : @mcp.Server) -> Unit {
  try! server.simple_prompt(
    name="test_simple_prompt",
    description="Return one user text message.",
    fn(_arguments) {
      @mcp.GetPromptResult::user("This is a simple prompt for testing.")
    },
  )
  try! server.simple_prompt(
    name="test_prompt_with_arguments",
    description="Include both required arguments in the returned prompt.",
    arguments=[
      @mcp.PromptArgument(name="arg1", required=true),
      @mcp.PromptArgument(name="arg2", required=true),
    ],
    fn(arguments) {
      let arg1 = arguments.get("arg1").unwrap_or("")
      let arg2 = arguments.get("arg2").unwrap_or("")
      @mcp.GetPromptResult::user(
        "Prompt with arguments: arg1='\{arg1}', arg2='\{arg2}'",
      )
    },
  )
  try! server.prompt(
    name="test_prompt_with_embedded_resource",
    description="Embed the resource URI supplied by the caller.",
    arguments=[@mcp.PromptArgument(name="resourceUri", required=true)],
    fn(_context, arguments) {
      let uri = arguments.get("resourceUri").unwrap_or("")
      @mcp.Complete({
        description: None,
        messages: [
          @mcp.PromptMessage(
            role=@mcp.Role::User,
            content=@mcp.ContentBlock::embedded_resource(
              resource=@mcp.ResourceContent::text(
                uri~,
                text="Embedded resource content for testing.",
                mime_type="text/plain",
              ),
            ),
          ),
          @mcp.PromptMessage::user(
            "Please process the embedded resource above.",
          ),
        ],
      })
    },
  )
  try! server.prompt(
    name="test_prompt_with_image",
    description="Return image content followed by a text instruction.",
    fn(_context, _arguments) {
      @mcp.Complete({
        description: None,
        messages: [
          @mcp.PromptMessage(
            role=@mcp.Role::User,
            content=@mcp.ContentBlock::image(
              data=pixel_png,
              mime_type="image/png",
            ),
          ),
          @mcp.PromptMessage::user("Please analyze the image above."),
        ],
      })
    },
  )
}

///|
fn register_completion_fixture(server : @mcp.Server) -> Unit {
  try! server.completion(
    reference=@mcp.CompletionReference::prompt(
      name="test_prompt_with_arguments",
    ),
    (_context, request) => {
      let prefix = request.argument_value
      let candidates = ["paris", "park", "party"]
      @mcp.CompleteResult(
        values=candidates.filter(fn(value) { value.has_prefix(prefix) }),
        total=3,
        has_more=false,
      )
    },
  )
}
