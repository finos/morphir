///|
/// An authoritative public entry's supported boundary declarations.
/// Manifest parsing, duplicate admission and declaration closure happen before
/// constructing these entries. No model visibility is inferred from a name.
pub(all) struct PublicEntry {
  name : String
  inputs : Array[ValueType]
  output : ValueType
}

///|
/// Validate a decoded suite before acquiring an execution provider.
/// Rejections are trusted generator diagnostics for entries absent from the
/// public allowlist. They never add entries or override an admitted entry.
/// Output types are manifest declarations; this validates argument values only.
pub fn validate_invocations(
  suite : Suite,
  entries : Array[PublicEntry],
  definitions : Array[CustomType],
  rejections~ : Array[(String, String)] = [],
) -> Unit raise {
  suite.validate()
  for call in suite.calls {
    guard entries.filter(e => e.name == call.entry).get(0) is Some(entry) else {
      let reason = rejections
        .filter(p => p.0 == call.entry)
        .get(0)
        .map(p => p.1)
        .unwrap_or("execution.entry_not_public_or_supported")
      raise Invalid(reason + ": " + call.entry)
    }
    if call.arguments.length() != entry.inputs.length() {
      raise Invalid("execution.wrong_arity: " + call.id)
    }
    for i = 0; i < call.arguments.length(); i = i + 1 {
      validate_as(call.arguments[i], entry.inputs[i], definitions)
    }
  }
}
