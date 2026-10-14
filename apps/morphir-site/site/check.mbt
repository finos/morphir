///|
fn attribute_values(html : String) -> Array[String] {
  let values = []
  ignore(
    @content.map_urls(html, url => {
      values.push(url)
      url
    }),
  )
  values
}

///|
fn title_ok(html : String) -> Bool {
  match html.find("<title>") {
    Some(start) =>
      match html[start:].find("</title>") {
        Some(end) => html[start + 7:start + end].trim() != ""
        None => false
      }
    None => false
  }
}

///|
/// Check that tags in an XML document are balanced. Returns a message or None.
fn xml_problem(xml : String) -> String? {
  let stack : Array[String] = []
  let mut rest = xml[:]
  while rest.find("<") is Some(start) {
    let tag = rest[start:]
    guard tag.find(">") is Some(end) else { return Some("unclosed `<`") }
    let body = tag[1:end].to_owned()
    rest = tag[end + 1:]
    if body.has_prefix("?") || body.has_prefix("!") || body.has_suffix("/") {
      continue
    }
    let name = match body.find(" ") {
      Some(i) => body[:i].to_owned()
      None => body
    }
    if name.has_prefix("/") {
      let closing = name[1:].to_owned()
      match stack.pop() {
        Some(open) if open == closing => ()
        Some(open) => return Some("`</\{closing}>` closes `<\{open}>`")
        None => return Some("`</\{closing}>` has no start tag")
      }
    } else {
      stack.push(name)
    }
  }
  if stack.is_empty() {
    None
  } else {
    Some("`<\{stack[stack.length() - 1]}>` is not closed")
  }
}

///|
/// Check a built site: internal links resolve, pages have titles, the feed is
/// well-formed, and no file is under a forbidden path.
pub fn check_site(
  base : String,
  files : Array[String],
  html : Array[(String, String)],
  feed : String?,
) -> Array[@model.Problem] {
  let present : Map[String, Bool] = Map([])
  for f in files {
    present.set(f, true)
  }
  let problems = []
  for page in html {
    let (path, text) = page
    for url in attribute_values(text) {
      guard url.has_prefix(base) else { continue }
      let target = match url[base.length():].find("#") {
        Some(i) => url[base.length():base.length() + i].to_owned()
        None => url[base.length():].to_owned()
      }
      let file = if target == "" || target.has_suffix("/") {
        target + "index.html"
      } else {
        target
      }
      if !present.contains(file) {
        problems.push(
          @model.problem(
            path,
            "link `\{url}` does not resolve in the built site",
          ),
        )
      }
    }
    if !title_ok(text) {
      problems.push(@model.problem(path, "page has no `<title>`"))
    }
  }
  match feed {
    Some(xml) =>
      if xml_problem(xml) is Some(message) {
        problems.push(@model.problem("blog/atom.xml", message))
      }
    None => problems.push(@model.problem("blog/atom.xml", "feed is missing"))
  }
  for f in files {
    if f.has_prefix("docs/superpowers/") {
      problems.push(@model.problem(f, "forbidden path in the built site"))
    }
  }
  problems
}
