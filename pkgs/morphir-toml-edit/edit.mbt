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
fn protected_value(
  source : String,
  value : Value,
  path : Array[String],
  target : Array[String],
) -> Unit raise Diagnostic {
  match value {
    Atom(_) => ()
    Sequence(_, items, _) =>
      for item in items {
        protected_value(source, item, path, target)
      }
    Inline(_, entries, _) =>
      for entry in entries {
        let full = joined(path, entry.keys)
        // Dotted syntax defines every intermediate table below this value.
        let dotted_root = joined(path, [entry.keys[0]])
        if entry.keys.length() > 1 && related(dotted_root, target) {
          raise problem(
            source,
            entry.start,
            UnsupportedDottedKey,
            "Dotted-key edits require tier 2",
          )
        }
        protected_value(source, entry.value, full, target)
      }
  }
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
          "Array-of-tables edits require tier 3",
        )
      Assignment(table, entry) => {
        let full = joined(table, entry.keys)
        let dotted_root = joined(table, [entry.keys[0]])
        if entry.keys.length() > 1 && related(dotted_root, path) {
          raise problem(
            self.source,
            entry.start,
            UnsupportedDottedKey,
            "Dotted-key edits require tier 2",
          )
        }
        protected_value(self.source, entry.value, full, path)
      }
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
  protected_value(text, v, [], [])
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
        let implicit_parent = self.statements.any(fn(statement) {
          match statement {
            Header(table, Standard, _) => prefix(parent, table)
            _ => false
          }
        })
        if implicit_parent {
          return self.add_table(parent).set(path, value)
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
  let parent = path[:path.length() - 1].to_owned()
  match self.lookup(parent) {
    Some(Inline(_, entries, commas)) => {
      for i, entry in entries {
        if entry.keys == [path[path.length() - 1]] {
          let patches = [
            { start: entry.start, end: value.span().end, text: "", },
          ]
          if !commas.is_empty() {
            let comma = if i < commas.length() {
              commas[i]
            } else {
              commas[i - 1]
            }
            patches.push({ start: comma, end: comma + 1, text: "", })
          }
          return self.patched(patches)
        }
      }
      raise problem(self.source, 0, MissingPath, "No inline key")
    }
    _ =>
      raise problem(self.source, 0, WrongKind, "Parent is not an inline table")
  }
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
  let at = self.source.length()
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
      Assignment(_, entry) =>
        if prefix(path, current) {
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
