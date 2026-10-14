///|
/// The "On this page" rail: the `h2` and `h3` headings. A page with fewer than two
/// such headings gets no rail.
pub fn toc_entries(
  headings : Array[@content.Heading],
) -> Array[@model.TocEntry] {
  let entries = headings
    .filter(h => h.level == 2 || h.level == 3)
    .map(h => @model.TocEntry::{ id: h.id, text: h.text, depth: h.level - 2, })
  if entries.length() < 2 {
    []
  } else {
    entries
  }
}
