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

///|
test "JSON pointer parts escape a tilde and a slash, and keep other text" {
  assert_eq(part("plain-name"), "plain-name")
  assert_eq(part("a~b/c"), "a~0b~1c")
  assert_eq(part("~/"), "~0~1")
}

///|
test "the node set has the identities of nodes, also from the caller's JSON" {
  let file = @ir_json.from_json(
    @codec_boundary.parse(
      "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"generated\",\"dependencies\":{},\"def\":{\"modules\":{\"main\":{\"Public\":{\"types\":{},\"values\":{\"answer\":{\"Public\":{\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":\"morphir/SDK:basics#int\",\"body\":{\"Literal\":{\"IntegerLiteral\":42}}}}}}}}}}}}}",
    ),
  )
  let sorted = nodes("u", file)
  assert_true(sorted.contains("value:generated:main#answer/body"))
  for
    set in [
      node_set("u", file),
      node_set("u", file, json=@ir_json.to_json(file)),
    ] {
    let keys = set.keys().collect()
    keys.sort()
    assert_eq(keys, sorted)
  }
}
