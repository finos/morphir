///|
const CompactionPolicyId = "morphir.compact/0.1.0-draft.1"

///|
/// The policy and written JSON for one plain input document.
pub struct NameCompaction {
  policy : String
  written : String
  compacted : Bool
}

///|
priv struct NameCandidate {
  table : String
  spelling : String
  mut occurrences : Int64
  mut original_bytes : Int64
  mut assigned_id : String?
}

///|
fn compaction_table_name(table : CompactionTable) -> String {
  match table {
    NameTable => "names"
    PackagePathTable => "packagePaths"
    ModulePathTable => "modulePaths"
    FQNameTable => "fqNames"
  }
}

///|
fn compaction_bytes(text : String) -> Int64 {
  @utf8.encode(text[:]).length().to_int64()
}

///|
fn[T] lossless_spelling(
  value : Json,
  spelling : CompactionSpelling,
  read : (Json) -> T raise,
  canonical : (T) -> String,
  legacy : (T) -> Json raise,
) -> String? raise {
  let name = read(value)
  let text = canonical(name)
  guard context_spelling_fits(text) else { return None }
  match (spelling, value) {
    (CanonicalSpelling, String(original)) if original == text => {
      ignore(read(Json::string(text)))
      Some(text)
    }
    (ClassicSpelling, Array(_)) => {
      let expanded = legacy(read(Json::string(text)))
      if expanded.stringify() == value.stringify() {
        Some(text)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn candidate_spelling(
  table : CompactionTable,
  spelling : CompactionSpelling,
  value : Json,
) -> String? {
  try {
    match table {
      NameTable =>
        lossless_spelling(
          value,
          spelling,
          read_name,
          name => name.to_canonical(),
          name => write_legacy_name(name),
        )
      PackagePathTable | ModulePathTable =>
        lossless_spelling(
          value,
          spelling,
          read_path,
          path => path.to_canonical(),
          write_legacy_path,
        )
      FQNameTable =>
        lossless_spelling(
          value,
          spelling,
          read_fqname,
          name => name.to_canonical(),
          write_legacy_fqname,
        )
    }
  } catch {
    _ => None
  }
}

///|
// The same traversal supplies the policy's written order and its first-use order.
fn policy_walk(
  value : Json,
  shape : CompactionShape?,
  at_reference : (CompactionTable, CompactionSpelling, Json) -> Json raise CodecError,
) -> Json raise CodecError {
  if shape is Some(mark) {
    if mark.verbatim {
      return value
    }
    if mark.reference is Some((table, spelling)) {
      return at_reference(table, spelling, value)
    }
  }
  match value {
    Object(fields) => {
      let keys = fields.keys().collect()
      if !(shape is Some(mark) && mark.keep_order) {
        keys.sort_by((left, right) => left.lexical_compare(right))
      }
      let ordered : Map[String, Json] = Map([])
      for key in keys {
        let child = fields[key]
        let next = match shape {
          Some(mark) => (mark.member_shape)(value, key, child)
          None => None
        }
        ordered[key] = policy_walk(child, next, at_reference)
      }
      Json::object(ordered)
    }
    Array(items) =>
      Json::array(
        items.mapi((index, child) => {
          let next = match shape {
            Some(mark) => (mark.item_shape)(value, index, child)
            None => None
          }
          policy_walk(child, next, at_reference)
        }),
      )
    _ => value
  }
}

///|
fn compaction_alias(position : Int32) -> String {
  let reversed : Array[Char] = []
  let mut index = position
  while index > 0 {
    index -= 1
    reversed.push(('a'.to_int() + index % 26).unsafe_to_char())
    index /= 26
  }
  String::from_array(reversed.rev())
}

///|
fn policy_shape(input : Json) -> CompactionShape raise CodecError {
  let version = try {
    let version = read_version(field(input, "formatVersion"))
    version.check_supported()
    version
  } catch {
    _ =>
      raise Invalid(
        "context.unsupported_format", "Expected a supported IR version",
      )
  }
  let v3 = version.major == 3U
  guard v3 || version.major == 4U else {
    raise Invalid("context.unsupported_format", "Expected IR 3 or 4")
  }
  compaction_root_shape(input, v3)
}

///|
/// Compact names into the fixed draft.1 policy form, or emit that form plain
/// when all alias savings fail to pay for the envelope.
pub fn compact_names(text : String) -> NameCompaction raise CodecError {
  let input = parse(text)
  guard input is Object(fields) && fields.get("$schema") is None else {
    raise Invalid("context.not_plain_document", "Expected a plain IR document")
  }
  let shape = Some(policy_shape(input))
  let indexed : Map[(String, String), NameCandidate] = Map([])
  let first_use : Array[NameCandidate] = []
  let plain = policy_walk(input, shape, (table, spelling, value) => {
    if contains_name_reference(value) {
      raise Invalid(
        "context.not_plain_document", "A typed position already contains an alias",
      )
    }
    if candidate_spelling(table, spelling, value) is Some(text) {
      let table = compaction_table_name(table)
      let key = (table, text)
      let size = compaction_bytes(value.stringify())
      match indexed.get(key) {
        Some(candidate) => {
          candidate.occurrences += 1L
          candidate.original_bytes += size
        }
        None => {
          let candidate = {
            table,
            spelling: text,
            occurrences: 1L,
            original_bytes: size,
            assigned_id: None,
          }
          indexed[key] = candidate
          first_use.push(candidate)
        }
      }
    }
    value
  }).stringify()

  let tables : Map[String, Map[String, Json]] = Map([])
  let mut aliases = 0
  for candidate in first_use {
    let id = compaction_alias(aliases + 1)
    let id_size = id.length().to_int64()
    let saving = candidate.original_bytes -
      candidate.occurrences * (12L + id_size)
    let cost = id_size + compaction_bytes(candidate.spelling) + 6L
    if saving > cost {
      let table = match tables.get(candidate.table) {
        Some(existing) => existing
        None => {
          let fresh = Map([])
          tables[candidate.table] = fresh
          fresh
        }
      }
      if table.length() < 16384 {
        table[id] = Json::string(candidate.spelling)
        candidate.assigned_id = Some(id)
        aliases += 1
      }
    }
  }

  if aliases == 0 {
    return { policy: CompactionPolicyId, written: plain, compacted: false, }
  }

  let document = policy_walk(input, shape, (table, spelling, value) => {
    if candidate_spelling(table, spelling, value) is Some(text) &&
      indexed.get((compaction_table_name(table), text))
      is Some({ assigned_id: Some(id), .. }) {
      { "$name": id }
    } else {
      value
    }
  })
  let context : Map[String, Json] = Map([])
  let keys = tables.keys().collect()
  keys.sort_by((left, right) => left.lexical_compare(right))
  for name in keys {
    let entries = tables[name]
    let ids = entries.keys().collect()
    ids.sort_by((left, right) => left.lexical_compare(right))
    let ordered : Map[String, Json] = Map([])
    for id in ids {
      ordered[id] = entries[id]
    }
    context[name] = Json::object(ordered)
  }
  let envelope : Json = {
    "$schema": ContextualSchema,
    "context": Json::object(context),
    "document": document,
  }
  let written = envelope.stringify()
  if compaction_bytes(written) < compaction_bytes(plain) {
    { policy: CompactionPolicyId, written, compacted: true, }
  } else {
    { policy: CompactionPolicyId, written: plain, compacted: false, }
  }
}

///|
fn contains_name_reference(value : Json) -> Bool {
  match value {
    Object(fields) =>
      fields.contains("$name") || fields.values().any(contains_name_reference)
    Array(items) => items.iter().any(contains_name_reference)
    _ => false
  }
}

///|
/// Expand aliases in a whole JSON file and write the plain policy form.
/// Unmarked data and document literals are carried without name rewriting.
pub fn expand_names(text : String) -> String raise CodecError {
  let input = parse_with_limits(
    text,
    PlainDocumentMaxDepth,
    None,
    None,
    true,
    allow_document_layer=true,
  )
  let (document, name_context) = admit_contextual_document(input, true)
  if name_context is Some(_) && input is Object(fields) {
    for key, _ in fields {
      if key == "context" {
        break
      }
      if key == "document" {
        raise Invalid(
          "context.after_document", "The context must precede the document",
        )
      }
    }
  }
  let shape = Some(policy_shape(document))
  let name_context = name_context.map(context => context.with_document(document))
  policy_walk(document, shape, (table, spelling, value) => {
    guard value is Object(fields) && fields.contains("$name") else {
      if contains_name_reference(value) {
        raise Invalid(
          "context.invalid_reference", "An alias must occupy the complete typed name position",
        )
      }
      return value
    }
    guard name_context is Some(context) else {
      raise Invalid(
        "context.not_plain_document", "A typed position carries an alias without a context",
      )
    }
    try {
      match table {
        NameTable => {
          let name = context.canonical_name(value)
          match spelling {
            CanonicalSpelling => Json::string(name.to_canonical())
            ClassicSpelling => write_legacy_name(name)
          }
        }
        PackagePathTable | ModulePathTable => {
          let path = match table {
            PackagePathTable => context.package_path(value)
            _ => context.module_path(value)
          }
          match spelling {
            CanonicalSpelling => Json::string(path.to_canonical())
            ClassicSpelling => write_legacy_path(path)
          }
        }
        FQNameTable => {
          let name = context.canonical_fqname(value)
          match spelling {
            CanonicalSpelling => Json::string(name.to_canonical())
            ClassicSpelling => write_legacy_fqname(name)
          }
        }
      }
    } catch {
      Invalid(code, detail) => raise Invalid(code, detail)
      _ =>
        raise Invalid(
          "context.invalid_entry", "The alias cannot be expressed in this typed position",
        )
    }
  }).stringify()
}
