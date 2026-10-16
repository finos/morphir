///|
pub(all) struct NodeMetadata {
  node_id : String
  data : @ion.IonValue
}

///|
/// A rich unit for the Scheme backend, independent of engine and host types: the IR, its node metadata, ordered
/// annotation tokens and provenance, as `finos/morphir-moonbit`'s `Input`.
pub(all) struct Input {
  unit_id : String
  ir : @ir.IRFile
  metadata : Array[NodeMetadata]
  annotations : Array[@ion.SymbolToken]
  provenance : Array[@ion.IonValue]
}

///|
pub fn Input::new(unit_id : String, ir : @ir.IRFile) -> Input {
  { unit_id, ir, metadata: [], annotations: [], provenance: [], }
}

///|
/// The Scheme text and the binary Ion symbols sidecar.
pub(all) struct Output {
  source : String
  symbols : Bytes
}

///|
pub const SYMBOLS_PROFILE : String = "morphir-scheme-symbols-v1"

///|
pub const SYMBOLS_SUFFIX : String = ".symbols.10n"

///|
/// Emit a unit: the text of `emit_file`, with a source comment above each define that the unit's metadata
/// describes, and the symbols sidecar that carries the metadata unchanged. `source_path` names the source in the
/// comments when a hint carries no path of its own; without it the unit id is used.
pub fn emit_unit(unit : Input, source_path~ : String? = None) -> Output raise {
  let hints = declaration_hints(unit, source_path)
  let emitted = emit_distribution(unit.ir, hints)
  {
    source: emitted.forms.join("\n"),
    symbols: symbol_metadata(unit, emitted.symbols),
  }
}
