///|
test "nav is a tree: leaves and directories sorted by order then title" {
  let nav = @site.build_nav([
    entry("QUICK_START.md", "Quick start", order=1),
    entry("ARCHITECTURE.md", "Architecture"),
    entry("adr/README.md", "Decision records", order=2),
    entry("adr/0002-b.md", "B"),
    entry("adr/0001-a.md", "A"),
    entry("packages/morphir-ir/README.md", "morphir-ir"),
  ])
  assert_eq(nav.map(n => (n.route, n.title, n.depth)), [
    ("/docs/quick_start/", "Quick start", 0),
    ("/docs/adr/", "Decision records", 0),
    ("/docs/adr/0001-a/", "A", 1),
    ("/docs/adr/0002-b/", "B", 1),
    ("/docs/architecture/", "Architecture", 0),
    ("", "Packages", 0),
    ("/docs/packages/morphir-ir/", "morphir-ir", 1),
  ])
}

///|
fn entry(
  source : String,
  title : String,
  order? : Int = 1000,
) -> @site.NavEntry {
  { route: @model.doc_route(source), source, title, order, }
}

///|
let site_pages : Array[@site.NavEntry] = [
  entry("QUICK_START.md", "Quick start"),
  entry("ARCHITECTURE.md", "Architecture"),
  entry("MISE_TASKS.md", "Mise tasks"),
  entry("WRITING_GUIDE.md", "Writing guide", order=1),
  entry("adr/README.md", "Decision records"),
  entry("adr/0002-b.md", "B"),
  entry("adr/0001-a.md", "A"),
  entry("packages/morphir-ir/README.md", "morphir-ir"),
  entry("packages/morphir-elm/README.md", "morphir-elm"),
]

///|
fn rows(nav : Array[@model.NavItem]) -> Array[(String, Int)] {
  nav.map(n => (n.title, n.depth))
}

///|
test "groups list their items in order under a label" {
  let (nav, problems) = @site.build_grouped_nav(
    [
      { group: "Start", items: ["QUICK_START.md", "ARCHITECTURE.md"], },
      { group: "Packages", items: ["packages/"], },
      { group: "Decisions", items: ["adr/"], },
      { group: "More", items: ["MISE_TASKS.md", "WRITING_GUIDE.md"], },
    ],
    site_pages,
  )
  assert_eq(problems, [])
  assert_eq(rows(nav), [
    ("Start", 0),
    ("Quick start", 0),
    ("Architecture", 0),
    ("Packages", 0),
    ("morphir-elm", 0),
    ("morphir-ir", 0),
    ("Decisions", 0),
    ("Decision records", 0),
    ("A", 1),
    ("B", 1),
    ("More", 0),
    ("Mise tasks", 0),
    ("Writing guide", 0),
  ])
  assert_eq(nav[0].route, "")
  assert_eq(nav[1].route, "/docs/quick_start/")
}

///|
test "exact items win over earlier patterns; a catch-all takes the rest" {
  let (nav, problems) = @site.build_grouped_nav(
    [
      { group: "Pages", items: ["*.md"], },
      { group: "Start", items: ["QUICK_START.md"], },
      { group: "Sections", items: ["*/"], },
    ],
    site_pages,
  )
  assert_eq(problems, [])
  assert_eq(rows(nav), [
    ("Pages", 0),
    ("Writing guide", 0),
    ("Architecture", 0),
    ("Mise tasks", 0),
    ("Start", 0),
    ("Quick start", 0),
    ("Sections", 0),
    ("Decision records", 0),
    ("A", 1),
    ("B", 1),
    ("morphir-elm", 0),
    ("morphir-ir", 0),
  ])
}

///|
test "a pattern without matches hides its group; ? matches one character" {
  let (nav, problems) = @site.build_grouped_nav(
    [
      { group: "Guides", items: ["*_GUIDE.md"], },
      { group: "Nothing", items: ["NOPE*.md", "NOPE*/"], },
      { group: "Docs", items: ["????????????.md", "*.md", "*/"], },
    ],
    site_pages,
  )
  assert_eq(problems, [])
  assert_eq(rows(nav).map(r => r.0)[:4].to_array(), [
    "Guides", "Writing guide", "Docs", "Architecture",
  ])
  assert_false(rows(nav).map(r => r.0).contains("Nothing"))
}

///|
test "unlisted pages and exact items without a page are problems" {
  let (_, problems) = @site.build_grouped_nav(
    [
      { group: "Start", items: ["QUICK_START.md", "MISSING.md", "gone/"], },
      { group: "Empty", items: ["*_NOTHING.md"], },
    ],
    site_pages,
  )
  assert_eq(problems, [
    "`nav` entry `MISSING.md` matches no page", "`nav` entry `gone/` matches no page",
    "docs page `ARCHITECTURE.md` is not in `nav`", "docs page `MISE_TASKS.md` is not in `nav`",
    "docs page `WRITING_GUIDE.md` is not in `nav`", "docs directory `adr/` is not in `nav`",
    "docs directory `packages/` is not in `nav`",
  ])
}

///|
test "globs never match across a slash" {
  assert_true(@site.glob_match("*.md", "A.md"))
  assert_false(@site.glob_match("*.md", "adr/A.md"))
  assert_true(@site.glob_match("*/", "adr/"))
  assert_false(@site.glob_match("*", "adr/"))
  assert_true(@site.glob_match("A?C.md", "ABC.md"))
  assert_false(@site.glob_match("A?C.md", "AC.md"))
  assert_true(@site.glob_match("**.md", "A.md"))
}

///|
test "HTML pages are top-level entries too" {
  let (nav, problems) = @site.build_grouped_nav(
    [{ group: "All", items: ["*.html", "*.md", "*/"], }],
    site_pages + [entry("GUIDE.html", "Guide")],
  )
  assert_eq(problems, [])
  assert_eq(rows(nav).map(r => r.0)[:2].to_array(), ["All", "Guide"])
}
