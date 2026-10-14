///|
test "nav is a tree: leaves and directories sorted by order then title" {
  let nav = @site.build_nav([
    { route: "/docs/quick-start/", title: "Quick start", order: 1, },
    { route: "/docs/architecture/", title: "Architecture", order: 1000, },
    { route: "/docs/adr/", title: "Decision records", order: 2, },
    { route: "/docs/adr/0002-b/", title: "B", order: 1000, },
    { route: "/docs/adr/0001-a/", title: "A", order: 1000, },
    { route: "/docs/packages/morphir-ir/", title: "morphir-ir", order: 1000, },
  ])
  assert_eq(nav.map(n => (n.route, n.title, n.depth)), [
    ("/docs/quick-start/", "Quick start", 0),
    ("/docs/adr/", "Decision records", 0),
    ("/docs/adr/0001-a/", "A", 1),
    ("/docs/adr/0002-b/", "B", 1),
    ("/docs/architecture/", "Architecture", 0),
    ("", "Packages", 0),
    ("/docs/packages/morphir-ir/", "morphir-ir", 1),
  ])
}
