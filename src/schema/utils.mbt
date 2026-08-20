///|
fn Map::get_number(self : Map[String, Json], key : String) -> Double? {
  guard self.get(key) is Some(Number(n, ..)) else { None }
  Some(n)
}

///|
fn Map::get_string(self : Map[String, Json], key : String) -> String? {
  guard self.get(key) is Some(String(s)) else { None }
  Some(s)
}

///|
fn[K : Eq + Hash, V, V2] Map::map_raise(
  self : Map[K, V],
  f : (K, V) -> V2 raise?,
) -> Map[K, V2] raise? {
  [ for k, v in self => (k, f(k, v)) ] |> Map::from_array
}

///|
fn[T, T2] Array::map_raise(
  self : Array[T],
  f : (T) -> T2 raise?,
) -> Array[T2] raise? {
  [
    for x in self => f(x)
  ]
}
