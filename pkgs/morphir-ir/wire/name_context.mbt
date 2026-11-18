///|
const ContextualSchema = "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json"

///|
/// Duplicate entries in these mappings use envelope diagnostics. A parser
/// must still confirm the top-level schema marker, which may appear last.
pub fn is_context_duplicate_scope(path : String) -> Bool {
  match path {
    ""
    | "/context"
    | "/context/names"
    | "/context/packagePaths"
    | "/context/modulePaths"
    | "/context/fqNames" => true
    _ => false
  }
}

///|
/// The admitted typed names owned by one physical IR document.
pub struct DocumentNameContext {
  names : Map[String, @common.Name]
  package_paths : Map[String, @common.Path]
  module_paths : Map[String, @common.Path]
  fq_names : Map[String, @common.FQName]
  document : Json?
}

///|
/// Bind error locations to the current parse of this file.
pub fn DocumentNameContext::with_document(
  self : DocumentNameContext,
  document : Json,
) -> DocumentNameContext {
  { ..self, document: Some(document), }
}

///|
fn alias_id(id : String) -> Bool {
  let mut first = true
  for character in id {
    let letter = (character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z')
    let digit = character >= '0' && character <= '9'
    if !letter && (first || !digit) {
      return false
    }
    first = false
  }
  !first
}

///|
fn context_spelling_fits(text : String) -> Bool {
  let mut size = 0
  for character in text {
    let codepoint = character.to_int()
    size += if codepoint < 128 {
      1
    } else if codepoint < 2048 {
      2
    } else if codepoint < 65536 {
      3
    } else {
      4
    }
    if size > 1024 {
      return false
    }
  }
  true
}

///|
fn[T] admit_name_table(
  tables : Map[String, Json],
  table : String,
  parse : (String) -> T raise,
) -> Map[String, T] raise CodecError {
  let path = "context." + table
  let entries = match tables.get(table) {
    None => return Map([])
    Some(Object(entries)) => entries
    _ => raise Invalid("context.invalid_entry", path + " must be an object")
  }
  guard entries.length() <= 16384 else {
    raise Invalid("context.too_many_entries", path + " exceeds 16384 entries")
  }
  for id, value in entries {
    if value is String(spelling) && !context_spelling_fits(spelling) {
      raise Invalid(
        "context.name_too_long",
        path + "." + id + " exceeds 1024 UTF-8 bytes",
      )
    }
  }
  let admitted = Map([])
  for id, value in entries {
    let entry = path + "." + id
    guard alias_id(id) && value is String(spelling) else {
      raise Invalid(
        "context.invalid_entry",
        entry + " has an invalid alias or spelling",
      )
    }
    let typed = parse(spelling) catch {
      _ =>
        raise Invalid(
          "context.invalid_entry",
          entry + " has an invalid canonical spelling",
        )
    }
    admitted[id] = typed
  }
  admitted
}

///|
fn check_context_critical(fields : Map[String, Json]) -> Unit raise CodecError {
  let critical = match fields.get("critical") {
    None => return
    Some(Array(critical)) => critical
    _ =>
      raise Invalid(
        "context.invalid_envelope", "critical must be an array of strings",
      )
  }
  guard critical.all(path => path is String(_)) else {
    raise Invalid(
      "context.invalid_envelope", "critical must be an array of strings",
    )
  }
  for value in critical {
    let path = string(value)
    guard [
      "$schema", "context", "context.names", "context.packagePaths", "context.modulePaths",
      "context.fqNames", "critical", "document",
    ].contains(path) else {
      raise Invalid("context.unknown_critical", path)
    }
  }
}

///|
/// Admit an opted-in envelope without expanding or copying its IR document.
pub fn admit_contextual_document(
  input : Json,
  allow_context : Bool,
) -> (Json, DocumentNameContext?) raise CodecError {
  guard input is Object(fields) && fields.get("$schema") is Some(schema) else {
    return (input, None)
  }
  guard allow_context && schema is String(url) && url == ContextualSchema else {
    raise Invalid("context.undeclared_schema", schema.stringify())
  }
  guard fields.get("context") is Some(Object(tables)) else {
    raise Invalid("context.invalid_envelope", "context must be an object")
  }
  guard fields.get("document") is Some(Object(_) as document) else {
    raise Invalid("context.invalid_envelope", "document must be an object")
  }
  check_context_critical(fields)
  let context = {
    names: admit_name_table(tables, "names", text => @common.Name::parse(text)),
    package_paths: admit_name_table(tables, "packagePaths", text => {
      @common.Path::parse(text)
    }),
    module_paths: admit_name_table(tables, "modulePaths", text => {
      @common.Path::parse(text)
    }),
    fq_names: admit_name_table(tables, "fqNames", text => {
      @common.FQName::parse(text)
    }),
    document: None,
  }
  (document, Some(context))
}

///|
fn find_reference(
  node : Json,
  target : Map[String, Json],
  path : Array[String],
) -> Bool {
  if path.length() > 512 {
    return false
  }
  match node {
    Object(fields) => {
      if physical_equal(fields, target) {
        return true
      }
      for key, child in fields {
        path.push(key)
        if find_reference(child, target, path) {
          return true
        }
        ignore(path.pop())
      }
    }
    Array(items) =>
      for index, child in items {
        path.push(index.to_string())
        if find_reference(child, target, path) {
          return true
        }
        ignore(path.pop())
      }
    _ => ()
  }
  false
}

///|
fn reference_location(document : Json?, fields : Map[String, Json]) -> String {
  let parts : Array[String] = []
  if document is Some(root) && find_reference(root, fields, parts) {
    "/document/" +
    parts
    .map(part => {
      part.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
    })
    .join("/")
  } else {
    "/document"
  }
}

///|
fn[T] context_slot(
  value : Json,
  table : Map[String, T],
  table_name : String,
  parse : (String) -> T raise,
  document : Json?,
) -> T raise {
  if value is Object(fields) && fields.get("$name") is Some(reference) {
    guard fields.length() == 1 && reference is String(id) && alias_id(id) else {
      raise Invalid(
        "context.invalid_reference",
        reference_location(document, fields) +
        ": Expected a single string $name alias",
      )
    }
    guard table.get(id) is Some(expanded) else {
      raise Invalid(
        "context.unknown_alias",
        reference_location(document, fields) +
        ": context." +
        table_name +
        "." +
        id,
      )
    }
    expanded
  } else {
    parse(string(value))
  }
}

///|
pub fn DocumentNameContext::canonical_name(
  self : DocumentNameContext,
  value : Json,
) -> @common.Name raise {
  context_slot(
    value,
    self.names,
    "names",
    text => @common.Name::parse(text),
    self.document,
  )
}

///|
pub fn DocumentNameContext::package_path(
  self : DocumentNameContext,
  value : Json,
) -> @common.Path raise {
  context_slot(
    value,
    self.package_paths,
    "packagePaths",
    text => @common.Path::parse(text),
    self.document,
  )
}

///|
pub fn DocumentNameContext::module_path(
  self : DocumentNameContext,
  value : Json,
) -> @common.Path raise {
  context_slot(
    value,
    self.module_paths,
    "modulePaths",
    text => @common.Path::parse(text),
    self.document,
  )
}

///|
pub fn DocumentNameContext::canonical_fqname(
  self : DocumentNameContext,
  value : Json,
) -> @common.FQName raise {
  context_slot(
    value,
    self.fq_names,
    "fqNames",
    text => @common.FQName::parse(text),
    self.document,
  )
}

///|
/// Resolve a name in a typed codec slot while retaining the ordinary wire spellings.
pub fn read_context_name(
  value : Json,
  context : DocumentNameContext?,
) -> @common.Name raise {
  if context is Some(names) &&
    value is Object(fields) &&
    fields.contains("$name") {
    names.canonical_name(value)
  } else {
    read_name(value)
  }
}

///|
/// Resolve an FQName in a typed codec slot. Opaque data never calls this reader.
pub fn read_context_fqname(
  value : Json,
  context : DocumentNameContext?,
) -> @common.FQName raise {
  if context is Some(names) &&
    value is Object(fields) &&
    fields.contains("$name") {
    names.canonical_fqname(value)
  } else {
    read_fqname(value)
  }
}

///|
pub fn read_classic_context_name(
  value : Json,
  context : DocumentNameContext?,
) -> @common.Name raise {
  if context is Some(names) &&
    value is Object(fields) &&
    fields.contains("$name") {
    let name = names.canonical_name(value)
    ignore(write_legacy_name(name))
    name
  } else {
    read_name(value)
  }
}

///|
pub fn read_classic_context_fqname(
  value : Json,
  context : DocumentNameContext?,
) -> @common.FQName raise {
  if context is Some(names) &&
    value is Object(fields) &&
    fields.contains("$name") {
    let name = names.canonical_fqname(value)
    ignore(write_legacy_fqname(name))
    name
  } else {
    read_fqname(value)
  }
}
