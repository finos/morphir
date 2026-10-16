///|
pub(all) enum FieldValue {
  Text(String)
  List(Array[String])
} derive(Eq, Debug)

///|
pub extend FieldValue with Eq::{equal, not_equal}

///|
pub extend FieldValue with @debug.Debug::{to_repr}

///|
/// Front matter and the rest of a source file. `body_line` is the 1-based line
/// where the body starts in the source file.
pub(all) struct FrontMatter {
  fields : Map[String, FieldValue]
  body : String
  body_line : Int32
}

///|
let known_keys : Array[String] = [
  "title", "date", "authors", "summary", "order", "draft",
]

///|
/// Split `source` into front matter and body. Markdown front matter is a block
/// between two `---` lines at the top. HTML front matter is the same block inside
/// a leading `<!-- --- ... --- -->` comment. A file without the block has no fields.
pub fn parse_front_matter(
  file : String,
  source : String,
) -> FrontMatter raise @model.Invalid {
  let lines = source.split("\n").map(l => l.to_owned()).collect()
  let close = if lines.length() > 0 && lines[0].trim_end() == "---" {
    "---"
  } else if lines.length() > 0 && lines[0].trim_end() == "<!-- ---" {
    "--- -->"
  } else {
    return { fields: Map([]), body: source, body_line: 1, }
  }
  let mut end = -1
  for i in 1..<lines.length() {
    if lines[i].trim_end() == close {
      end = i
      break
    }
  }
  if end < 0 {
    raise @model.Invalid([
      @model.problem(file, "front matter is not closed with `\{close}`", line=1),
    ])
  }
  let fields : Map[String, FieldValue] = Map([])
  let problems : Array[@model.Problem] = []
  let mut current_list : String? = None
  for i in 1..<end {
    let line = lines[i]
    let number = i + 1
    if line.trim() == "" {
      continue
    }
    if line.trim_start().has_prefix("- ") {
      match current_list {
        Some(key) => {
          let item = unquote(line.trim_start()[2:].trim().to_owned())
          match fields.get(key) {
            Some(List(items)) => items.push(item)
            _ => fields.set(key, List([item]))
          }
        }
        None =>
          problems.push(
            @model.problem(file, "list item without a key", line=number),
          )
      }
      continue
    }
    guard line.find(":") is Some(colon) else {
      problems.push(@model.problem(file, "expected `key: value`", line=number))
      continue
    }
    let key = line[:colon].trim().to_owned()
    let value = line[colon + 1:].trim().to_owned()
    current_list = None
    if !known_keys.contains(key) {
      problems.push(
        @model.problem(file, "unknown front matter key `\{key}`", line=number),
      )
      continue
    }
    if fields.contains(key) {
      problems.push(
        @model.problem(file, "duplicate front matter key `\{key}`", line=number),
      )
      continue
    }
    if value == "" {
      current_list = Some(key)
      fields.set(key, List([]))
    } else if value.has_prefix("[") && value.has_suffix("]") {
      let inner = value[1:value.length() - 1].trim()
      let items = if inner == "" {
        []
      } else {
        inner.split(",").map(s => unquote(s.trim().to_owned())).collect()
      }
      fields.set(key, List(items))
    } else {
      fields.set(key, Text(unquote(value)))
    }
  }
  if problems.length() > 0 {
    raise @model.Invalid(problems)
  }
  let body = lines[end + 1:].iter().collect().join("\n")
  { fields, body, body_line: end + 2, }
}

///|
fn unquote(value : String) -> String {
  if value.length() >= 2 &&
    (
      (value.has_prefix("\"") && value.has_suffix("\"")) ||
      (value.has_prefix("'") && value.has_suffix("'"))
    ) {
    value[1:value.length() - 1].to_owned()
  } else {
    value
  }
}

///|
pub fn FrontMatter::text(self : FrontMatter, key : String) -> String? {
  match self.fields.get(key) {
    Some(Text(value)) => Some(value)
    _ => None
  }
}

///|
pub fn FrontMatter::list(self : FrontMatter, key : String) -> Array[String] {
  match self.fields.get(key) {
    Some(List(items)) => items
    Some(Text(value)) => [value]
    None => []
  }
}

///|
pub fn FrontMatter::flag(self : FrontMatter, key : String) -> Bool {
  self.text(key) is Some("true")
}
