///|
fn prefix(a : Array[String], b : Array[String]) -> Bool {
  if a.length() > b.length() {
    return false
  }
  for i, key in a {
    if b[i] != key {
      return false
    }
  }
  true
}

///|
fn related(a : Array[String], b : Array[String]) -> Bool {
  prefix(a, b) || prefix(b, a)
}

///|
fn joined(a : Array[String], b : Array[String]) -> Array[String] {
  let result = a.copy()
  result.append(b)
  result
}

///|
fn tail(path : Array[String], n : Int32) -> Array[String] {
  path[n:].to_owned()
}

///|
fn Document::check_edit(
  self : Document,
  path : Array[String],
) -> Unit raise Diagnostic {
  for statement in self.statements {
    match statement {
      Header(table, ArrayOfTables, span) if related(table, path) =>
        raise problem(
          self.source,
          span.start,
          UnsupportedArrayOfTables,
          "Select an array-of-tables element by index before editing it",
        )
      _ => ()
    }
  }
}

///|
fn lookup_inline(value : Value, path : Array[String]) -> Value? {
  if path.is_empty() {
    return Some(value)
  }
  match value {
    Inline(_, entries, _) => {
      for entry in entries {
        if prefix(entry.keys, path) {
          return lookup_inline(entry.value, tail(path, entry.keys.length()))
        }
      }
      None
    }
    _ => None
  }
}

///|
fn Document::lookup(self : Document, path : Array[String]) -> Value? {
  for statement in self.statements {
    if statement is Assignment(table, entry) {
      let full = joined(table, entry.keys)
      if prefix(full, path) {
        return lookup_inline(entry.value, tail(path, full.length()))
      }
    }
  }
  None
}

///|
/// Read a value's original TOML spelling. Paths contain decoded key segments;
/// a segment containing a dot is a single quoted key, not dotted syntax.
pub fn Document::get(self : Document, path : Array[String]) -> String? {
  // A path without an element index cannot select an array-of-tables member.
  for statement in self.statements {
    if statement is Header(table, ArrayOfTables, _) && prefix(table, path) {
      return None
    }
  }
  self
  .lookup(path)
  .map(fn(v) {
    let s = v.span()
    self.source[s.start:s.end].to_owned()
  })
}

///|
priv struct Patch {
  start : Int32
  end : Int32
  text : String
}

///|
/// Patches are applied right to left, retaining every source unit outside them.
fn Document::patched(
  self : Document,
  patches : Array[Patch],
) -> Document raise Diagnostic {
  let mut source = self.source
  let ordered = patches.copy()
  ordered.sort_by(fn(a, b) { b.start.compare(a.start) })
  for patch in ordered {
    source = source[:patch.start].to_owned() +
      patch.text +
      source[patch.end:].to_owned()
  }
  parse(source)
}

///|
fn Document::replace(
  self : Document,
  span : Span,
  text : String,
) -> Document raise Diagnostic {
  self.patched([{ start: span.start, end: span.end, text, }])
}

///|
fn checked_value(text : String) -> String raise Diagnostic {
  let p = Parser::{ source: text, pos: 0, }
  p.spaces()
  let v = p.value()
  p.spaces()
  if p.peek() != -1 {
    p.bad("Expected exactly one TOML value")
  }
  let s = v.span()
  text[s.start:s.end].to_owned()
}

///|
fn key_text(key : String) -> String {
  if !key.is_empty() && key.code_units().iter().all(c => bare(c.to_int())) {
    return key
  }
  let out = StringBuilder()
  out.write_char('"')
  for c in key {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\b' => out.write_string("\\b")
      '\t' => out.write_string("\\t")
      '\n' => out.write_string("\\n")
      '\u{000c}' => out.write_string("\\f")
      '\r' => out.write_string("\\r")
      _ =>
        if c.to_int() < 32 || c.to_int() == 127 {
          let n = c.to_int()
          let digits = "0123456789abcdef"
          out.write_string("\\u00")
          out.write_char(digits.code_unit_at(n / 16).to_int().unsafe_to_char())
          out.write_char(digits.code_unit_at(n % 16).to_int().unsafe_to_char())
        } else {
          out.write_char(c)
        }
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
fn path_text(path : Array[String]) -> String {
  path.map(key_text).join(".")
}

///|
fn Document::require_value(
  self : Document,
  path : Array[String],
) -> Value raise Diagnostic {
  self.check_edit(path)
  match self.lookup(path) {
    Some(v) => v
    None =>
      raise problem(
        self.source,
        0,
        MissingPath,
        "No value at " + path_text(path),
      )
  }
}

///|
fn Document::eol(self : Document) -> String {
  if self.source.contains("\r\n") {
    "\r\n"
  } else {
    "\n"
  }
}

///|
fn Document::line_end(self : Document, start : Int32) -> Int32 {
  let mut end = start
  while end < self.source.length() &&
        self.source.code_unit_at(end).to_int() != 10 {
    end += 1
  }
  if end < self.source.length() {
    end + 1
  } else {
    end
  }
}

///|
/// Set an existing value, or insert a key into an existing standard/inline
/// table. Missing intermediate tables are explicit via add_table.
pub fn Document::set(
  self : Document,
  path : Array[String],
  value : String,
) -> Document raise Diagnostic {
  self.check_edit(path)
  let value = checked_value(value)
  if self.lookup(path) is Some(old) {
    return self.replace(old.span(), value)
  }
  if path.is_empty() {
    raise problem(self.source, 0, WrongKind, "A key path must not be empty")
  }
  let parent = path[:path.length() - 1].to_owned()
  let key = key_text(path[path.length() - 1])
  // An inline table can define an implicit parent with dotted keys too.
  for length = parent.length(); length >= 0; length = length - 1 {
    let ancestor = parent[:length].to_owned()
    if self.lookup(ancestor) is Some(Inline(span, entries, _)) {
      let relative = tail(parent, length)
      if relative.is_empty() || entries.any(e => prefix(relative, e.keys)) {
        let at = if entries.is_empty() {
          span.start + 1
        } else {
          entries[entries.length() - 1].value.span().end
        }
        let sep = if entries.is_empty() { "" } else { ", " }
        return self.replace(
          { start: at, end: at, },
          sep + path_text(tail(path, length)) + " = " + value,
        )
      }
    }
  }
  match self.lookup(parent) {
    Some(Inline(span, entries, _)) => {
      let at = if entries.is_empty() {
        span.start + 1
      } else {
        entries[entries.length() - 1].value.span().end
      }
      let sep = if entries.is_empty() { "" } else { ", " }
      self.replace({ start: at, end: at, }, sep + key + " = " + value)
    }
    Some(old) =>
      raise problem(
        self.source,
        old.span().start,
        WrongKind,
        "Parent is not a table",
      )
    None => {
      let mut found = parent.is_empty()
      let mut at = 0
      let mut current : Array[String] = []
      for statement in self.statements {
        match statement {
          Header(table, _, span) => {
            current = table
            if table == parent {
              found = true
              at = self.line_end(span.end)
            }
          }
          Assignment(_, entry) =>
            if current == parent {
              at = self.line_end(entry.value.span().end)
            }
        }
      }
      if !found {
        // Dotted definitions own their implicit tables. Add a sibling dotted
        // assignment in that same section instead of declaring a new table.
        let dotted_owner = self.statements
          .iter()
          .find_first(statement => {
            match statement {
              Assignment(table, entry) =>
                table.length() < parent.length() &&
                prefix(table, parent) &&
                prefix(parent, joined(table, entry.keys))
              _ => false
            }
          })
        if dotted_owner is Some(Assignment(table, _)) {
          let relative = tail(path, table.length())
          let mut at = 0
          for statement in self.statements {
            match statement {
              Header(header, _, span) if header == table =>
                at = self.line_end(span.end)
              Assignment(owner, entry) if owner == table =>
                at = self.line_end(entry.value.span().end)
              _ => ()
            }
          }
          let lead = if at > 0 &&
            self.source.code_unit_at(at - 1).to_int() != 10 {
            self.eol()
          } else {
            ""
          }
          return self.replace(
            { start: at, end: at, },
            lead + path_text(relative) + " = " + value + self.eol(),
          )
        }
        let implicit_parent = self.statements.any(fn(statement) {
          match statement {
            Header(table, Standard, _) => prefix(parent, table)
            _ => false
          }
        })
        if implicit_parent {
          let at = self.focus.map(f => f.end).unwrap_or(self.source.length())
          let parent = joined(self.focus.map(f => f.keys).unwrap_or([]), parent)
          let lead = if at > 0 &&
            self.source.code_unit_at(at - 1).to_int() != 10 {
            self.eol()
          } else {
            ""
          }
          return self.replace(
            { start: at, end: at, },
            lead +
            "[" +
            path_text(parent) +
            "]" +
            self.eol() +
            key +
            " = " +
            value +
            self.eol(),
          )
        }
        raise problem(
          self.source,
          0,
          MissingPath,
          "No table at " + path_text(parent),
        )
      }
      let lead = if at > 0 && self.source.code_unit_at(at - 1).to_int() != 10 {
        self.eol()
      } else {
        ""
      }
      self.replace(
        { start: at, end: at, },
        lead + key + " = " + value + self.eol(),
      )
    }
  }
}

///|
fn inline_removal(value : Value, path : Array[String]) -> Array[Patch]? {
  guard value is Inline(_, entries, commas) else { return None }
  for i, entry in entries {
    if entry.keys == path {
      let patches = [
        { start: entry.start, end: entry.value.span().end, text: "", },
      ]
      if !commas.is_empty() {
        let comma = if i < commas.length() { commas[i] } else { commas[i - 1] }
        patches.push({ start: comma, end: comma + 1, text: "", })
      }
      return Some(patches)
    }
    if prefix(entry.keys, path) {
      if inline_removal(entry.value, tail(path, entry.keys.length()))
        is Some(patches) {
        return Some(patches)
      }
    }
  }
  None
}

///|
/// Remove only an entry and its required separator. Surrounding whitespace
/// and comments remain intact, including a former end-of-line comment.
pub fn Document::remove(
  self : Document,
  path : Array[String],
) -> Document raise Diagnostic {
  let value = self.require_value(path)
  for statement in self.statements {
    if statement is Assignment(table, entry) {
      if joined(table, entry.keys) == path {
        return self.replace({ start: entry.start, end: value.span().end, }, "")
      }
    }
  }
  for statement in self.statements {
    if statement is Assignment(table, entry) {
      let full = joined(table, entry.keys)
      if prefix(full, path) &&
        inline_removal(entry.value, tail(path, full.length())) is Some(patches) {
        return self.patched(patches)
      }
    }
  }
  raise problem(self.source, 0, MissingPath, "No inline key")
}

///|
/// Add a standard table at EOF. Existing implicit parents can be made explicit.
pub fn Document::add_table(
  self : Document,
  path : Array[String],
) -> Document raise Diagnostic {
  if path.is_empty() {
    raise problem(self.source, 0, WrongKind, "The root table already exists")
  }
  self.check_edit(path)
  let at = self.focus.map(f => f.end).unwrap_or(self.source.length())
  let path = joined(self.focus.map(f => f.keys).unwrap_or([]), path)
  let lead = if at > 0 && self.source.code_unit_at(at - 1).to_int() != 10 {
    self.eol()
  } else {
    ""
  }
  self.replace(
    { start: at, end: at, },
    lead + "[" + path_text(path) + "]" + self.eol(),
  )
}

///|
/// Remove a table and all its descendant tables, even when their sections are
/// interleaved with unrelated tables. Retain comments and whitespace.
pub fn Document::remove_table(
  self : Document,
  path : Array[String],
) -> Document raise Diagnostic {
  if path.is_empty() {
    raise problem(self.source, 0, WrongKind, "Cannot remove the document root")
  }
  self.check_edit(path)
  let patches = []
  let mut current : Array[String] = []
  for statement in self.statements {
    match statement {
      Header(table, _, span) => {
        current = table
        if prefix(path, table) {
          patches.push({ start: span.start, end: span.end, text: "", })
        }
      }
      Assignment(table, entry) =>
        if prefix(path, current) ||
          (
            path.length() < table.length() + entry.keys.length() &&
            prefix(path, joined(table, entry.keys))
          ) {
          patches.push({
            start: entry.start,
            end: entry.value.span().end,
            text: "",
          })
        }
    }
  }
  if patches.is_empty() {
    raise problem(self.source, 0, MissingPath, "No table at " + path_text(path))
  }
  self.patched(patches)
}

///|
/// Append an array item without rewriting existing items or their comments.
pub fn Document::append(
  self : Document,
  path : Array[String],
  value : String,
) -> Document raise Diagnostic {
  let old = self.require_value(path)
  let value = checked_value(value)
  match old {
    Sequence(span, items, commas) => {
      let at = span.end - 1
      let patches = [{ start: at, end: at, text: value, }]
      if !items.is_empty() && commas.length() < items.length() {
        let end = items[items.length() - 1].span().end
        if end == at {
          return self.replace({ start: at, end: at, }, "," + value)
        }
        patches.push({ start: end, end, text: ",", })
      }
      self.patched(patches)
    }
    _ =>
      raise problem(
        self.source,
        old.span().start,
        WrongKind,
        "Expected an array",
      )
  }
}

///|
/// Remove an array item and one comma, preserving intervening comments.
pub fn Document::remove_item(
  self : Document,
  path : Array[String],
  index : Int32,
) -> Document raise Diagnostic {
  let old = self.require_value(path)
  match old {
    Sequence(_, items, commas) => {
      if index < 0 || index >= items.length() {
        raise problem(
          self.source,
          old.span().start,
          InvalidIndex,
          "Array index is out of bounds",
        )
      }
      let span = items[index].span()
      let patches = [{ start: span.start, end: span.end, text: "", }]
      if !commas.is_empty() {
        let comma = if index < commas.length() {
          commas[index]
        } else {
          commas[index - 1]
        }
        patches.push({ start: comma, end: comma + 1, text: "", })
      }
      self.patched(patches)
    }
    _ =>
      raise problem(
        self.source,
        old.span().start,
        WrongKind,
        "Expected an array",
      )
  }
}
