///|
/// Project metadata and filenames use conventional spelling; IR uses canonical names. `My.Pkg` and `my/pkg` both
/// give `my/pkg`.
pub fn canonical_path(text : String) -> String raise {
  let paths = text
    .split(".")
    .map(StringView::to_owned)
    .collect()
    .join("/")
    .split("/")
  let result = []
  for path in paths {
    let path = path.to_owned()
    let canonical = Some(@ir.Name::parse(path).to_canonical()) catch {
      _ => None
    }
    if canonical is Some(value) {
      result.push(value)
      continue
    }
    let chars = path.to_array()
    let words = []
    let mut word = ""
    for i, ch in chars {
      let upper = ch >= 'A' && ch <= 'Z'
      let previous_lower = i > 0 && chars[i - 1] >= 'a' && chars[i - 1] <= 'z'
      let next_lower = i + 1 < chars.length() &&
        chars[i + 1] >= 'a' &&
        chars[i + 1] <= 'z'
      if ch == '_' ||
        ch == '-' ||
        ch == ' ' ||
        (upper && (previous_lower || next_lower)) {
        if word != "" {
          words.push(word)
          word = ""
        }
      }
      if ch != '_' && ch != '-' && ch != ' ' {
        word = word + ch.to_string()
      }
    }
    if word != "" {
      words.push(word)
    }
    let value = words
      .map(fn(w) {
        if w.length() > 1 && w == w.to_upper() {
          w
        } else {
          w.to_lower()
        }
      })
      .join("-")
    result.push(@ir.Name::parse(value).to_canonical())
  }
  result.join("/")
}
