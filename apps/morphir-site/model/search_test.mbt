///|
fn entry(
  route : String,
  title : String,
  headings : Array[String],
  text : String,
) -> @model.SearchEntry {
  { route, title, section: "Docs", summary: "", headings, text, }
}

///|
let entries : Array[@model.SearchEntry] = [
  entry("/docs/a/", "Architecture", ["Packages"], "the scheme engine"),
  entry("/docs/b/", "Quick start", ["Architecture notes"], "install mise"),
  entry("/docs/c/", "Tasks", [], "architecture of tasks and adr records"),
]

///|
test "title beats heading beats text" {
  assert_eq(@model.search(entries, "arch").map(e => e.route), [
    "/docs/a/", "/docs/b/", "/docs/c/",
  ])
}

///|
test "all tokens must match, case-insensitive prefixes" {
  assert_eq(@model.search(entries, "ARCH ADR").map(e => e.route), ["/docs/c/"])
  assert_eq(@model.search(entries, "zzz"), [])
}

///|
test "blank query and limit" {
  assert_eq(@model.search(entries, "   "), [])
  assert_eq(@model.search(entries, "arch", limit=1).length(), 1)
}

///|
test "search entry json round trip" {
  let e = entries[0]
  assert_eq(@model.SearchEntry::from_json(e.to_json()), Some(e))
  assert_eq(@model.SearchEntry::from_json(Json::null()), None)
}
