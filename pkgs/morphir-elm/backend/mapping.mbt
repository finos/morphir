///|
pub using @mapping {type MappingEntry, type Namespace}

///|
/// Keys are canonical FQName text, for example `morphir/SDK:basics#add`.
/// `overridden` holds the keys of user entries, prefixed with `type ` or `value `.
pub struct Mapping {
  priv types : Map[String, MappingEntry]
  priv values : Map[String, MappingEntry]
  priv overridden : Map[String, Bool]
}

///|
pub fn Mapping::empty() -> Mapping {
  { types: Map([]), values: Map([]), overridden: Map([]), }
}

///|
pub fn Mapping::builtin() -> Mapping {
  let mapping = Mapping::empty()
  for entry in @mapping.builtin_entries() {
    match entry.1 {
      Type(_, _) => mapping.types[entry.0] = entry.1
      _ => mapping.values[entry.0] = entry.1
    }
  }
  mapping
}

///|
pub fn Mapping::with_overrides(
  self : Mapping,
  overrides : Map[String, MappingEntry],
) -> Mapping {
  let types = self.types.copy()
  let values = self.values.copy()
  let overridden = self.overridden.copy()
  for key, entry in overrides {
    match entry {
      Type(_, _) => {
        types[key] = entry
        overridden["type " + key] = true
      }
      Operator(_) | Function(_, _) => {
        values[key] = entry
        overridden["value " + key] = true
      }
      Removed => {
        types.remove(key)
        values.remove(key)
      }
    }
  }
  { types, values, overridden, }
}

///|
pub fn Mapping::lookup(
  self : Mapping,
  name : @ir.FQName,
  space : Namespace,
) -> MappingEntry? {
  let table = match space {
    TypeSpace => self.types
    ValueSpace => self.values
  }
  table.get(name.to_canonical())
}

///|
/// A user entry keeps its text as written; a built-in entry may print bare.
fn Mapping::is_override(
  self : Mapping,
  name : @ir.FQName,
  space : Namespace,
) -> Bool {
  let prefix = match space {
    TypeSpace => "type "
    ValueSpace => "value "
  }
  self.overridden.contains(prefix + name.to_canonical())
}

///|
pub fn Mapping::is_empty(self : Mapping) -> Bool {
  self.types.is_empty() && self.values.is_empty()
}

///|
fn parse_mapping_entry(
  key : String,
  value : Json,
) -> MappingEntry raise ElmGenerationError {
  let at = "backends.elm.mapping." + key
  let canonical = @ir.FQName::parse(key) catch {
    _ => refuse("invalid_mapping", at, "the key is not a canonical FQName")
  }
  if canonical.to_canonical() != key {
    refuse(
      "invalid_mapping",
      at,
      "write the key as " + canonical.to_canonical(),
    )
  }
  guard value is Object(fields) else {
    refuse("invalid_mapping", at, "an entry is a table")
  }
  let mut kind : (String, String)? = None
  let mut import_line : String? = None
  for name, field in fields {
    guard field is String(text) && text != "" else {
      refuse("invalid_mapping", at, name + " must be nonempty text")
    }
    match name {
      "operator" | "function" | "type" => {
        if kind is Some(_) {
          refuse(
            "invalid_mapping", at, "use exactly one of operator, function or type",
          )
        }
        kind = Some((name, text))
      }
      "import" => import_line = Some(text)
      other => refuse("invalid_mapping", at, "unknown key " + other)
    }
  }
  match (kind, import_line) {
    (None, None) => Removed
    (None, Some(_)) =>
      refuse("invalid_mapping", at, "import needs a function or type")
    (Some(("operator", _)), Some(_)) =>
      refuse("invalid_mapping", at, "an operator takes no import")
    (Some(("operator", op)), None) => Operator(op)
    (Some(("function", name)), imp) => Function(name, imp)
    (Some((_, name)), imp) => Type(name, imp)
  }
}
