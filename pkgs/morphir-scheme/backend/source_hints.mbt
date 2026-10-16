///|
/// A hint is a spelling for a comment, never a trusted fact. A field that occurs more than once, an invalid span
/// and a name that could end a line comment are ignored, as in the MoonBit backend's source hints.
fn hint_field(value : @ion.IonValue, name : String) -> @ion.IonValue? {
  guard value.kind() is Struct(fields) else { return None }
  let matches = fields.filter(f => f.name().text() == Some(name))
  if matches.length() == 1 {
    Some(matches[0].value())
  } else {
    None
  }
}

///|
/// Text that cannot end a `;` line comment or hide inside it: non-empty, at most 256 characters, with no control
/// character and no line or paragraph separator.
fn comment_safe(text : String) -> Bool {
  if text.is_empty() || text.length() > 256 {
    return false
  }
  !text
  .iter()
  .any(c => {
    let code = c.to_int()
    code < 0x20 ||
    code == 0x7F ||
    code == 0x85 ||
    code == 0x2028 ||
    code == 0x2029
  })
}

///|
fn hint_text(value : @ion.IonValue, name : String) -> String? {
  guard hint_field(value, name) is Some(v) else { return None }
  guard v.kind() is String(text) else { return None }
  if comment_safe(text) {
    Some(text)
  } else {
    None
  }
}

///|
/// A non-negative coordinate of at most nine digits, read without a numeric conversion of the Ion integer.
fn hint_coordinate(value : @ion.IonValue, name : String) -> Int32? {
  guard hint_field(value, name) is Some(v) else { return None }
  guard v.kind() is Int(n) else { return None }
  let text = n.to_string()
  if text.is_empty() || text.length() > 9 {
    return None
  }
  let mut result = 0
  for c in text {
    if c < '0' || c > '9' {
      return None
    }
    result = result * 10 + (c.to_int() - 48)
  }
  Some(result)
}

///|
fn hint_position(origin : @ion.IonValue) -> (Int32, Int32)? {
  guard hint_coordinate(origin, "start_line") is Some(start_line) else {
    return None
  }
  guard hint_coordinate(origin, "start_column") is Some(start_column) else {
    return None
  }
  guard hint_coordinate(origin, "end_line") is Some(end_line) else {
    return None
  }
  guard hint_coordinate(origin, "end_column") is Some(end_column) else {
    return None
  }
  if end_line < start_line ||
    (end_line == start_line && end_column < start_column) {
    return None
  }
  Some((start_line, start_column))
}

///|
/// The comment line for each declaration that the unit metadata describes, by canonical fqname. The hint is the
/// `declaration` record of the entry `value:<fqname>`; an entry that occurs more than once is ignored.
fn declaration_hints(
  unit : Input,
  source_path : String?,
) -> Map[String, String] {
  let counts : Map[String, Int32] = Map([])
  for entry in unit.metadata {
    counts[entry.node_id] = counts.get(entry.node_id).unwrap_or(0) + 1
  }
  let fallback = match source_path {
    Some(path) if comment_safe(path) => Some(path)
    _ => if comment_safe(unit.unit_id) { Some(unit.unit_id) } else { None }
  }
  let result : Map[String, String] = Map([])
  for entry in unit.metadata {
    if counts.get(entry.node_id) != Some(1) ||
      !entry.node_id.has_prefix("value:") {
      continue
    }
    guard hint_field(entry.data, "declaration") is Some(origin) else {
      continue
    }
    guard hint_text(origin, "name") is Some(name) else { continue }
    let location = match hint_text(origin, "path") {
      Some(path) => Some(path)
      None => fallback
    }
    let comment = ";; " +
      name +
      (match (location, hint_position(origin)) {
        (Some(place), Some((line, column))) =>
          " (" + place + ":" + line.to_string() + ":" + column.to_string() + ")"
        (Some(place), None) => " (" + place + ")"
        (None, _) => ""
      })
    result[entry.node_id["value:".length():].to_owned()] = comment
  }
  result
}
