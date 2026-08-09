///|
pub fn cancelled_notification(
  request_id~ : Json,
  reason? : String,
) -> Json raise McpError {
  if !(request_id is (String(_) | Number(_))) {
    raise InvalidParams(
      "cancelled notification requestId must be a string or number",
    )
  }
  let params : Map[String, Json] = { "requestId": request_id }
  put_optional_string(params, "reason", reason)
  jsonrpc_notification("notifications/cancelled", params=Json::object(params))
}

///|
pub fn progress_notification(
  progress_token~ : Json,
  progress~ : Double,
  total? : Double,
  message? : String,
) -> Json raise McpError {
  ignore(parse_progress_token(progress_token, "progress notification"))
  let params : Map[String, Json] = {
    "progressToken": progress_token,
    "progress": Json::number(progress),
  }
  match total {
    Some(total) => params["total"] = Json::number(total)
    None => ()
  }
  put_optional_string(params, "message", message)
  jsonrpc_notification("notifications/progress", params=Json::object(params))
}

///|
pub fn tools_list_changed_notification(subscription_id~ : Json) -> Json {
  jsonrpc_notification(
    "notifications/tools/list_changed",
    params=subscription_params(subscription_id),
  )
}

///|
fn subscription_notification_meta(subscription_id : Json) -> Json {
  Json::object({ "io.modelcontextprotocol/subscriptionId": subscription_id })
}

///|
fn subscription_params(subscription_id : Json) -> Json {
  Json::object({ "_meta": subscription_notification_meta(subscription_id) })
}

///|
pub fn resources_list_changed_notification(subscription_id~ : Json) -> Json {
  jsonrpc_notification(
    "notifications/resources/list_changed",
    params=subscription_params(subscription_id),
  )
}

///|
/// Build a `notifications/resources/updated` notification for one URI.
pub fn resource_updated_notification(
  uri~ : String,
  subscription_id~ : Json,
) -> Json {
  let params : Map[String, Json] = { "uri": Json::string(uri) }
  params["_meta"] = subscription_notification_meta(subscription_id)
  jsonrpc_notification(
    "notifications/resources/updated",
    params=Json::object(params),
  )
}

///|
pub fn prompts_list_changed_notification(subscription_id~ : Json) -> Json {
  jsonrpc_notification(
    "notifications/prompts/list_changed",
    params=subscription_params(subscription_id),
  )
}
