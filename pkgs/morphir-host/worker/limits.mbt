///|
/// Bounds on one model transfer. The host enforces the encoded and decoded
/// byte limits, and checks the decoded length that a payload declares. The
/// depth and node limits are negotiated; the party that decodes the model
/// enforces them.
pub struct ModelLimits {
  encoded_bytes : Int32
  decoded_bytes : Int32
  depth : Int32
  nodes : Int32
} derive(Eq, Debug)

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
pub struct Limits {
  request_bytes : Int32
  response_bytes : Int32
  model : ModelLimits
} derive(Eq, Debug)

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub fn Limits::new(
  request_bytes~ : Int32,
  response_bytes~ : Int32,
  model~ : ModelLimits,
) -> Limits raise ValueError {
  {
    request_bytes: positive("request_bytes", request_bytes),
    response_bytes: positive("response_bytes", response_bytes),
    model,
  }
}

///|
/// The host's own limits: a 4 MiB framed request, a 16 MiB response and model
/// limits of 2 MiB decoded, 2,796,204 encoded bytes, depth 128 and 100,000
/// nodes.
pub fn Limits::host() -> Limits {
  {
    request_bytes: 4 * 1024 * 1024,
    response_bytes: 16 * 1024 * 1024,
    model: {
      encoded_bytes: 2796204,
      decoded_bytes: 2 * 1024 * 1024,
      depth: 128,
      nodes: 100000,
    },
  }
}
