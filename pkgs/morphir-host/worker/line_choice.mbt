///|
/// The code of the warning that a fallback gives. It is stable: a consumer can
/// match it in the `diagnostics` of a command result.
pub let legacy_fallback_code : String = "extension.legacy_mep_fallback"

///|
/// What a fallback sends on MEP 0.1.
#derive(Eq, Debug)
pub(all) enum FallbackInput {
  Sources
  PlainIr
  ModelEnvelope
}

///|
pub extend FallbackInput with Eq::{equal, not_equal}

///|
pub extend FallbackInput with @debug.Debug::{to_repr}

///|
pub impl Show for FallbackInput with fn output(self, logger) {
  logger.write_string(
    match self {
      Sources => "sources"
      PlainIr => "plain-ir"
      ModelEnvelope => "model-envelope"
    },
  )
}

///|
pub extend FallbackInput with Show::{to_string, output}

///|
/// Why an operation runs on MEP 0.1 for a guest that also claims the model
/// line: no claimed model tuple matches the request, and the claims show that
/// the guest serves the request on MEP 0.1 (SES-4).
#derive(Eq, Debug)
pub struct LegacyFallback {
  extension_id : ExtensionId
  version : ExtensionVersion
  /// The MEP 0.1 method that runs.
  operation : Operation
  /// The model method that has no matching tuple.
  model_operation : ModelOperation
  /// The IR version of the request, when the request names one.
  requested : IrVersionName?
  /// The codec that the request requires, when it requires one.
  codec : ModelCodec?
  /// The claimed name of the IR version on MEP 0.1, when the request names one.
  ir_version : IrVersionName?
  input : FallbackInput
  /// The IR versions of the model tuples that the guest claims for the model
  /// method, newest first: the versions the user can move to.
  model_ir_versions : Array[IrVersion]
}

///|
pub extend LegacyFallback with Eq::{equal, not_equal}

///|
pub extend LegacyFallback with @debug.Debug::{to_repr}

///|
/// The line that an operation runs on, and the fallback when it is MEP 0.1 for
/// a guest that also claims the model line. Every host takes this choice from
/// the claims, so one request gives one line on each host.
#derive(Eq, Debug)
pub struct LineChoice {
  offer : Offer
  fallback : LegacyFallback?
}

///|
pub extend LineChoice with Eq::{equal, not_equal}

///|
pub extend LineChoice with @debug.Debug::{to_repr}

///|
/// The line of a generate call, with what it sends: the tuple on the model
/// line, and the model in the form of that line.
#derive(Eq, Debug)
pub struct GenerateChoice {
  line : LineChoice
  tuple : ModelTuple?
  model : Json
}

///|
pub extend GenerateChoice with Eq::{equal, not_equal}

///|
pub extend GenerateChoice with @debug.Debug::{to_repr}

///|
/// The numeric parts of an IR version name: `[4, 10, 0]` for `4.10.0`. A part
/// that is not a number is -1, so it orders first.
fn IrVersionName::parts(self : IrVersionName) -> Array[Int32] {
  self.text
  .split(".")
  .map(part => @string.parse_int(part) catch { _ => -1 })
  .collect()
}

///|
/// Orders two names part by part, with a missing part as 0: `4.10.0` after
/// `4.9.0`, `4.1` after `4.0.0`.
fn IrVersionName::order(self : IrVersionName, other : IrVersionName) -> Int32 {
  let left = self.parts()
  let right = other.parts()
  for i in 0..<@cmp.maximum(left.length(), right.length()) {
    let order = left.get(i).unwrap_or(0).compare(right.get(i).unwrap_or(0))
    if order != 0 {
      return order
    }
  }
  0
}

///|
/// The highest of the names, by number.
pub fn IrVersionName::highest(
  names : ArrayView[IrVersionName],
) -> IrVersionName? {
  names.fold(init=None, (highest, name) => {
    match highest {
      Some(other) if other.order(name) >= 0 => highest
      _ => Some(name)
    }
  })
}

///|
/// The IR versions of the model tuples, newest first.
let tuple_versions : Array[IrVersion] = [V4_0_0, V3_0_0]

///|
/// The model tuple version that this name selects: `3` and `3.0.0` select
/// `3.0.0`. A name that selects no tuple version is `None`.
fn IrVersionName::tuple_version(self : IrVersionName) -> IrVersion? {
  tuple_versions.iter().find_first(version => version.serves(self))
}

///|
/// The version as the user reads it: the tuple version when the name selects
/// one, for example `3.0.0` for `3`.
fn IrVersionName::display(self : IrVersionName) -> String {
  match self.tuple_version() {
    Some(version) => version.to_string()
    None => self.text
  }
}

///|
/// The claimed name of the IR version on MEP 0.1 that serves a selection: an
/// exact name, then the highest claimed version that `IrVersionName::serves`
/// the selection. A claim of a major version also serves the full name of a
/// tuple version of that major, because an integer format version `3` denotes
/// exactly `3.0.0` (`IrVersion::of_format_version`). `3.1.0` names no tuple
/// version, so a claim of `3` does not serve it.
fn legacy_ir_claim(
  claimed : Array[IrVersionName],
  selected : IrVersionName,
) -> IrVersionName? {
  if claimed.contains(selected) {
    return Some(selected)
  }
  match IrVersionName::highest(claimed.filter(name => name.serves(selected))) {
    Some(name) => Some(name)
    None => {
      guard selected.tuple_version() is Some(_) else { return None }
      let major : IrVersionName = { text: selected.major(), }
      if claimed.contains(major) {
        Some(major)
      } else {
        None
      }
    }
  }
}

///|
/// The fallback for a model request with no matching tuple, when the claims
/// show that the guest serves it on MEP 0.1: the guest claims that line, the
/// legacy method, and any requested IR version for the role of that method.
fn Claims::legacy_fallback(
  self : Claims,
  operation : ModelOperation,
  requested : IrVersionName?,
  codec : ModelCodec?,
  input : FallbackInput,
) -> LegacyFallback? {
  guard self.protocol_lines.contains(Mep0_1) &&
    operation.operation().legacy() is Some(legacy) &&
    self.offers(legacy) else {
    return None
  }
  let claimed = match operation {
    CompileModel => self.frontend_ir_versions
    GenerateModel => self.backend_ir_versions
  }
  let ir_version = match requested {
    None => None
    Some(selected) =>
      match legacy_ir_claim(claimed, selected) {
        Some(name) => Some(name)
        None => return None
      }
  }
  let model_ir_versions = tuple_versions.filter(version => {
    self.model_tuples
    .iter()
    .any(tuple => tuple.operation == operation && tuple.ir_version == version)
  })
  Some({
    extension_id: self.extension_id,
    version: self.version,
    operation: legacy,
    model_operation: operation,
    requested,
    codec,
    ir_version,
    input,
    model_ir_versions,
  })
}

///|
/// Whether the IR version of this fallback serves a `--ir-version` check, with
/// the same answer as on the model line: `3` and `3.0.0` both serve a document
/// of format version `3`.
pub fn LegacyFallback::serves(
  self : LegacyFallback,
  selected : IrVersionName,
) -> Bool {
  guard self.requested is Some(requested) else { return true }
  requested.serves(selected) ||
  (requested.tuple_version() is Some(version) && version.serves(selected))
}

///|
/// The warning for this fallback: the extension and its version, the requested
/// IR version, that the operation runs on legacy MEP 0.1, and what to do next.
/// `data` holds the same facts for a machine reader.
pub fn LegacyFallback::diagnostic(self : LegacyFallback) -> Diagnostic {
  let request = match (self.requested, self.codec) {
    (Some(requested), _) => "at IR \{requested.display()}"
    (None, Some(codec)) => "with \{codec}"
    (None, None) => "for this request"
  }
  let carried = match self.input {
    ModelEnvelope =>
      " The envelope's payload goes as plain IR, with its bytes unchanged; its modelId and revision do not go with it."
    Sources | PlainIr => ""
  }
  let update = match self.requested {
    Some(requested) => "the IR \{requested.display()} model tuple"
    None => "that model tuple"
  }
  let move_to = match self.model_ir_versions {
    [newest, ..] => ", or move to IR \{newest}"
    [] => ""
  }
  let data : Map[String, Json] = {
    "extension": {
      "id": self.extension_id.to_string(),
      "version": self.version.to_string(),
    },
    "operation": self.operation.to_string(),
    "protocolVersion": ProtocolLine::Mep0_1.to_string(),
    "input": self.input.to_string(),
    "modelIrVersions": Json::array(
      self.model_ir_versions.map(version => Json::string(version.to_string())),
    ),
  }
  if self.requested is Some(requested) {
    data["requestedIrVersion"] = Json::string(requested.display())
  }
  if self.ir_version is Some(name) {
    data["irVersion"] = Json::string(name.to_string())
  }
  if self.codec is Some(codec) {
    data["codec"] = Json::string(codec.to_string())
  }
  {
    severity: Warning,
    code: Some(legacy_fallback_code),
    message: "\{self.extension_id} \{self.version} claims no model tuple for \{self.model_operation} \{request}, so this operation runs on legacy MEP 0.1 with \{self.operation}.\{carried} Update the extension to a release that claims \{update}\{move_to}.",
    location: None,
    related: [],
    data: Some(Json::object(data)),
  }
}

///|
/// A tuple refusal with the reason that MEP 0.1 cannot serve the request either.
fn no_line(refusal : Refusal, reason : String) -> Refusal {
  guard refusal is Refusal(code~, message~)
  Refusal(code~, message="\{message}; \{reason}")
}

///|
/// Chooses the line of a compile (SES-3, SES-4). A guest that claims only MEP
/// 0.1 compiles on it. A guest on the model line compiles on it when a claimed
/// tuple matches the request. With no match, the guest compiles on MEP 0.1 with
/// a fallback when the claims show that it serves the request there. Otherwise
/// the choice raises `TupleUnavailable`.
///
/// MEP 0.1 returns Morphir JSON, so it cannot carry a requirement of Ion or of
/// the `morphir-model` profile. `model_only` says that the request has an
/// option that only the model line has, for example `--frontend-profile`.
pub fn LineChoice::compile(
  claims : Claims,
  profile? : ModelProfile,
  codec? : ModelCodec,
  ir_version? : IrVersionName,
  model_only~ : Bool = false,
) -> LineChoice raise Refusal {
  try
    Offer::select(
      claims,
      claims.compile_operation(),
      profile?,
      codec?,
      ir_version?,
    )
  catch {
    Refusal(code=TupleUnavailable, ..) as refusal => {
      if model_only {
        raise no_line(refusal, "MEP 0.1 cannot carry this request's options")
      }
      if codec is Some(IonBinary) {
        raise no_line(refusal, "MEP 0.1 cannot carry \{IonBinary}")
      }
      if profile is Some(MorphirModel) {
        raise no_line(refusal, "MEP 0.1 cannot carry \{MorphirModel}")
      }
      guard claims.legacy_fallback(CompileModel, ir_version, codec, Sources)
        is Some(fallback) else {
        raise no_line(
          refusal, "its claims on MEP 0.1 do not serve this request",
        )
      }
      { offer: Legacy, fallback: Some(fallback), }
    }
    error => raise error
  } noraise {
    offer => { offer, fallback: None, }
  }
}

///|
/// The version name of a plain IR document's `formatVersion`: `3` for the
/// integer 3, `3.0.0` for that text. Any other value names nothing.
fn format_version_name(ir : Json) -> IrVersionName? {
  let text = match field_at(ir, ["formatVersion"]) {
    Some(String(text)) => text
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int().to_string()
    _ => return None
  }
  try IrVersionName::parse(text) catch {
    _ => None
  } noraise {
    name => Some(name)
  }
}

///|
/// Chooses the line of a generate from a plain Morphir IR document. A guest on
/// the model line gets the document wrapped at the tuple of its format version
/// when it claims that tuple (`WrappedPlainIr`). With no claimed tuple, the
/// guest gets the document as it is on MEP 0.1, with a fallback, when it claims
/// that version for the backend role on that line. A guest that claims only MEP
/// 0.1 gets the document as it is, and the caller checks the version.
pub fn GenerateChoice::of_plain_ir(
  claims : Claims,
  document : Bytes,
  ir : Json,
) -> GenerateChoice raise Refusal {
  guard claims.on_model_line() else {
    return {
      line: { offer: Offer::select(claims, Generate), fallback: None, },
      tuple: None,
      model: ir,
    }
  }
  try {
    let wrapped = WrappedPlainIr::of(document, ir)
    let offer = Offer::of_model(claims, wrapped.tuple)
    {
      line: { offer, fallback: None, },
      tuple: Some(wrapped.tuple),
      model: wrapped.envelope,
    }
  } catch {
    Refusal(code=TupleUnavailable, ..) as refusal => {
      guard format_version_name(ir) is Some(format) &&
        claims.legacy_fallback(GenerateModel, Some(format), None, PlainIr)
        is Some(fallback) else {
        raise no_line(
          refusal, "its claims on MEP 0.1 do not serve this document",
        )
      }
      {
        line: { offer: Legacy, fallback: Some(fallback), },
        tuple: None,
        model: ir,
      }
    }
    error => raise error
  }
}

///|
/// The exact bytes of a `morphir-ir` envelope's payload, as a document that
/// MEP 0.1 can carry without a change: one document, nothing in `critical` or
/// `evidence` that a plain document would lose, and a payload that matches its
/// declared length and digest.
fn unwrap_envelope(envelope : Json, tuple : ModelTuple) -> Json raise {
  let refuse = (reason : String) => {
    Refusal(
      code=TupleUnavailable,
      message="the model envelope cannot go on MEP 0.1: \{reason}",
    )
  }
  guard field_at(envelope, ["payload", "layout"])
    is Some(String("single-document")) else {
    raise refuse("its payload is not a single document")
  }
  for field in ["evidence", "critical"] {
    match field_at(envelope, [field]) {
      None | Some(Array([])) => ()
      Some(_) => raise refuse("a plain document has no \{field}")
    }
  }
  guard field_at(envelope, ["payload", "content"]) is Some(String(content)) else {
    raise InvalidModelEnvelope("its payload has no content")
  }
  let bytes = @base64.decode(content) catch {
    _ => raise InvalidModelEnvelope("its payload content is not base64")
  }
  guard integer(field_at(envelope, ["payload", "decodedByteLength"]))
    is Some(declared) &&
    declared == bytes.length() else {
    raise InvalidModelEnvelope(
      "its payload has \{bytes.length()} bytes, which is not its decodedByteLength",
    )
  }
  guard field_at(envelope, ["payload", "sha256"]) is Some(String(digest)) &&
    digest == Sha256::of(bytes).to_string() else {
    raise InvalidModelEnvelope("its payload does not match its sha256")
  }
  let document = parse_model_document(bytes) catch {
    _ =>
      raise InvalidModelEnvelope("its payload is not a bounded JSON document")
  }
  guard field_at(document, ["formatVersion"]).bind(IrVersion::of_format_version)
    is Some(version) &&
    version == tuple.ir_version else {
    raise InvalidModelEnvelope(
      "the formatVersion of its payload is not IR \{tuple.ir_version}",
    )
  }
  document
}

///|
/// Chooses the line of a generate from a model envelope. A guest that claims
/// the envelope's tuple gets the envelope as it is. With no claimed tuple, a
/// `morphir-ir` and `morphir-json` envelope can still go on MEP 0.1: its payload
/// is plain Morphir IR, so the guest gets that document, with a fallback, when
/// it claims that version for the backend role on that line. The payload's bytes
/// do not change, and the warning says that the envelope's identity stays
/// behind. An Ion or `morphir-model` envelope has no plain form without a
/// conversion, so it stays `TupleUnavailable` (SES-4).
///
/// It raises `InvalidModelEnvelope` when the payload does not match what the
/// envelope declares, because the host cannot then say what the document is.
pub fn GenerateChoice::of_envelope(
  claims : Claims,
  envelope : Json,
  tuple : ModelTuple,
) -> GenerateChoice raise {
  try {
    let offer = Offer::of_model(claims, tuple)
    { line: { offer, fallback: None, }, tuple: Some(tuple), model: envelope, }
  } catch {
    Refusal(code=TupleUnavailable, ..) as refusal => {
      guard tuple.profile is MorphirIr && tuple.codec is MorphirJson else {
        raise no_line(
          refusal,
          "MEP 0.1 carries only \{MorphirIr} with \{MorphirJson}, and the host does not convert a model",
        )
      }
      let requested : IrVersionName = { text: tuple.ir_version.to_string(), }
      guard claims.legacy_fallback(
          GenerateModel,
          Some(requested),
          None,
          ModelEnvelope,
        )
        is Some(fallback) else {
        raise no_line(refusal, "its claims on MEP 0.1 do not serve this model")
      }
      {
        line: { offer: Legacy, fallback: Some(fallback), },
        tuple: None,
        model: unwrap_envelope(envelope, tuple),
      }
    }
    error => raise error
  }
}

///|
/// Decodes a model document under the host's bounds: depth 128, 100,000 nodes
/// and 4 MiB of strings. Duplicate keys are refused.
pub fn parse_model_document(bytes : Bytes) -> Json raise {
  @model_wire.parse_bounded(
    @utf8.decode(bytes[:]),
    max_depth=128,
    max_nodes=100000,
    max_string_units=4194304,
  )
}
