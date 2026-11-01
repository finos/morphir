///|
/// A plain Morphir IR JSON document as a model on the model line: a
/// `morphir-ir` and `morphir-json` envelope around the document's exact bytes,
/// with the generate tuple of the document's format version. Every host wraps
/// a plain IR document with this code, so one document gives one envelope on
/// each host (SES-3).
pub struct WrappedPlainIr {
  tuple : ModelTuple
  envelope : Json
} derive(Eq, Debug)

///|
pub extend WrappedPlainIr with Eq::{equal, not_equal}

///|
pub extend WrappedPlainIr with @debug.Debug::{to_repr}

///|
/// Wraps the bytes of a plain IR document. The caller gives the document that
/// it parsed from these bytes under its own bounds. The model ID and the
/// revision come from the SHA-256 of the bytes, so the same bytes always give
/// the same envelope, and other bytes give another revision. The payload holds
/// the bytes as they are: no conversion happens.
///
/// A document whose `formatVersion` names no IR version of a model tuple is
/// `TupleUnavailable`, because the host offers no tuple for it.
pub fn WrappedPlainIr::of(
  document : Bytes,
  ir : Json,
) -> WrappedPlainIr raise Refusal {
  let format = field_at(ir, ["formatVersion"])
  guard format.bind(IrVersion::of_format_version) is Some(ir_version) else {
    let named = format.map(value => value.stringify()).unwrap_or("nothing")
    raise Refusal(
      code=TupleUnavailable,
      message="the host has no model tuple for the formatVersion \{named} of a plain IR document",
    )
  }
  let tuple = ModelTuple::new(
    GenerateModel,
    MorphirIr,
    MorphirJson,
    V0_1_0Draft1,
    ir_version,
  )
  let digest = Sha256::of(document).to_string()
  let envelope : Json = {
    "envelopeVersion": tuple.envelope_version.to_string(),
    "modelId": "urn:morphir:plain-ir:sha256:\{digest}",
    "revision": "sha256:\{digest}",
    "irVersion": tuple.ir_version.to_string(),
    "profile": tuple.profile.to_string(),
    "payload": {
      "codec": tuple.codec.to_string(),
      "layout": "single-document",
      "decodedByteLength": document.length(),
      "sha256": digest,
      "content": @base64.encode(document[:]),
    },
    "evidence": [],
    "critical": [],
  }
  { tuple, envelope, }
}
