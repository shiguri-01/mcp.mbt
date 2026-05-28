///|
pub fn cancelled_notification(request_id? : Json, reason? : String) -> Json {
  let params : Map[String, Json] = {}
  put_optional_json(params, "requestId", request_id)
  put_optional_string(params, "reason", reason)
  jsonrpc_notification("notifications/cancelled", params=Json::object(params))
}

///|
pub fn progress_notification(
  progress_token~ : Json,
  progress~ : Double,
  total? : Double,
  message? : String,
) -> Json {
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
pub fn tools_list_changed_notification() -> Json {
  jsonrpc_notification("notifications/tools/list_changed")
}

///|
pub fn resources_list_changed_notification() -> Json {
  jsonrpc_notification("notifications/resources/list_changed")
}

///|
/// Build a `notifications/resources/updated` notification for one URI.
pub fn resource_updated_notification(uri~ : String) -> Json {
  jsonrpc_notification(
    "notifications/resources/updated",
    params=Json::object({ "uri": Json::string(uri) }),
  )
}

///|
pub fn prompts_list_changed_notification() -> Json {
  jsonrpc_notification("notifications/prompts/list_changed")
}
