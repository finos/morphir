///|
test "the contents rail lists h2 and h3 headings" {
  let toc = @site.toc_entries([
    @content.Heading::{ level: 1, id: "title", text: "Title", },
    @content.Heading::{ level: 2, id: "overview", text: "Overview", },
    @content.Heading::{ level: 3, id: "details", text: "Details", },
    @content.Heading::{ level: 4, id: "deep", text: "Deep", },
    @content.Heading::{ level: 2, id: "usage", text: "Usage", },
  ])
  assert_eq(toc.map(e => (e.id, e.text, e.depth)), [
    ("overview", "Overview", 0),
    ("details", "Details", 1),
    ("usage", "Usage", 0),
  ])
}

///|
test "a page with fewer than two entries has no contents rail" {
  assert_eq(
    @site.toc_entries([
      @content.Heading::{ level: 1, id: "title", text: "Title", },
      @content.Heading::{ level: 2, id: "only", text: "Only", },
    ]).length(),
    0,
  )
}
