///|
/// A check that refused work before the host sent an operation.
pub(all) suberror Refusal {
  Refusal(code~ : RefusalCode, message~ : String)
} derive(Eq, Debug)

///|
pub extend Refusal with Eq::{equal, not_equal}

///|
pub extend Refusal with @debug.Debug::{to_repr}

///|
/// What the host offers in `initialize`: MEP 0.1 for the legacy compile and
/// generate methods, or MEP 0.2.0-draft.1 with exactly one model tuple.
pub(all) enum Offer {
  Legacy
  Model(ModelTuple)
} derive(Eq, Debug)

///|
pub extend Offer with Eq::{equal, not_equal}

///|
pub extend Offer with @debug.Debug::{to_repr}

///|
pub fn Offer::line(self : Offer) -> ProtocolLine {
  match self {
    Legacy => Mep0_1
    Model(_) => Mep0_2Draft1
  }
}

///|
/// The operations a session with this offer can call.
pub fn Offer::operations(self : Offer) -> Array[Operation] {
  match self {
    Legacy => [Compile, Generate]
    Model(tuple) => [tuple.operation.operation()]
  }
}

///|
/// The host's codec preference, best first: Ion, then JSON.
let codec_preference : Array[ModelCodec] = [IonBinary, MorphirJson]

///|
/// Picks the offer for an operation from an extension's claims, usually the
/// claims of a describe probe. A model operation takes a claimed tuple that
/// matches the operation and the optional profile and codec. When several
/// match, the host's preference decides (Ion, then JSON), not the order in
/// which the worker declared them. It raises `Refusal` when the claims cannot
/// serve the operation.
pub fn Offer::select(
  claims : Claims,
  operation : Operation,
  profile? : ModelProfile,
  codec? : ModelCodec,
) -> Offer raise Refusal {
  guard claims.offers(operation) else {
    raise Refusal(
      code=CapabilityUnavailable,
      message="\{claims.extension_id} does not claim \{operation}",
    )
  }
  guard claims.protocol_lines.contains(operation.protocol_line()) else {
    raise Refusal(
      code=ProtocolUnavailable,
      message="\{claims.extension_id} does not claim MEP \{operation.protocol_line()}",
    )
  }
  guard operation.model() is Some(model) else { return Legacy }
  let matching = claims.model_tuples.filter(tuple => {
    tuple.operation == model &&
    (profile is None || profile == Some(tuple.profile)) &&
    (codec is None || codec == Some(tuple.codec))
  })
  for preferred in codec_preference {
    if matching.search_by(tuple => tuple.codec == preferred) is Some(index) {
      return Model(matching[index])
    }
  }
  raise Refusal(
    code=TupleUnavailable,
    message="\{claims.extension_id} claims no matching tuple for \{operation}",
  )
}

///|
let max_deadline_ms : Int32 = 594000

///|
/// The time a whole session may take, from the start of its worker to its
/// stop: 60,000 ms by default and at most 594,000 ms.
pub struct Deadline {
  priv ms : Int32
} derive(Eq, Debug)

///|
pub extend Deadline with Eq::{equal, not_equal}

///|
pub extend Deadline with @debug.Debug::{to_repr}

///|
pub fn Deadline::default() -> Deadline {
  { ms: 60000, }
}

///|
pub fn Deadline::of_ms(ms : Int32) -> Deadline raise ValueError {
  guard ms > 0 && ms <= max_deadline_ms else { raise InvalidDeadline(ms) }
  { ms, }
}

///|
pub fn Deadline::ms(self : Deadline) -> Int32 {
  self.ms
}

///|
/// The smaller of each pair of model limits: the effective limits when a
/// worker declares its own.
pub fn ModelLimits::min(self : ModelLimits, other : ModelLimits) -> ModelLimits {
  {
    encoded_bytes: @cmp.minimum(self.encoded_bytes, other.encoded_bytes),
    decoded_bytes: @cmp.minimum(self.decoded_bytes, other.decoded_bytes),
    depth: @cmp.minimum(self.depth, other.depth),
    nodes: @cmp.minimum(self.nodes, other.nodes),
  }
}

///|
pub extend ModelLimits with ToJson::{to_json}

///|
pub impl ToJson for ModelLimits with fn to_json(self) {
  {
    "maxEncodedBytes": self.encoded_bytes,
    "maxDecodedBytes": self.decoded_bytes,
    "maxDepth": self.depth,
    "maxNodes": self.nodes,
  }
}

///|
pub extend Limits with ToJson::{to_json}

///|
pub impl ToJson for Limits with fn to_json(self) {
  {
    "requestBytes": self.request_bytes,
    "responseBytes": self.response_bytes,
    "model": self.model.to_json(),
  }
}

///|
pub extend ModelTuple with ToJson::{to_json}

///|
pub impl ToJson for ModelTuple with fn to_json(self) {
  {
    "operation": self.operation.to_string(),
    "profile": self.profile.to_string(),
    "codec": self.codec.to_string(),
    "envelopeVersion": self.envelope_version.to_string(),
    "irVersion": self.ir_version.to_string(),
  }
}

///|
/// The restricted Extism profile that applies to MEP 0.1 WASM guests: a
/// 256 MiB memory ceiling, 1,000,000,000 instructions and 30,000 ms for each
/// guest call, 4 MiB of input and 16 MiB of output. The WASM launcher
/// enforces memory, instructions and call time; the session enforces input
/// and output through its request and response limits.
pub struct ExtismProfile {
  memory_bytes : Int32
  instructions : Int64
  call_ms : Int32
  input_bytes : Int32
  output_bytes : Int32
} derive(Eq, Debug)

///|
pub extend ExtismProfile with Eq::{equal, not_equal}

///|
pub extend ExtismProfile with @debug.Debug::{to_repr}

///|
pub fn ExtismProfile::restricted() -> ExtismProfile {
  {
    memory_bytes: 256 * 1024 * 1024,
    instructions: 1000000000L,
    call_ms: 30000,
    input_bytes: 4 * 1024 * 1024,
    output_bytes: 16 * 1024 * 1024,
  }
}

///|
pub extend ExtismProfile with ToJson::{to_json}

///|
pub impl ToJson for ExtismProfile with fn to_json(self) {
  {
    "memoryBytes": self.memory_bytes,
    "instructions": self.instructions.to_double(),
    "callMs": self.call_ms,
    "inputBytes": self.input_bytes,
    "outputBytes": self.output_bytes,
  }
}

///|
/// The limits for one session: the host limits, and for a MEP 0.1 WASM guest
/// the request and response bounds of the restricted Extism profile.
pub fn Limits::for_session(
  self : Limits,
  offer : Offer,
  runtime : WorkerRuntime,
) -> Limits {
  match (offer, runtime) {
    (Legacy, Wasm(..)) => {
      let profile = ExtismProfile::restricted()
      {
        ..self,
        request_bytes: @cmp.minimum(self.request_bytes, profile.input_bytes),
        response_bytes: @cmp.minimum(self.response_bytes, profile.output_bytes),
      }
    }
    _ => self
  }
}

///|
/// What activation agreed with a worker: the offer it accepted and the
/// effective limits.
pub struct Negotiated {
  offer : Offer
  limits : Limits
} derive(Eq, Debug)

///|
pub extend Negotiated with Eq::{equal, not_equal}

///|
pub extend Negotiated with @debug.Debug::{to_repr}

///|
/// Which kind of call a request makes. The negotiated protocol line chooses
/// the method.
priv enum CallKind {
  CompileCall
  GenerateCall
} derive(Eq, Debug)

///|
fn CallKind::operation(self : CallKind, offer : Offer) -> Operation {
  match (self, offer) {
    (CompileCall, Legacy) => Compile
    (GenerateCall, Legacy) => Generate
    (CompileCall, Model(_)) => CompileModel
    (GenerateCall, Model(_)) => GenerateModel
  }
}

///|
/// The ID of the operation request in a fresh session, after `initialize`.
/// `Call::make` uses it to size a request before the session exists.
let first_operation_id : Int32 = 2

///|
/// The bytes of a Content-Length frame that carries `body` bytes.
fn framed_size(body : Int32) -> Int32 {
  "Content-Length: \{body}\r\n\r\n".length() + body
}

///|
priv struct Call {
  kind : CallKind
  params : Map[String, Json]
} derive(Eq, Debug)

///|
let placeholder_tuple : ModelTuple = {
  operation: CompileModel,
  profile: MorphirModel,
  codec: MorphirJson,
  envelope_version: V0_1_0Draft1,
  ir_version: V4_0_0,
}

///|
/// Checks a call against the host's 4 MiB framed request limit when it is
/// made, so that an oversized request is refused before any worker starts.
fn Call::make(
  kind : CallKind,
  params : Map[String, Json],
) -> Call raise Refusal {
  let call = { kind, params: params.copy(), }
  // The model method is the longer name, so this bound holds on either line.
  let size = framed_size(
    call
    .message(first_operation_id, kind.operation(Model(placeholder_tuple)))
    .size(),
  )
  let limit = Limits::host().request_bytes
  guard size <= limit else {
    raise Refusal(
      code=RequestLimit,
      message="the request frame has \{size} bytes; the limit is \{limit}",
    )
  }
  call
}

///|
fn Call::message(self : Call, id : Int32, operation : Operation) -> Message {
  Message::new({
    "jsonrpc": "2.0",
    "id": id,
    "method": operation.to_string(),
    "params": Json::object(self.params),
  })
}

///|
/// The guest-facing parameters of one compile call, for example
/// `languageId`, `sources` and `package`, and `output` on the model line.
pub struct CompileRequest {
  priv call : Call
} derive(Eq, Debug)

///|
pub extend CompileRequest with Eq::{equal, not_equal}

///|
pub extend CompileRequest with @debug.Debug::{to_repr}

///|
pub fn CompileRequest::new(
  params : Map[String, Json],
) -> CompileRequest raise Refusal {
  { call: Call::make(CompileCall, params), }
}

///|
/// The guest-facing parameters of one generate call, for example `ir` and
/// `target`, or `model`, `input` and `target` on the model line.
pub struct GenerateRequest {
  priv call : Call
} derive(Eq, Debug)

///|
pub extend GenerateRequest with Eq::{equal, not_equal}

///|
pub extend GenerateRequest with @debug.Debug::{to_repr}

///|
pub fn GenerateRequest::new(
  params : Map[String, Json],
) -> GenerateRequest raise Refusal {
  { call: Call::make(GenerateCall, params), }
}

///|
/// The guest's answer to a compile call that succeeded.
pub struct Compiled {
  result : Json
} derive(Eq, Debug)

///|
pub extend Compiled with Eq::{equal, not_equal}

///|
pub extend Compiled with @debug.Debug::{to_repr}

///|
pub fn Compiled::new(result : Json) -> Compiled {
  { result, }
}

///|
/// The guest's answer to a generate call that succeeded.
pub struct Generated {
  result : Json
} derive(Eq, Debug)

///|
pub extend Generated with Eq::{equal, not_equal}

///|
pub extend Generated with @debug.Debug::{to_repr}

///|
pub fn Generated::new(result : Json) -> Generated {
  { result, }
}
