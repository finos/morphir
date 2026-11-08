///|
/// Bounds on one model transfer. The host enforces the encoded and decoded
/// byte limits, and checks the decoded length that a payload declares. The
/// depth and node limits are negotiated; the party that decodes the model
/// enforces them.
#derive(Eq, Debug)
pub struct ModelLimits {
  encoded_bytes : Int32
  decoded_bytes : Int32
  depth : Int32
  nodes : Int32
}

///|
pub extend ModelLimits with Eq::{equal, not_equal}

///|
pub extend ModelLimits with @debug.Debug::{to_repr}

///|
fn positive(name : String, value : Int32) -> Int32 raise ValueError {
  guard value > 0 else { raise InvalidLimit("\{name}=\{value}") }
  value
}

///|
pub fn ModelLimits::new(
  encoded_bytes~ : Int32,
  decoded_bytes~ : Int32,
  depth~ : Int32,
  nodes~ : Int32,
) -> ModelLimits raise ValueError {
  {
    encoded_bytes: positive("encoded_bytes", encoded_bytes),
    decoded_bytes: positive("decoded_bytes", decoded_bytes),
    depth: positive("depth", depth),
    nodes: positive("nodes", nodes),
  }
}

///|
/// Bounds on the messages of one session.
#derive(Eq, Debug)
pub struct Limits {
  request_bytes : Int32
  response_bytes : Int32
  model : ModelLimits
  /// The instruction budget of one guest call, where the engine meters
  /// instructions.
  call_instructions : Int32
}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub fn Limits::new(
  request_bytes~ : Int32,
  response_bytes~ : Int32,
  model~ : ModelLimits,
  call_instructions~ : Int32 = model_call_instructions,
) -> Limits raise ValueError {
  {
    request_bytes: positive("request_bytes", request_bytes),
    response_bytes: positive("response_bytes", response_bytes),
    model,
    call_instructions: positive("call_instructions", call_instructions),
  }
}

///|
/// The largest framed request of a call that carries no model payload: a compile
/// call, or any call of a MEP 0.1 session. A guest on MEP 0.1 has this bound on
/// every runtime.
let call_frame_bytes : Int32 = 4 * 1024 * 1024

///|
/// The instruction budget of one guest call on the model line: the largest that
/// the engine accepts, because WAMR holds the count in a C `int`. A call on
/// MEP 0.1, and a probe, keep the budget of the restricted Extism profile.
let model_call_instructions : Int32 = 2147483647

///|
/// The host's own limits: a 6 MiB framed request, a 16 MiB response and model
/// limits of 4 MiB decoded, 5,592,408 encoded bytes, depth 128 and 100,000
/// nodes, and 2,147,483,647 instructions for one guest call.
///
/// The encoded limit is 4 * ceil(4194304 / 3), the base64 length of the decoded
/// limit. The frame must hold that and the envelope, the method and the other
/// parameters, about 1 KiB for a plain IR file. The 6 MiB frame leaves 699,048
/// bytes for them. Only a generate call on the model line uses a frame over
/// `call_frame_bytes`.
pub fn Limits::host() -> Limits {
  {
    request_bytes: 6 * 1024 * 1024,
    response_bytes: 16 * 1024 * 1024,
    model: {
      encoded_bytes: 5592408,
      decoded_bytes: 4 * 1024 * 1024,
      depth: 128,
      nodes: 100000,
    },
    call_instructions: model_call_instructions,
  }
}
