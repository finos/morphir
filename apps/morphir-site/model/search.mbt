///|
pub(all) struct SearchEntry {
  route : String
  title : String
  section : String
  summary : String
  headings : Array[String]
  text : String
} derive(Eq, Debug)

///|
pub extend SearchEntry with Eq::{equal, not_equal}

///|
pub extend SearchEntry with @debug.Debug::{to_repr}

///|
pub fn SearchEntry::to_json(self : SearchEntry) -> Json {
  {
    "route": self.route.to_json(),
    "title": self.title.to_json(),
    "section": self.section.to_json(),
    "summary": self.summary.to_json(),
    "headings": self.headings.to_json(),
    "text": self.text.to_json(),
  }
}

///|
pub fn SearchEntry::from_json(json : Json) -> SearchEntry? {
  guard json is Object(f) else { return None }
  let text = fn(key : String) -> String? {
    if f.get(key) is Some(String(value)) {
      Some(value)
    } else {
      None
    }
  }
  guard text("route") is Some(route) &&
    text("title") is Some(title) &&
    text("section") is Some(section) &&
    text("summary") is Some(summary) &&
    text("text") is Some(body) &&
    f.get("headings") is Some(Array(items)) else {
    return None
  }
  let headings = items.filter_map(item => {
    if item is String(h) {
      Some(h)
    } else {
      None
    }
  })
  Some({ route, title, section, summary, headings, text: body, })
}

///|
fn words(text : String) -> Array[String] {
  let out = []
  let current = StringBuilder()
  for c in text.to_lower() {
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c.to_int() > 127 {
      current.write_char(c)
    } else if current.to_string() != "" {
      out.push(current.to_string())
      current.reset()
    }
  }
  if current.to_string() != "" {
    out.push(current.to_string())
  }
  out
}

///|
fn prefix_hit(haystack : Array[String], token : String) -> Bool {
  haystack.iter().any(w => w.has_prefix(token))
}

///|
/// Rank entries for a query. Every query token must prefix a word of the entry.
/// A token scores 3 in the title, 2 in a heading, 1 in the text. Ties keep index order.
pub fn search(
  entries : Array[SearchEntry],
  query : String,
  limit? : Int = 10,
) -> Array[SearchEntry] {
  let tokens = words(query)
  if tokens.is_empty() {
    return []
  }
  let scored = []
  for i, e in entries {
    let title = words(e.title)
    let headings = words(e.headings.join(" "))
    let text = words(e.text)
    let mut score = 0
    let mut all = true
    for t in tokens {
      if prefix_hit(title, t) {
        score += 3
      } else if prefix_hit(headings, t) {
        score += 2
      } else if prefix_hit(text, t) {
        score += 1
      } else {
        all = false
        break
      }
    }
    if all {
      scored.push((score, i))
    }
  }
  scored.sort_by((a, b) => if a.0 != b.0 { b.0 - a.0 } else { a.1 - b.1 })
  scored.iter().take(limit).map(s => entries[s.1]).collect()
}
