///|
/// Frozen pre-adoption TOML parse/merge oracle for the required parity corpus.

///|
suberror Invalid {
  Invalid(String)
}

///|
struct OldDocument {
  value : @toml.TomlValue
  provenance : Map[String, String]
}

///|
fn old_leaves(
  value : @toml.TomlValue,
  path : String,
  origin : String,
  out : Map[String, String],
) -> Unit {
  match value {
    TomlTable(fields) =>
      for key, value in fields {
        old_leaves(
          value,
          if path == "" {
            key
          } else {
            path + "." + key
          },
          origin,
          out,
        )
      }
    _ => out[path] = origin
  }
}

///|
fn old_parse(text : String, origin~ : String = "<memory>") -> OldDocument raise {
  let value = @toml.parse(text) catch {
    error =>
      raise Invalid("Invalid TOML at " + origin + ": " + error.to_string())
  }
  let provenance = Map([])
  old_leaves(value, "", origin, provenance)
  { value, provenance, }
}

///|
fn old_empty() -> OldDocument {
  { value: @toml.TomlTable(Map([])), provenance: Map([]), }
}

///|
fn OldDocument::get(self : OldDocument, path : String) -> @toml.TomlValue? {
  let mut value = self.value
  for part in path.split(".") {
    match value {
      TomlTable(fields) =>
        match fields.get(part.to_owned()) {
          Some(next) => value = next
          None => return None
        }
      _ => return None
    }
  }
  Some(value)
}

///|
fn old_secret(fields : Map[String, @toml.TomlValue]) -> Bool {
  fields.length() == 1 &&
  ["env", "file", "command", "keyring"].any(key => fields.contains(key))
}

///|
fn old_merge_value(
  base : @toml.TomlValue,
  overlay : @toml.TomlValue,
) -> @toml.TomlValue {
  match (base, overlay) {
    (TomlTable(a), TomlTable(b)) if !old_secret(a) && !old_secret(b) => {
      let fields = a.copy()
      for key, value in b {
        fields[key] = match a.get(key) {
          Some(old) => old_merge_value(old, value)
          None => value
        }
      }
      @toml.TomlTable(fields)
    }
    _ => overlay
  }
}

///|
fn old_merge(base : OldDocument, overlay : OldDocument) -> OldDocument {
  let value = old_merge_value(base.value, overlay.value)
  let provenance = base.provenance.copy()
  // Remove stale origins below replaced arrays, scalars and secret references.
  for path, origin in overlay.provenance {
    let keys = provenance.keys().collect()
    for key in keys {
      if key == path || key.has_prefix(path + ".") || path.has_prefix(key + ".") {
        provenance.remove(key)
      }
    }
    provenance[path] = origin
  }
  // Only retain paths present in the merged tree.
  let present = Map([])
  old_leaves(value, "", "", present)
  for key in provenance.keys().collect() {
    if !present.contains(key) {
      provenance.remove(key)
    }
  }
  { value, provenance, }
}

///|
fn old_toml_json(value : @toml.TomlValue, path : String) -> Json raise {
  match value {
    TomlString(s) => Json::string(s)
    TomlInteger(i) => Json::number(i.to_double(), repr=i.to_string())
    TomlFloat(d) => Json::number(d)
    TomlBoolean(b) => Json::boolean(b)
    TomlArray(items) =>
      Json::array(items.map(item => old_toml_json(item, path)))
    TomlTable(fields) => {
      let result = Map([])
      for key, item in fields {
        result[key] = old_toml_json(item, path + "." + key)
      }
      Json::object(result)
    }
    TomlDateTime(_) => raise Invalid("Dates are not supported at " + path)
  }
}

///|
/// The value at a dotted path as JSON, for components that do not read TOML.
fn OldDocument::json(self : OldDocument, path : String) -> Json? raise {
  match self.get(path) {
    None => None
    Some(value) => Some(old_toml_json(value, path))
  }
}
