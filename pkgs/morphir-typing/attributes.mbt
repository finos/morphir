///|
pub suberror TypeSubstitutionError {
  AttributeConflict
} derive(Eq, Debug)

///|
pub extend TypeSubstitutionError with Eq::{equal, not_equal}

///|
pub extend TypeSubstitutionError with @debug.Debug::{to_repr}

///|
fn type_attributes(t : @ir.Type) -> @ir.TypeAttributes {
  match t {
    Variable(a, _)
    | Reference(a, _, _)
    | Tuple(a, _)
    | Union(a, _)
    | Record(a, _)
    | ExtensibleRecord(a, _, _)
    | Function(a, _, _)
    | Unit(a) => a
  }
}

///|
fn with_attributes(t : @ir.Type, a : @ir.TypeAttributes) -> @ir.Type {
  match t {
    Variable(_, n) => Variable(a, n)
    Reference(_, n, xs) => Reference(a, n, xs)
    Tuple(_, xs) => Tuple(a, xs)
    Union(_, xs) => Union(a, xs)
    Record(_, fs) => Record(a, fs)
    ExtensibleRecord(_, n, fs) => ExtensibleRecord(a, n, fs)
    Function(_, x, y) => Function(a, x, y)
    Unit(_) => Unit(a)
  }
}

///|
/// Conjoins representable attributes. Conflicts cannot be flattened into one IR node.
fn merge_attributes(
  a : @ir.TypeAttributes,
  b : @ir.TypeAttributes,
) -> @ir.TypeAttributes? {
  if a.source is Some(x) && b.source is Some(y) && x != y {
    return None
  }
  let constraints = a.constraints.copy()
  let extensions = a.extensions.copy()
  for k, v in b.constraints {
    if constraints.get(k) is Some(old) && old != v {
      return None
    }
    constraints[k] = v
  }
  for k, v in b.extensions {
    if extensions.get(k) is Some(old) && old != v {
      return None
    }
    extensions[k] = v
  }
  Some({
    source: if a.source is Some(_) {
      a.source
    } else {
      b.source
    },
    constraints,
    extensions,
  })
}

///|
/// Source positions are descriptive. Inference markers are consumed by conversion.
/// Every other extension remains an obligation; no runtime extension interpreter is claimed.
fn obligations(a : @ir.TypeAttributes) -> @ir.TypeAttributes {
  let extensions = a.extensions.copy()
  if a.is_unknown() {
    extensions.remove("morphir.inference")
  }
  if extensions.get("example/union:provenance#note") is Some(Text(_)) {
    extensions.remove("example/union:provenance#note")
  }
  { ..a, source: None, extensions, }
}

///|
fn retained_attributes(t : @ir.Type) -> @ir.TypeAttributes {
  let a = type_attributes(t)
  let extensions = a.extensions.copy()
  if a.is_unknown() {
    extensions.remove("morphir.inference")
  }
  let constraints = a.constraints.copy()
  if t is Variable(_, _) &&
    constraints.get(TYPECLASS) is Some(Text(c)) &&
    is_class(c) {
    constraints.remove(TYPECLASS)
  }
  { ..a, extensions, constraints, }
}

///|
/// Rebuild a solved fact from its authored template, retaining occurrence metadata.
fn retain_solved_attributes(
  template : @ir.Type,
  solved : @ir.Type,
  conflicts : Ref[Bool],
) -> @ir.Type {
  let go = (a, b) => retain_solved_attributes(a, b, conflicts)
  let body : @ir.Type = match (template, solved) {
    (Reference(_, n, xs), Reference(a, m, ys)) if n == m &&
      xs.length() == ys.length() =>
      Reference(a, m, xs.mapi((i, x) => go(x, ys[i])))
    (Tuple(_, xs), Tuple(a, ys)) if xs.length() == ys.length() =>
      Tuple(a, xs.mapi((i, x) => go(x, ys[i])))
    (Union(_, xs), Union(a, ys)) if xs.length() == ys.length() =>
      Union(a, xs.mapi((i, x) => go(x, ys[i])))
    (Function(_, a, b), Function(attrs, c, d)) =>
      Function(attrs, go(a, c), go(b, d))
    (Record(_, xs), Record(a, ys)) =>
      Record(
        a,
        ys.map((n, y) => {
          match xs.get(n) {
            Some(x) => go(x, y)
            None => y
          }
        }),
      )
    (ExtensibleRecord(_, _, xs), Record(a, ys)) =>
      Record(
        a,
        ys.map((n, y) => {
          match xs.get(n) {
            Some(x) => go(x, y)
            None => y
          }
        }),
      )
    (ExtensibleRecord(_, _, xs), ExtensibleRecord(a, r, ys)) =>
      ExtensibleRecord(
        a,
        r,
        ys.map((n, y) => {
          match xs.get(n) {
            Some(x) => go(x, y)
            None => y
          }
        }),
      )
    _ => solved
  }
  match merge_attributes(retained_attributes(template), type_attributes(body)) {
    Some(a) => with_attributes(body, a)
    None => {
      conflicts.val = true
      body
    }
  }
}
