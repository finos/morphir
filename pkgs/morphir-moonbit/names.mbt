///|
fn hex(text : String) -> String {
  let digits = "0123456789abcdef".to_array()
  let result = StringBuilder()
  for byte in @utf8.encode(text) {
    let n = byte.to_int()
    result.write_char(digits[n >> 4])
    result.write_char(digits[n & 15])
  }
  result.to_string()
}

///|
fn validate_name(name : @ir.Name) -> Unit raise {
  if @ir.Name::parse(name.to_canonical()) != name {
    raise Invalid(
      "moonbit.invalid_name",
      name.to_canonical(),
      "Name segments do not round-trip through canonical spelling",
    )
  }
}

///|
fn validate_path(path : @ir.Path) -> Unit raise {
  if path.to_names().is_empty() {
    raise Invalid("moonbit.invalid_name", "", "Empty path")
  }
  for name in path.to_names() {
    validate_name(name)
  }
}

///|
/// Refuses an FQName whose names do not round-trip, as `value_name` does,
/// without building the hex name.
fn validate_fqname(name : @ir.FQName) -> Unit raise {
  validate_path(name.package_name)
  validate_path(name.module_name)
  validate_name(name.local_name)
}

///|
/// Legacy ABI helper. Read Output.symbols for names allocated in readable mode.
/// Hex encodes validated canonical FQNames without folding case or word boundaries.
pub fn value_name(name : @ir.FQName) -> String raise {
  validate_fqname(name)
  "v_" + hex(name.to_canonical())
}

///|
pub fn value_node(name : @ir.FQName) -> String {
  "value:" + name.to_canonical()
}

///|
fn quote(text : String) -> String {
  Json::string(text).stringify()
}

///|
/// Sort map keys while retaining numeric lexemes from the IR codec.
fn canonical_json(value : Json) -> String {
  match value {
    Object(fields) => {
      let keys = fields.keys().collect()
      keys.sort()
      "{" +
      keys.map(key => quote(key) + ":" + canonical_json(fields[key])).join(",") +
      "}"
    }
    Array(items) => "[" + items.map(canonical_json).join(",") + "]"
    _ => value.stringify()
  }
}
