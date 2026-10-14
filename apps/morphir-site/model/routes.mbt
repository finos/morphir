///|
/// The route of a file below `docs/`. `rel` uses `/`, has no leading `/`, and ends in
/// `.md` or `.html`. A `README` or `index` file gives the route of its directory.
pub fn doc_route(rel : String) -> String {
  let stem = strip_extension(rel).to_lower()
  let (dir, name) = match stem.rev_find("/") {
    Some(i) => (stem[:i].to_owned(), stem[i + 1:].to_owned())
    None => ("", stem)
  }
  let path = if name == "readme" || name == "index" {
    dir
  } else if dir == "" {
    name
  } else {
    "\{dir}/\{name}"
  }
  if path == "" {
    "/docs/"
  } else {
    "/docs/\{path}/"
  }
}

///|
pub fn strip_extension(path : String) -> String {
  for ext in [".html", ".md"] {
    if path.has_suffix(ext) {
      return path[:path.length() - ext.length()].to_owned()
    }
  }
  path
}

///|
/// Split a blog file name `YYYY-MM-DD-slug.md` (or `.html`) into its date and slug.
/// The date must be a real calendar date. The slug uses `a`-`z`, `0`-`9` and single
/// `-` between them, so it is one safe, lower-case URL segment.
pub fn post_parts(file_name : String) -> (String, String)? {
  let stem = strip_extension(file_name)
  if stem == file_name || stem.length() < 12 || stem[10] != '-' {
    return None
  }
  let date = stem[:10].to_owned()
  let slug = stem[11:].to_owned()
  if !is_calendar_date(date) || !is_slug(slug) {
    return None
  }
  Some((date, slug))
}

///|
fn digits(text : String, from : Int, to : Int) -> Int? {
  let mut n = 0
  for i in from..<to {
    let c = text[i]
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
/// Whether `date` is `YYYY-MM-DD` and names a day that exists.
fn is_calendar_date(date : String) -> Bool {
  guard date.length() == 10 && date[4] == '-' && date[7] == '-' else {
    return false
  }
  guard digits(date, 0, 4) is Some(year) &&
    digits(date, 5, 7) is Some(month) &&
    digits(date, 8, 10) is Some(day) else {
    return false
  }
  let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  let days = match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if leap { 29 } else { 28 }
    _ => 0
  }
  day >= 1 && day <= days
}

///|
/// Whether `slug` is `a`-`z` and `0`-`9` words joined by single `-`.
fn is_slug(slug : String) -> Bool {
  if slug == "" ||
    slug.has_prefix("-") ||
    slug.has_suffix("-") ||
    slug.contains("--") {
    return false
  }
  for c in slug {
    if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') {
      return false
    }
  }
  true
}

///|
pub fn post_route(slug : String) -> String {
  "/blog/\{slug}/"
}

///|
pub fn package_route(name : String) -> String {
  "/docs/packages/\{name}/"
}
