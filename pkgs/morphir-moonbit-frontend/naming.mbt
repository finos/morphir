///|
pub const NAMING_POLICY : String = "moonbit-readable-names-v1"

///|
fn lower_ascii(c : Char) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
fn upper_ascii(c : Char) -> Bool {
  c >= 'A' && c <= 'Z'
}

///|
fn digit_ascii(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Split ASCII source words at underscores and camel-case/initialism boundaries.
/// Unsupported characters are escaped by the allocator, never canonical parsing.
fn normalized_source(text : String) -> (@ir.Name, Bool) raise {
  let chars = text.to_array()
  let words : Array[String] = []
  let token = StringBuilder()
  let mut unsupported = false
  fn flush() -> Unit {
    let word = token.to_string()
    if word != "" {
      let uppercase = word.to_array().all(c => upper_ascii(c) || digit_ascii(c)) &&
        word.to_array().filter(upper_ascii).length() > 1
      words.push(if uppercase { word } else { word.to_lower() })
      token.reset()
    }
  }
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c == '_' {
      flush()
      continue
    }
    if !lower_ascii(c) && !upper_ascii(c) && !digit_ascii(c) {
      unsupported = true
      flush()
      continue
    }
    if i > 0 &&
      upper_ascii(c) &&
      (
        lower_ascii(chars[i - 1]) ||
        digit_ascii(chars[i - 1]) ||
        (
          upper_ascii(chars[i - 1]) &&
          i + 1 < chars.length() &&
          lower_ascii(chars[i + 1])
        )
      ) {
      flush()
    }
    token.write_char(c)
  }
  flush()
  if words.is_empty() {
    words.push("name")
    unsupported = true
  }
  (@ir.Name::parse(words.join("-")), unsupported)
}

///|
fn spelling_hex(text : String) -> String {
  let digits = "0123456789abcdef".to_array()
  let result = StringBuilder()
  for byte in @utf8.encode(text) {
    result.write_char(digits[byte.to_int() / 16])
    result.write_char(digits[byte.to_int() % 16])
  }
  result.to_string()
}

///|
/// Prefix extension and checked counters guarantee uniqueness against user names.
fn escaped_name(
  base : String,
  original : String,
  reserved : Map[String, Bool],
) -> @ir.Name raise {
  let hex = spelling_hex(original)
  let mut length = if hex.length() < 8 { hex.length() } else { 8 }
  let mut counter = 0
  while true {
    let suffix = if counter == 0 { "" } else { "-" + counter.to_string() }
    let candidate = base + "-source-" + hex[:length].to_owned() + suffix
    if !reserved.contains(candidate) {
      reserved[candidate] = true
      return @ir.Name::parse(candidate)
    }
    if length < hex.length() {
      length += 2
    } else {
      counter += 1
    }
  } nobreak {
    abort("unreachable")
  }
}

///|
fn diagnostic_span(source : @ir.SourceLocation) -> @diagnostics.Span {
  {
    start_line: source.start_line,
    start_column: source.start_column,
    end_line: source.end_line,
    end_column: source.end_column,
  }
}

///|
priv struct SourceNames {
  names : Map[String, @ir.Name]
  warnings : Array[@diagnostics.Warning]
}

///|
/// Allocate an entire identity namespace before binding any references.
fn allocate_source_names(
  inputs : Array[(String, @ir.SourceLocation)],
  owner : String,
) -> SourceNames raise {
  let groups : Map[String, Array[String]] = Map([])
  let spans : Map[String, @ir.SourceLocation] = Map([])
  let unsupported : Map[String, Bool] = Map([])
  let reserved : Map[String, Bool] = Map([])
  for (text, source) in inputs {
    if spans.contains(text) {
      continue
    }
    spans[text] = source
    let (name, escaped) = normalized_source(text)
    let base = name.to_canonical()
    unsupported[text] = escaped
    reserved[base] = true
    let group = groups.get(base).unwrap_or([])
    group.push(text)
    groups[base] = group
  }
  let names : Map[String, @ir.Name] = Map([])
  let warnings = []
  let bases = groups.keys().collect()
  bases.sort()
  for base in bases {
    let group = groups[base]
    group.sort_by((a, b) => spelling_hex(a).compare(spelling_hex(b)))
    let mut preferred = group[0]
    for text in group {
      if text == base.replace(old="-", new="_") && !unsupported[text] {
        preferred = text
        break
      }
    }
    for text in group {
      names[text] = if text == preferred && !unsupported[text] {
        @ir.Name::parse(base)
      } else {
        escaped_name(base, text, reserved)
      }
    }
    if group.length() > 1 || group.any(text => unsupported[text]) {
      let renamed = group[group.length() - 1]
      let mut n = 1
      let root = (if digit_ascii(base.to_array()[0]) { "name_" } else { "" }) +
        base.replace(old="-", new="_").to_lower() +
        "_renamed_"
      let mut suggestion = root + n.to_string()
      while reserved.contains(normalized_source(suggestion).0.to_canonical()) {
        n += 1
        suggestion = root + n.to_string()
      }
      warnings.push(@diagnostics.Warning::{
        code: if group.length() > 1 {
          "moonbit_frontend.name_normalization_collision"
        } else {
          "moonbit_frontend.name_spelling_escape"
        },
        stage: "frontend",
        message: if group.length() > 1 {
          "Source spellings normalize to " +
          base +
          "; continuing with distinct identities"
        } else {
          "Source spelling requires a portable identity escape; continuing automatically"
        },
        locations: group.map(text => {
          owner: owner + "#" + names[text].to_canonical(),
          original: text,
          allocated: names[text].to_canonical(),
          source: Some(diagnostic_span(spans[text])),
        }),
        fix: if group.length() > 1 {
          "Rename " +
          renamed +
          " to " +
          suggestion +
          " so its semantic words differ. A backend targetNames request alone cannot repair an IR identity collision."
        } else {
          "Rename " +
          renamed +
          " to " +
          suggestion +
          " to use distinct portable words."
        },
      })
    }
  }
  { names, warnings, }
}

///|
/// Reserve user bases before allocation; freshening never captures a user binding.
priv struct BinderNames {
  source : SourceNames
  reserved : Map[String, Bool]
  used : Map[String, Bool]
}

///|
fn BinderNames::new(
  inputs : Array[(String, @ir.SourceLocation)],
  owner : String,
) -> BinderNames raise {
  let source = allocate_source_names(inputs, owner)
  let reserved = Map([])
  for _, name in source.names {
    reserved[name.to_canonical()] = true
  }
  { source, reserved, used: Map([]), }
}

///|
fn BinderNames::fresh(
  self : BinderNames,
  base : String,
  role : String,
) -> @ir.Name raise {
  let mut counter = 1
  while true {
    let candidate = base + "-" + role + "-" + counter.to_string()
    if !self.reserved.contains(candidate) && !self.used.contains(candidate) {
      self.used[candidate] = true
      return @ir.Name::parse(candidate)
    }
    counter += 1
  } nobreak {
    abort("unreachable")
  }
}

///|
fn BinderNames::bind(self : BinderNames, text : String) -> @ir.Name raise {
  let name = self.source.names[text]
  let base = name.to_canonical()
  if self.used.contains(base) {
    return self.fresh(base, "shadow")
  }
  self.used[base] = true
  name
}

///|
fn collect_bindings(
  expr : LibraryExpr,
  names : Array[(String, @ir.SourceLocation)],
) -> Unit {
  match expr {
    Binding(text, source, value, body, _) => {
      names.push((text, source))
      collect_bindings(value, names)
      collect_bindings(body, names)
    }
    Negation(value, _) | Constraint(value, _, _) =>
      collect_bindings(value, names)
    Binary(_, lhs, rhs, _) => {
      collect_bindings(lhs, names)
      collect_bindings(rhs, names)
    }
    Conditional(cond, yes, no, _) => {
      collect_bindings(cond, names)
      collect_bindings(yes, names)
      collect_bindings(no, names)
    }
    Call(_, arguments, _) =>
      for arg in arguments {
        collect_bindings(arg, names)
      }
    _ => ()
  }
}

///|
fn check_naming_warnings(
  warnings : Array[@diagnostics.Warning],
  strict : Bool,
) -> Unit raise FrontendError {
  if strict && !warnings.is_empty() {
    let warning = warnings[0]
    let source = warning.locations[0].source.map(s => @ir.SourceLocation::{
      start_line: s.start_line,
      start_column: s.start_column,
      end_line: s.end_line,
      end_column: s.end_column,
    })
    raise Invalid({ code: warning.code, detail: warning.display(), source, })
  }
}

///|
fn SourceNames::reason(self : SourceNames, text : String) -> String {
  for warning in self.warnings {
    if warning.locations.any(loc => loc.original == text) {
      return if warning.code == "moonbit_frontend.name_normalization_collision" {
        "normalization-collision"
      } else {
        "portable-spelling-escape"
      }
    }
  }
  "normalized"
}
