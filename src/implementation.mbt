///|
/// MCP implementation metadata advertised during `initialize`.
pub(all) struct Implementation {
  name : String
  version : String
} derive(Debug, Eq)

///|
pub impl ToJson for Implementation with fn to_json(self : Implementation) -> Json {
  Json::object({
    "name": Json::string(self.name),
    "version": Json::string(self.version),
  })
}
