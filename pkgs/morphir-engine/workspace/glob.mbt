///|
/// Confined globs with literal separators, **, ?, classes and alternatives.
pub fn matches(pattern : String, path : String) -> Bool raise {
  matches_bounded(pattern, path, Ref(100000))
}

///|
fn matches_bounded(
  pattern : String,
  path : String,
  budget : Ref[Int32],
) -> Bool raise {
  budget.val -= 1
  if budget.val < 0 {
    raise @config.Invalid("Glob evaluation limit exceeded")
  }
  ignore(normalize(pattern))
  if pattern.length() > 512 || path.length() > 4096 {
    raise @config.Invalid("Glob/path limit exceeded")
  }
  // Expand one brace group at a time; nested groups are rejected explicitly.
  let chars = pattern.to_array()
  let mut open = -1
  for i, ch in chars {
    if ch == '{' {
      if open >= 0 {
        raise @config.Invalid(
          "Nested glob alternatives are unsupported: " + pattern,
        )
      }
      open = i
    }
    if ch == '}' {
      if open < 0 {
        raise @config.Invalid("Unmatched glob brace: " + pattern)
      }
      let before = String::from_array(chars[:open].to_owned())
      let after = String::from_array(chars[i + 1:].to_owned())
      let choices = String::from_array(chars[open + 1:i].to_owned())
      let mut found = false
      for choice in choices.split(",") {
        if matches_bounded(before + choice.to_owned() + after, path, budget) {
          found = true
        }
      }
      return found
    }
  }
  if open >= 0 {
    raise @config.Invalid("Unclosed glob brace: " + pattern)
  }
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '[' {
      let mut end = index + 1
      while end < chars.length() && chars[end] != ']' {
        end += 1
      }
      let first = if index + 1 < chars.length() &&
        (chars[index + 1] == '!' || chars[index + 1] == '^') {
        index + 2
      } else {
        index + 1
      }
      if end == chars.length() || first == end {
        raise @config.Invalid("Invalid glob class: " + pattern)
      }
      for i = first; i + 2 < end; i = i + 1 {
        if chars[i + 1] == '-' && chars[i] > chars[i + 2] {
          raise @config.Invalid("Reversed glob range: " + pattern)
        }
      }
      index = end
    } else if chars[index] == ']' {
      raise @config.Invalid("Unmatched glob class: " + pattern)
    }
    index += 1
  }
  let text = path.to_array()
  let cache : Map[String, Bool] = Map([])
  fn go(p : Int32, t : Int32) -> Bool raise {
    let key = p.to_string() + ":" + t.to_string()
    if cache.get(key) is Some(result) {
      return result
    }
    budget.val -= 1
    if budget.val < 0 {
      raise @config.Invalid("Glob evaluation limit exceeded")
    }
    let result = if p == chars.length() {
      t == text.length()
    } else {
      match chars[p] {
        '*' => {
          let double = p + 1 < chars.length() && chars[p + 1] == '*'
          let next = if double { p + 2 } else { p + 1 }
          let skip_slash = double && next < chars.length() && chars[next] == '/'
          if skip_slash {
            let mut slash = t
            while slash < text.length() && text[slash] != '/' {
              slash += 1
            }
            go(next + 1, t) || (slash < text.length() && go(p, slash + 1))
          } else {
            go(next, t) ||
            (t < text.length() && (double || text[t] != '/') && go(p, t + 1))
          }
        }
        '?' => t < text.length() && text[t] != '/' && go(p + 1, t + 1)
        '[' => {
          let mut end = p + 1
          while end < chars.length() && chars[end] != ']' {
            end = end + 1
          }
          if end == chars.length() || end == p + 1 {
            raise @config.Invalid("Invalid glob class: " + pattern)
          }
          let inverted = chars[p + 1] == '!' || chars[p + 1] == '^'
          let mut i = if inverted { p + 2 } else { p + 1 }
          let mut found = false
          if t < text.length() {
            while i < end {
              if i + 2 < end && chars[i + 1] == '-' {
                if chars[i] > chars[i + 2] {
                  raise @config.Invalid("Reversed glob range: " + pattern)
                }
                if text[t] >= chars[i] && text[t] <= chars[i + 2] {
                  found = true
                }
                i = i + 3
              } else {
                if chars[i] == text[t] {
                  found = true
                }
                i = i + 1
              }
            }
          }
          t < text.length() &&
          text[t] != '/' &&
          found != inverted &&
          go(end + 1, t + 1)
        }
        ']' => raise @config.Invalid("Unmatched glob class: " + pattern)
        ch => t < text.length() && ch == text[t] && go(p + 1, t + 1)
      }
    }
    cache[key] = result
    result
  }
  go(0, 0)
}
