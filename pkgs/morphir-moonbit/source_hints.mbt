///|
/// Metadata is a spelling hint, never an exact request or a trust decision.
/// Duplicate fields, invalid spans and ambiguous hints are ignored and retained.
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
fn hint_text(value : @ion.IonValue, name : String) -> String? {
  match hint_field(value, name) {
    Some(v) =>
      match v.kind() {
        String(text) => Some(text)
        _ => None
      }
    None => None
  }
}

///|
fn hint_span(value : @ion.IonValue) -> @diagnostics.Span? {
  fn coordinate(value : @ion.IonValue, name : String) -> Int32? {
    guard hint_field(value, name) is Some(v) else { return None }
    guard v.kind() is Int(n) else { return None }
    let text = n.to_string()
    let result = @strconv.parse_int(text) catch { _ => return None }
    if result >= 0 {
      Some(result)
    } else {
      None
    }
  }
  guard coordinate(value, "start_line") is Some(start_line) else { return None }
  guard coordinate(value, "start_column") is Some(start_column) else {
    return None
  }
  guard coordinate(value, "end_line") is Some(end_line) else { return None }
  guard coordinate(value, "end_column") is Some(end_column) else { return None }
  if end_line < start_line ||
    (end_line == start_line && end_column < start_column) {
    return None
  }
  Some({ start_line, start_column, end_line, end_column, })
}

///|
fn moonbit_origins(input : Input) -> Bool {
  input.provenance.any(p => {
    p.annotations().any(a => a.text() == Some("morphir_moonbit_frontend")) &&
    hint_text(p, "unit_id") == Some(input.unit_id) &&
    (
      hint_text(p, "language") == Some("moonbit") ||
      hint_text(p, "frontend") == Some("moonbit-model-bool-v1")
    )
  })
}

///|
fn declaration_hint(
  plan : TargetNames,
  owner : String,
) -> (String?, @diagnostics.Span?) {
  guard plan.origins.get(owner) is Some(data) else { return (None, None) }
  guard hint_field(data, "declaration") is Some(origin) else {
    return (None, None)
  }
  (hint_text(origin, "name"), hint_span(origin))
}
