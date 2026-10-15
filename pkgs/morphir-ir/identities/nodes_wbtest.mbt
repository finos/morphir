///|
fn collect_error(value : Json) -> String {
  try {
    collect("unit:u/ir", value, Map([]))
    ""
  } catch {
    @codec_boundary.Invalid(code, message) => code + ": " + message
    error => error.to_string()
  }
}

///|
test "the identity limits name the limit that a tree exceeds" {
  let mut deep : Json = Json::null()
  for _ in 0..<MAX_DEPTH {
    deep = Json::array([deep])
  }
  assert_eq(collect_error(deep), "")
  assert_eq(
    collect_error(Json::array([deep])),
    "identity.tree_limit: Identity depth exceeds the limit of 128",
  )
  let wide = Json::array(Array::make(MAX_NODES + 1, Json::null()))
  assert_eq(
    collect_error(wide),
    "identity.tree_limit: Identity node count exceeds the limit of 100000",
  )
}
