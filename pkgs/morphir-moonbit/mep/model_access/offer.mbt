///|
pub const PROTOCOL : String = "0.2.0-draft.2"

///|
pub const ACCESS_VERSION : String = "0.1.0-draft.1"

///|
pub const CONTEXT_SCHEMA : String = "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json"

///|
pub const START : String = "morphir.backend.generateModel.start"

///|
pub const ADVANCE : String = "morphir.backend.generateModel.advance"

///|
pub const CANCEL : String = "morphir.backend.generateModel.cancel"

///|
#derive(Eq, Debug)
pub(all) enum IrVersion {
  V3_1
  V4
}

///|
pub extend IrVersion with Eq::{equal, not_equal}

///|
pub extend IrVersion with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum Codec {
  MorphirJson
  MorphirYaml
}

///|
pub extend Codec with Eq::{equal, not_equal}

///|
pub extend Codec with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum Encoding {
  Plain
  ContextualDraft1
}

///|
pub extend Encoding with Eq::{equal, not_equal}

///|
pub extend Encoding with @debug.Debug::{to_repr}

///|
/// One complete bounded offer. The fixed draft, profile, operation and layout
/// are checked at decoding and cannot be changed by assembling a tuple.
#derive(Eq, Debug)
pub(all) struct AccessTuple {
  ir : IrVersion
  codec : Codec
  encoding : Encoding
}

///|
pub extend AccessTuple with Eq::{equal, not_equal}

///|
pub extend AccessTuple with @debug.Debug::{to_repr}

///|
fn tuple_text(value : Json, key : String) -> String raise @wire.CodecError {
  @wire.string(@wire.field(value, key))
}

///|
pub fn AccessTuple::from_json(
  value : Json,
) -> AccessTuple raise @wire.CodecError {
  guard tuple_text(value, "protocolVersion") == PROTOCOL &&
    tuple_text(value, "accessVersion") == ACCESS_VERSION &&
    tuple_text(value, "operation") == "morphir.backend.generateModel" &&
    tuple_text(value, "profile") == "morphir-ir" &&
    tuple_text(value, "layout") == "document-tree" else {
    raise @wire.Invalid(
      "model_access.invalid_tuple", "Expected a draft.2 bounded generation tuple",
    )
  }
  let ir = match tuple_text(value, "irVersion") {
    "3.1.0" => V3_1
    "4.0.0" => V4
    other =>
      raise @wire.Invalid(
        "model_access.invalid_tuple",
        "Unsupported IR version \{other}",
      )
  }
  let codec = match tuple_text(value, "codec") {
    "morphir-json" => MorphirJson
    "morphir-yaml" => MorphirYaml
    other =>
      raise @wire.Invalid(
        "model_access.invalid_tuple",
        "Unsupported codec \{other}",
      )
  }
  let encoding = match tuple_text(value, "contextualEncoding") {
    "plain" => Plain
    value if value == CONTEXT_SCHEMA => ContextualDraft1
    other =>
      raise @wire.Invalid(
        "model_access.invalid_tuple",
        "Unsupported context encoding \{other}",
      )
  }
  { ir, codec, encoding, }
}

///|
pub fn AccessTuple::to_json(self : AccessTuple) -> Json {
  {
    "protocolVersion": PROTOCOL,
    "accessVersion": ACCESS_VERSION,
    "operation": "morphir.backend.generateModel",
    "irVersion": match self.ir {
      V3_1 => "3.1.0"
      V4 => "4.0.0"
    },
    "profile": "morphir-ir",
    "codec": match self.codec {
      MorphirJson => "morphir-json"
      MorphirYaml => "morphir-yaml"
    },
    "layout": "document-tree",
    "contextualEncoding": match self.encoding {
      Plain => "plain"
      ContextualDraft1 => CONTEXT_SCHEMA
    },
  }
}

///|
// maxFrameBytes is the first entry in limit_names.
const FRAME_BYTES_INDEX : Int32 = 0

///|
const GUEST_STATE_BYTES_INDEX : Int32 = 8

///|
const ENCODED_BYTES_INDEX : Int32 = 1

///|
const DECODED_BYTES_INDEX : Int32 = 2

///|
const DOCUMENT_COUNT_INDEX : Int32 = 3

///|
let limit_names : Array[String] = [
  "maxFrameBytes", "maxEncodedBytesPerExchange", "maxDecodedBytesPerExchange", "maxDocumentsPerBatch",
  "maxDepth", "maxNodes", "maxDiagnosticsPerExchange", "maxOutstandingRequests",
  "maxGuestStateBytes", "maxHostCacheBytes", "maxArtifactChunkBytes", "maxArtifactBytes",
  "maxTotalArtifactBytes", "maxSessionDiskBytes", "maxSessionWorkUnits", "maxRounds",
  "maxCallMilliseconds", "maxSessionMilliseconds",
]

///|
/// Validated positive limits in the fixed order of the draft. Each value fits
/// the JSON interoperable integer range, including byte ceilings above Int32.
#derive(Eq, Debug)
pub struct Limits {
  priv values : Array[Int64]
}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub fn Limits::from_json(value : Json) -> Limits raise @wire.CodecError {
  let values = limit_names.map(name => {
    let number = @strconv.parse_int64(
      @wire.integer_text(@wire.field(value, name)),
    ) catch {
      _ => raise @wire.Invalid("model_access.invalid_limit", name)
    }
    let ceiling = match name {
      "maxArtifactBytes"
      | "maxTotalArtifactBytes"
      | "maxSessionDiskBytes"
      | "maxSessionWorkUnits" => 9007199254740991L
      _ => 2147483647L
    }
    guard number > 0L && number <= ceiling else {
      raise @wire.Invalid("model_access.invalid_limit", name)
    }
    number
  })
  { values, }
}

///|
pub fn Limits::to_json(self : Limits) -> Json {
  let fields : Map[String, Json] = Map([])
  for index, name in limit_names {
    let value = self.values[index]
    fields[name] = Json::number(value.to_double(), repr=value.to_string())
  }
  Json::object(fields)
}

///|
pub fn Limits::bound(self : Limits, peer : Limits) -> Limits {
  {
    values: self.values.mapi((index, value) => {
      if value < peer.values[index] {
        value
      } else {
        peer.values[index]
      }
    }),
  }
}

///|
pub fn Limits::frame_bytes(self : Limits) -> Int64 {
  self.values[FRAME_BYTES_INDEX]
}

///|
pub fn Limits::guest_state_bytes(self : Limits) -> Int32 {
  self.values[GUEST_STATE_BYTES_INDEX].to_int()
}

///|
pub fn Limits::at_most(self : Limits, ceiling : Limits) -> Bool {
  self == self.bound(ceiling)
}

///|
#derive(Eq, Debug)
pub struct Support {
  priv tuples : Array[AccessTuple]
  limits : Limits
}

///|
pub extend Support with Eq::{equal, not_equal}

///|
pub extend Support with @debug.Debug::{to_repr}

///|
pub fn Support::from_json(value : Json) -> Support raise @wire.CodecError {
  let limits = Limits::from_json(@wire.field(value, "limits"))
  let tuples : Array[AccessTuple] = []
  for item in @wire.array(@wire.field(value, "tuples")) {
    let tuple = AccessTuple::from_json(item)
    guard !tuples.contains(tuple) else {
      raise @wire.Invalid(
        "model_access.duplicate_tuple", "Bounded offers must contain each tuple once",
      )
    }
    tuples.push(tuple)
  }
  { tuples, limits, }
}

///|
pub fn Support::tuples(self : Support) -> Array[AccessTuple] {
  [..self.tuples]
}

///|
pub fn Support::to_json(self : Support) -> Json {
  {
    "tuples": self.tuples.map(tuple => tuple.to_json()),
    "limits": self.limits.to_json(),
  }
}

///|
/// Reduces the offer to both physical directions of its transport.
pub fn Support::cap_frame(
  self : Support,
  ceiling : Int32,
) -> Support raise @wire.CodecError {
  guard ceiling > 0 else {
    raise @wire.Invalid("model_access.invalid_limit", "maxFrameBytes")
  }
  if self.limits.frame_bytes() <= ceiling.to_int64() {
    return self
  }
  let values = self.limits.values.copy()
  values[FRAME_BYTES_INDEX] = ceiling.to_int64()
  { ..self, limits: { values, }, }
}

///|
pub fn Support::intersect(self : Support, guest : Support) -> Support {
  {
    tuples: self.tuples.filter(tuple => guest.tuples.contains(tuple)),
    limits: self.limits.bound(guest.limits),
  }
}

///|
pub fn Limits::rounds(self : Limits) -> Int32 {
  self.values[limit_names.search("maxRounds").unwrap()].to_int()
}

///|
pub fn Limits::diagnostics_per_exchange(self : Limits) -> Int32 {
  self.values[limit_names.search("maxDiagnosticsPerExchange").unwrap()].to_int()
}

///|
pub fn Limits::call_milliseconds(self : Limits) -> Int32 {
  self.values[16].to_int()
}

///|
pub fn Limits::session_milliseconds(self : Limits) -> Int32 {
  self.values[17].to_int()
}

///|
pub fn Limits::outstanding_requests(self : Limits) -> Int32 {
  self.values[limit_names.search("maxOutstandingRequests").unwrap()].to_int()
}
