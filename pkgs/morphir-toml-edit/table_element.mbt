///|
priv enum ElementStep {
  Key(String)
  Index(Int32)
} derive(Eq)

///|
priv struct EditFocus {
  keys : Array[String]
  end : Int32
}

///|
/// An immutable selection of one array-of-tables element. Nested selections
/// retain every ancestor index. Editing returns the complete document.
pub struct TableElement {
  priv document : Document
  priv path : Array[ElementStep]
}

///|
fn element_prefix(
  parent : Array[ElementStep],
  path : Array[ElementStep],
) -> Bool {
  if parent.length() > path.length() {
    return false
  }
  for i, part in parent {
    if part != path[i] {
      return false
    }
  }
  true
}

///|
fn element_keys(path : Array[ElementStep]) -> Array[String] {
  path.filter_map(part => {
    match part {
      Key(key) => Some(key)
      Index(_) => None
    }
  })
}

///|
/// Resolve headers through the last element of each enclosing array. Counts
/// include the ancestor indices, so nested arrays restart in every parent.
fn Document::located(self : Document) -> Array[(Array[ElementStep], Statement)] {
  let counts : Array[(Array[ElementStep], Int32)] = []
  let result = []
  let mut current : Array[ElementStep] = []
  for statement in self.statements {
    if statement is Header(keys, kind, _) {
      let path = []
      for i, key in keys {
        path.push(Key(key))
        let counter = counts.search_by(entry => entry.0 == path)
        if i == keys.length() - 1 && kind is ArrayOfTables {
          let index = match counter {
            Some(at) => {
              let index = counts[at].1 + 1
              counts[at] = (path.copy(), index)
              index
            }
            None => {
              counts.push((path.copy(), 0))
              0
            }
          }
          path.push(Index(index))
        } else if counter is Some(at) {
          path.push(Index(counts[at].1))
        }
      }
      current = path
    }
    result.push((current.copy(), statement))
  }
  result
}

///|
fn Document::check_array_ancestors(
  self : Document,
  path : Array[String],
) -> Unit raise Diagnostic {
  for statement in self.statements {
    if statement is Header(table, ArrayOfTables, span) &&
      table.length() < path.length() &&
      prefix(table, path) {
      raise problem(
        self.source,
        span.start,
        UnsupportedArrayOfTables,
        "Select the enclosing array-of-tables element by index",
      )
    }
  }
}

///|
fn select_element(
  document : Document,
  parent : Array[ElementStep],
  path : Array[String],
  index : Int32,
) -> TableElement raise Diagnostic {
  if path.is_empty() {
    raise problem(
      document.source,
      0,
      WrongKind,
      "An array-of-tables path must not be empty",
    )
  }
  if index < 0 {
    raise problem(
      document.source,
      0,
      InvalidIndex,
      "Array-of-tables index is out of bounds",
    )
  }
  let base = parent + path.map(key => Key(key))
  let selected = base + [Index(index)]
  let mut array_exists = false
  for (context, statement) in document.located() {
    if statement is Header(_, ArrayOfTables, _) &&
      context.length() == selected.length() &&
      element_prefix(base, context) {
      array_exists = true
      if context == selected {
        return { document, path: selected, }
      }
    }
  }
  raise problem(
    document.source,
    0,
    if array_exists {
      InvalidIndex
    } else {
      MissingPath
    },
    if array_exists {
      "Array-of-tables index is out of bounds"
    } else {
      "No array of tables at " + path_text(path)
    },
  )
}

///|
/// Select an element by its zero-based index. Use TableElement::element for a
/// nested array, so no enclosing index is guessed.
pub fn Document::element(
  self : Document,
  path : Array[String],
  index : Int32,
) -> TableElement raise Diagnostic {
  self.check_array_ancestors(path)
  select_element(self, [], path, index)
}

///|
pub fn TableElement::element(
  self : TableElement,
  path : Array[String],
  index : Int32,
) -> TableElement raise Diagnostic {
  self.focused().check_array_ancestors(path)
  select_element(self.document, self.path, path, index)
}

///|
/// An element ends before the next element of its own or an enclosing array.
fn TableElement::end(self : TableElement) -> Int32 {
  let mut started = false
  for (context, statement) in self.document.located() {
    guard statement is Header(_, _, span) else { continue }
    if context == self.path {
      started = true
      continue
    }
    if !started {
      continue
    }
    for i, part in self.path {
      guard context.get(i) is Some(other) else { break }
      if part == other {
        continue
      }
      if part is Index(_) && other is Index(_) {
        return self.document.leading_comments(span.start)
      }
      break
    }
  }
  self.document.source.length()
}

///|
fn TableElement::focused(self : TableElement) -> Document {
  let statements = []
  for (context, statement) in self.document.located() {
    guard element_prefix(self.path, context) else { continue }
    let relative = element_keys(context[self.path.length():].to_owned())
    statements.push(
      match statement {
        Header(_, kind, span) =>
          Header(
            relative,
            if context == self.path {
              Standard
            } else {
              kind
            },
            span,
          )
        Assignment(_, entry) => Assignment(relative, entry)
      },
    )
  }
  {
    source: self.document.source,
    statements,
    focus: Some({ keys: element_keys(self.path), end: self.end(), }),
  }
}

///|
pub fn TableElement::get(self : TableElement, path : Array[String]) -> String? {
  self.focused().get(path)
}

///|
pub fn TableElement::set(
  self : TableElement,
  path : Array[String],
  value : String,
) -> Document raise Diagnostic {
  self.focused().set(path, value)
}

///|
pub fn TableElement::remove(
  self : TableElement,
  path : Array[String],
) -> Document raise Diagnostic {
  self.focused().remove(path)
}

///|
pub fn TableElement::append(
  self : TableElement,
  path : Array[String],
  value : String,
) -> Document raise Diagnostic {
  self.focused().append(path, value)
}

///|
pub fn TableElement::remove_item(
  self : TableElement,
  path : Array[String],
  index : Int32,
) -> Document raise Diagnostic {
  self.focused().remove_item(path, index)
}

///|
pub fn TableElement::add_table(
  self : TableElement,
  path : Array[String],
) -> Document raise Diagnostic {
  self.focused().add_table(path)
}

///|
pub fn TableElement::remove_table(
  self : TableElement,
  path : Array[String],
) -> Document raise Diagnostic {
  self.focused().remove_table(path)
}

///|
fn Document::line_start(self : Document, at : Int32) -> Int32 {
  let mut start = at
  while start > 0 && self.source.code_unit_at(start - 1).to_int() != 10 {
    start -= 1
  }
  start
}

///|
/// Contiguous full comment lines and blank lines preceding a header belong to
/// that header. End-of-line comments stay with their own section.
fn Document::leading_comments(self : Document, at : Int32) -> Int32 {
  let mut start = self.line_start(at)
  while start > 0 {
    let previous = self.line_start(start - 1)
    let text = self.source[previous:start].trim()
    if text != "" && !text.has_prefix("#") {
      break
    }
    start = previous
  }
  start
}

///|
fn Document::sections(
  self : Document,
) -> Array[(Array[ElementStep], Int32, Int32)] {
  let headers = self
    .located()
    .filter_map(row => {
      match row.1 {
        Header(_, _, span) => Some((row.0, self.leading_comments(span.start)))
        _ => None
      }
    })
  headers.mapi((i, header) => {
    (
      header.0,
      header.1,
      headers.get(i + 1).map(next => next.1).unwrap_or(self.source.length()),
    )
  })
}

///|
/// Remove this element and its descendant sections, with their owned comments.
/// Interleaved sections belonging to other tables remain byte-for-byte intact.
pub fn TableElement::delete(self : TableElement) -> Document raise Diagnostic {
  let patches = self.document
    .sections()
    .filter_map(section => {
      if element_prefix(self.path, section.0) {
        Some({ start: section.1, end: section.2, text: "", })
      } else {
        None
      }
    })
  self.document.patched(patches)
}

///|
fn append_table_in(
  document : Document,
  parent : Array[ElementStep],
  path : Array[String],
  entries : Array[(Array[String], String)],
  end : Int32,
) -> Document raise Diagnostic {
  if path.is_empty() {
    raise problem(
      document.source,
      0,
      WrongKind,
      "An array-of-tables path must not be empty",
    )
  }
  let base = parent + path.map(key => Key(key))
  let mut last : Array[ElementStep]? = None
  for (context, statement) in document.located() {
    if statement is Header(_, ArrayOfTables, _) &&
      context.length() == base.length() + 1 &&
      element_prefix(base, context) {
      last = Some(context)
    }
  }
  let mut at = end
  if last is Some(last) {
    for section in document.sections() {
      if element_prefix(last, section.0) {
        at = section.2
      }
    }
  }
  let out = StringBuilder()
  if at > 0 && document.source.code_unit_at(at - 1).to_int() != 10 {
    out.write_string(document.eol())
  }
  out.write_string("[[" + path_text(element_keys(base)) + "]]" + document.eol())
  for (keys, value) in entries {
    if keys.is_empty() {
      raise problem(
        document.source,
        at,
        WrongKind,
        "A key path must not be empty",
      )
    }
    out.write_string(
      path_text(keys) + " = " + checked_value(value) + document.eol(),
    )
  }
  document.replace({ start: at, end: at, }, out.to_string())
}

///|
/// Append a new element after the last element and its descendants. Values are
/// TOML spellings, with the same validation as set; keys may be dotted paths.
pub fn Document::append_table(
  self : Document,
  path : Array[String],
  entries : Array[(Array[String], String)],
) -> Document raise Diagnostic {
  self.check_array_ancestors(path)
  append_table_in(self, [], path, entries, self.source.length())
}

///|
pub fn TableElement::append_table(
  self : TableElement,
  path : Array[String],
  entries : Array[(Array[String], String)],
) -> Document raise Diagnostic {
  self.focused().check_array_ancestors(path)
  append_table_in(self.document, self.path, path, entries, self.end())
}
