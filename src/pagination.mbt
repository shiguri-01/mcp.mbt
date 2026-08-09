///|
struct Page[T] {
  items : Array[T]
  next_cursor : String?
} derive(Debug, Eq)

///|
fn[T] Page::Page(items~ : Array[T], next_cursor? : String) -> Page[T] {
  { items, next_cursor }
}

///|
fn parse_cursor(cursor : String?, total : Int) -> Int raise McpError {
  match cursor {
    None => 0
    Some(cursor) => {
      let mut offset = 0
      // Empty strings are valid opaque cursors in MCP. This implementation
      // treats one as the beginning of the deterministic registry order.
      if cursor.length() == 0 {
        return 0
      }
      for c in cursor {
        if c < '0' || c > '9' {
          raise InvalidParams(
            "cursor must be an opaque cursor returned by the server",
          )
        }
        offset = offset * 10 + (c.to_int() - '0'.to_int())
      }
      if offset < 0 || offset > total {
        raise InvalidParams("cursor is out of range")
      }
      offset
    }
  }
}

///|
fn[T] paginate(
  items : Array[T],
  cursor? : String,
  page_size? : Int = 100,
) -> Page[T] raise McpError {
  let total = items.length()
  let start = parse_cursor(cursor, total)
  let limit = if page_size <= 0 { total } else { page_size }
  let stop = if start + limit < total { start + limit } else { total }
  let page = Array::makei(stop - start, fn(i) { items[start + i] })
  let next_cursor = if stop < total { Some("\{stop}") } else { None }
  Page(items=page, next_cursor?)
}
