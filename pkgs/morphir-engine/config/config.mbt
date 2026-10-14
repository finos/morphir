///|
pub(all) suberror Invalid {
  Invalid(String)
}

///|
pub(all) struct Document {
  value : @toml.TomlValue
  provenance : Map[String, String]
}

///|
fn leaves(
  value : @toml.TomlValue,
  path : String,
  origin : String,
  out : Map[String, String],
) -> Unit {
  match value {
    TomlTable(fields) =>
      for key, value in fields {
        leaves(
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
pub fn parse(text : String, origin? : String = "<memory>") -> Document raise {
  let value = @toml.parse(text) catch {
    error =>
      raise Invalid("Invalid TOML at " + origin + ": " + error.to_string())
  }
  let provenance = Map([])
  leaves(value, "", origin, provenance)
  { value, provenance, }
}

///|
pub fn empty() -> Document {
  { value: @toml.TomlTable(Map([])), provenance: Map([]), }
}

///|
pub fn Document::encode(self : Document) -> String {
  self.value.to_string()
}

///|
pub fn Document::get(self : Document, path : String) -> @toml.TomlValue? {
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
pub fn Document::text(
  self : Document,
  path : String,
  fallback : String,
) -> String raise {
  match self.get(path) {
    None => fallback
    Some(TomlString(value)) => value
    _ => raise Invalid("Expected string at " + path)
  }
}

///|
pub fn Document::strings(self : Document, path : String) -> Array[String] raise {
  match self.get(path) {
    None => []
    Some(TomlArray(values)) =>
      values.map(fn(value) raise {
        match value {
          TomlString(value) => value
          _ => raise Invalid("Expected string array at " + path)
        }
      })
    _ => raise Invalid("Expected array at " + path)
  }
}

///|
fn secret(fields : Map[String, @toml.TomlValue]) -> Bool {
  fields.length() == 1 &&
  ["env", "file", "command", "keyring"].any(key => fields.contains(key))
}

///|
fn merge_value(
  base : @toml.TomlValue,
  overlay : @toml.TomlValue,
) -> @toml.TomlValue {
  match (base, overlay) {
    (TomlTable(a), TomlTable(b)) if !secret(a) && !secret(b) => {
      let fields = a.copy()
      for key, value in b {
        fields[key] = match a.get(key) {
          Some(old) => merge_value(old, value)
          None => value
        }
      }
      @toml.TomlTable(fields)
    }
    _ => overlay
  }
}

///|
pub fn merge(base : Document, overlay : Document) -> Document {
  let value = merge_value(base.value, overlay.value)
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
  leaves(value, "", "", present)
  for key in provenance.keys().collect() {
    if !present.contains(key) {
      provenance.remove(key)
    }
  }
  { value, provenance, }
}

///|
fn json_value(value : Json) -> @toml.TomlValue raise {
  match value {
    String(s) => @toml.TomlString(s)
    True => @toml.TomlBoolean(true)
    False => @toml.TomlBoolean(false)
    Number(n, repr~) =>
      match repr {
        Some(s) =>
          try {
            match @toml.parse("value = " + s) {
              TomlTable(t) => t["value"]
              _ => @toml.TomlFloat(n)
            }
          } catch {
            _ => @toml.TomlFloat(n)
          }
        None => @toml.TomlFloat(n)
      }
    Array(items) => @toml.TomlArray(items.map(json_value))
    Object(fields) => {
      let result = Map([])
      for k, v in fields {
        if !(v is Null) {
          result[k] = json_value(v)
        }
      }
      @toml.TomlTable(result)
    }
    Null => raise Invalid("TOML cannot represent null array elements")
  }
}

///|
pub fn from_json(
  value : Json,
  origin? : String = "<overlay>",
) -> Document raise {
  let value = json_value(value)
  let provenance = Map([])
  leaves(value, "", origin, provenance)
  { value, provenance, }
}

///|
pub fn environment(values : Map[String, String]) -> Document raise {
  let keys = values.keys().collect()
  // Long paths first; shorter paths replace nested values as required upstream.
  keys.sort_by(fn(a, b) {
    let depth = b.split("__").count().compare(a.split("__").count())
    if depth == 0 {
      a.compare(b)
    } else {
      depth
    }
  })
  let mut result = empty()
  for key in keys {
    if !key.has_prefix("MORPHIR_") || key == "MORPHIR_HOME" {
      continue
    }
    let mut start = 8
    while start < key.length() && key.code_unit_at(start).to_int() == 95 {
      start = start + 1
    }
    let path = key[start:]
      .to_owned()
      .to_lower()
      .split("__")
      .map(StringView::to_owned)
      .collect()
    if path.any(p => p == "") {
      raise Invalid("Empty environment configuration key: " + key)
    }
    let text = values[key]
    let mut value = environment_value(text)
    for i = path.length() - 1; i >= 0; i = i - 1 {
      value = @toml.TomlTable(Map::from_array([(path[i], value)]))
    }
    let provenance = Map([])
    leaves(value, "", key, provenance)
    result = merge(result, { value, provenance, })
  }
  result
}

///|
fn environment_value(text : String) -> @toml.TomlValue {
  if text.to_lower() == "true" {
    return @toml.TomlBoolean(true)
  }
  if text.to_lower() == "false" {
    return @toml.TomlBoolean(false)
  }
  if text.has_prefix("[") || text.has_prefix("{") {
    return json_value(@json.parse(text)) catch { _ => @toml.TomlString(text) }
  }
  let chars = text.to_array()
  let start = if !chars.is_empty() && (chars[0] == '+' || chars[0] == '-') {
    1
  } else {
    0
  }
  if chars.length() > start &&
    chars[start:].iter().all(ch => ch >= '0' && ch <= '9') {
    let mut first = start
    while first + 1 < chars.length() && chars[first] == '0' {
      first = first + 1
    }
    let number = (if start == 1 && chars[0] == '-' { "-" } else { "" }) +
      String::from_array(chars[first:].to_owned())
    return try {
      match @toml.parse("value = " + number) {
        TomlTable(fields) => fields["value"]
        _ => @toml.TomlString(text)
      }
    } catch {
      _ => @toml.TomlString(text)
    }
  }
  @toml.TomlString(text)
}

///|
/// Workspace defaults and global layers do not transfer project identity or roots.
pub fn Document::shared(self : Document) -> Document {
  let value = match self.value {
    TomlTable(fields) => {
      let copy = fields.copy()
      copy.remove("project")
      copy.remove("workspace")
      @toml.TomlTable(copy)
    }
    _ => self.value
  }
  let provenance = self.provenance.copy()
  for path in provenance.keys().collect() {
    if path == "project" ||
      path == "workspace" ||
      path.has_prefix("project.") ||
      path.has_prefix("workspace.") {
      provenance.remove(path)
    }
  }
  { value, provenance, }
}

///|
pub fn Document::boolean(
  self : Document,
  path : String,
  fallback : Bool,
) -> Bool raise {
  match self.get(path) {
    None => fallback
    Some(TomlBoolean(value)) => value
    _ => raise Invalid("Expected boolean at " + path)
  }
}

///|
fn toml_json(value : @toml.TomlValue, path : String) -> Json raise {
  match value {
    TomlString(s) => Json::string(s)
    TomlInteger(i) => Json::number(i.to_double(), repr=i.to_string())
    TomlFloat(d) => Json::number(d)
    TomlBoolean(b) => Json::boolean(b)
    TomlArray(items) => Json::array(items.map(item => toml_json(item, path)))
    TomlTable(fields) => {
      let result = Map([])
      for key, item in fields {
        result[key] = toml_json(item, path + "." + key)
      }
      Json::object(result)
    }
    TomlDateTime(_) => raise Invalid("Dates are not supported at " + path)
  }
}

///|
/// The value at a dotted path as JSON, for components that do not read TOML.
pub fn Document::json(self : Document, path : String) -> Json? raise {
  match self.get(path) {
    None => None
    Some(value) => Some(toml_json(value, path))
  }
}

///|
pub fn Document::validate(self : Document) -> Unit raise {
  for
    section in [
      "workspace", "project", "frontend", "ir", "pipeline", "backends",
    ] {
    match self.get(section) {
      None | Some(TomlTable(_)) => ()
      _ => raise Invalid("Expected table at " + section)
    }
  }
  for
    path in [
      "workspace.name", "workspace.root", "workspace.out_dir", "workspace.default_member",
      "project.name", "project.version", "project.source_directory", "project.module_prefix",
      "frontend.language", "frontend.provider", "frontend.profile", "ir.layout",
      "ir.format", "ir.mode", "pipeline.backend", "pipeline.checkpoint_format", "pipeline.inference",
    ] {
    ignore(self.text(path, ""))
  }
  for
    path in [
      "workspace.members", "workspace.exclude", "project.exposed_modules", "project.authors",
    ] {
    ignore(self.strings(path))
  }
  ignore(self.boolean("ir.strict_mode", false))
  ignore(self.boolean("pipeline.strict_naming", false))
  ignore(self.metadata_provider_request())
}
