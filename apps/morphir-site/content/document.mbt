///|
pub(all) struct Heading {
  level : Int
  id : String
  text : String
} derive(Eq, Debug)

///|
pub extend Heading with Eq::{equal, not_equal}

///|
pub extend Heading with @debug.Debug::{to_repr}

///|
/// An HTML body with the facts the site needs from it.
pub(all) struct Document {
  html : String
  title : String?
  summary : String
  headings : Array[Heading]
  ids : Array[String]
  text : String
}

///|
/// Render CommonMark with tables, strikethrough and task lists to HTML, then add
/// heading anchors and collect the document facts. Raw HTML is kept, because site
/// content is reviewed in pull requests.
pub fn render_markdown(
  file : String,
  source : String,
) -> Document raise @model.Invalid {
  let html = @cmark_html.render(safe=false, strict=false, source) catch {
    error =>
      raise @model.Invalid([
        @model.problem(file, "Markdown does not render: \{error}"),
      ])
  }
  analyse_html(html)
}

///|
/// Add an `id` to each `<h1>`..`<h6>` start tag that has no attributes, then
/// collect the title (first `h1`), summary (first paragraph), headings, ids and text.
pub fn analyse_html(source : String) -> Document {
  let out = StringBuilder()
  let headings : Array[Heading] = []
  let used : Map[String, Bool] = Map([])
  for existing in ids_in(source) {
    used.set(existing, true)
  }
  let mut rest = source[:]
  while rest.find("<h") is Some(start) {
    let after = rest[start:]
    let level = if after.length() >= 4 &&
      after[3] == '>' &&
      after[2] >= '1' &&
      after[2] <= '6' {
      after[2].to_int() - '0'.to_int()
    } else {
      0
    }
    if level == 0 {
      out.write_view(rest[:start + 2])
      rest = rest[start + 2:]
      continue
    }
    let close = "</h\{level}>"
    guard after.find(close) is Some(end) else { break }
    let inner = after[4:end].to_owned()
    let text = inline_text(inner)
    let id = unique_id(slug(text), used)
    used.set(id, true)
    headings.push({ level, id, text, })
    out.write_view(rest[:start])
    out.write_string("<h\{level} id=\"\{id}\">\{inner}\{close}")
    rest = after[end + close.length():]
  }
  out.write_view(rest)
  let html = out.to_string()
  let title = headings.search_by(h => h.level == 1).map(i => headings[i].text)
  let summary = match html.find("<p>") {
    Some(start) =>
      match html[start:].find("</p>") {
        Some(end) => plain_text(html[start + 3:start + end].to_owned())
        None => ""
      }
    None => ""
  }
  { html, title, summary, headings, ids: ids_in(html), text: plain_text(html), }
}

///|
/// `base` if no id uses it yet, otherwise the first `base-n` (n >= 2) that is free.
fn unique_id(base : String, used : Map[String, Bool]) -> String {
  if !used.contains(base) {
    return base
  }
  let mut n = 2
  while used.contains("\{base}-\{n}") {
    n += 1
  }
  "\{base}-\{n}"
}

///|
/// Every `id="..."` attribute value in `html`, in document order.
pub fn ids_in(html : String) -> Array[String] {
  let ids = []
  let mut rest = html[:]
  while rest.find(" id=\"") is Some(start) {
    let value = rest[start + 5:]
    match value.find("\"") {
      Some(end) => {
        ids.push(value[:end].to_owned())
        rest = value[end + 1:]
      }
      None => rest = ""
    }
  }
  ids
}
