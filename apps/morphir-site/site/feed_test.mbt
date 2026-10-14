///|
fn post(slug : String, date : String) -> @site.Page {
  {
    source: "site/blog/\{date}-\{slug}.md",
    route: "/blog/\{slug}/",
    kind: Post("\{date}-\{slug}.md"),
    title: "Post <\{slug}>",
    summary: "S & T",
    date,
    authors: ["Zoë"],
    order: 1000,
    full: false,
    html: "<p>a &amp; b</p>",
    ids: [],
    headings: ["H"],
    text: "a & b",
    mermaid: false,
  }
}

///|
test "atom feed is newest first and escaped" {
  let feed = @site.atom_feed(config, [
    post("old", "2026-01-01"),
    post("new", "2026-10-13"),
  ])
  assert_true(
    feed.has_prefix(
      "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<feed xmlns=\"http://www.w3.org/2005/Atom\">",
    ),
  )
  assert_true(feed.contains("<updated>2026-10-13T00:00:00Z</updated>"))
  let newest = feed.find("Post &lt;new&gt;").unwrap()
  let oldest = feed.find("Post &lt;old&gt;").unwrap()
  assert_true(newest < oldest)
  assert_true(feed.contains("<id>https://x.io/m/blog/new/</id>"))
  assert_true(feed.contains("<name>Zoë</name>"))
  assert_true(
    feed.contains(
      "<content type=\"html\">&lt;p&gt;a &amp;amp; b&lt;/p&gt;</content>",
    ),
  )
  assert_true(feed.has_suffix("</feed>\n"))
}

///|
test "empty feed has a fixed updated date" {
  assert_true(
    @site.atom_feed(config, []).contains(
      "<updated>1970-01-01T00:00:00Z</updated>",
    ),
  )
}

///|
test "search index lists pages with trimmed text" {
  let long = { ..post("x", "2026-10-13"), text: "w".repeat(3000), }
  let json = @json.parse(@site.search_index([long])) catch { _ => Json::null() }
  guard json is Array([Object(entry)]) else { fail("expected one entry") }
  assert_eq(entry.get("route"), Some(Json::string("/blog/x/")))
  assert_eq(entry.get("section"), Some(Json::string("Blog")))
  guard entry.get("text") is Some(String(text)) else { fail("no text") }
  assert_eq(text.length(), 2000)
}
