///|
const MODEL_PROTOCOL : String = "0.2.0-draft.1"

///|
const MODEL_ENVELOPE : String = "0.1.0-draft.1"

///|
const GENERATE_MODEL : String = "morphir.backend.generateModel"

///|
priv suberror ModelError {
  Refused(String)
}

///|
priv struct ModelLimits {
  encoded : Int32
  decoded : Int32
  depth : Int32
  nodes : Int32
}

///|
priv struct ModelTransport {
  tuples : Array[Json]
  limits : ModelLimits
}

///|
fn model_tuple(profile : String, codec : String) -> Json {
  {
    "operation": GENERATE_MODEL,
    "profile": profile,
    "codec": codec,
    "envelopeVersion": MODEL_ENVELOPE,
    "irVersion": "4.0.0",
  }
}

///|
fn model_support() -> ModelTransport {
  {
    tuples: [
      model_tuple("morphir-model", "ion-binary"),
      model_tuple("morphir-ir", "morphir-json"),
    ],
    // MEP counts every value, including scalar leaves, from root depth one.
    // This bound also stays within Ion's separate container-depth ceiling.
    limits: { encoded: 5592408, decoded: 4194304, depth: 128, nodes: 100000, },
  }
}

///|
fn ModelTransport::to_json(self : ModelTransport) -> Json {
  {
    "tuples": self.tuples.map(tuple_snapshot),
    "limits": {
      "maxEncodedBytes": self.limits.encoded,
      "maxDecodedBytes": self.limits.decoded,
      "maxDepth": self.limits.depth,
      "maxNodes": self.limits.nodes,
    },
    "guarantees": [],
  }
}

///|
fn model_positive(value : Json) -> Int32 raise {
  let n = @strconv.parse_int(@wire.integer_text(value))
  guard n > 0 else { raise Refused("invalid_limits") }
  n
}

///|
fn model_text(value : Json) -> String raise {
  let text = @wire.string(value)
  guard !text.trim().is_empty() else { raise Refused("invalid_identity") }
  text
}

///|
fn read_support(value : Json) -> ModelTransport raise {
  let limits = @wire.field(value, "limits")
  let limits = {
    encoded: model_positive(@wire.field(limits, "maxEncodedBytes")),
    decoded: model_positive(@wire.field(limits, "maxDecodedBytes")),
    depth: model_positive(@wire.field(limits, "maxDepth")),
    nodes: model_positive(@wire.field(limits, "maxNodes")),
  }
  let guarantees = @wire.optional(value, "guarantees")
    .map(@wire.array)
    .unwrap_or([])
  let seen : Map[String, Bool] = Map([])
  for guarantee in guarantees {
    let text = model_text(guarantee)
    guard !seen.contains(text) else { raise Refused("invalid_support") }
    seen[text] = true
  }
  let tuples = @wire.array(@wire.field(value, "tuples"))
  let selected : Array[Json] = []
  for tuple in tuples {
    @wire.fields(tuple, [
      "operation", "profile", "codec", "envelopeVersion", "irVersion",
    ])
    let operation = @wire.string(@wire.field(tuple, "operation"))
    let profile = @wire.string(@wire.field(tuple, "profile"))
    let codec = @wire.string(@wire.field(tuple, "codec"))
    let envelope = @wire.string(@wire.field(tuple, "envelopeVersion"))
    let version = @version.FormatVersion::parse(
      @wire.string(@wire.field(tuple, "irVersion")),
    )
    guard [GENERATE_MODEL, "morphir.frontend.compileModel"].contains(operation) &&
      envelope == MODEL_ENVELOPE &&
      (version.major == 3U || version.major == 4U) &&
      (
        (profile == "morphir-model" && codec == "ion-binary") ||
        (profile == "morphir-ir" && codec == "morphir-json")
      ) &&
      !selected.contains(tuple) else {
      raise Refused("invalid_support")
    }
    selected.push(tuple)
  }
  { tuples: selected, limits, }
}

///|
fn select_models(value : Json) -> ModelTransport raise {
  let host = read_support(value)
  let guest = model_support()
  {
    tuples: host.tuples
    .filter(t => guest.tuples.contains(t))
    .map(tuple_snapshot),
    limits: {
      encoded: min_limit(host.limits.encoded, guest.limits.encoded),
      decoded: min_limit(host.limits.decoded, guest.limits.decoded),
      depth: min_limit(host.limits.depth, guest.limits.depth),
      nodes: min_limit(host.limits.nodes, guest.limits.nodes),
    },
  }
}

///|
fn min_limit(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn tuple_snapshot(tuple : Json) -> Json {
  let members = Map([])
  for name in ["operation", "profile", "codec", "envelopeVersion", "irVersion"] {
    members[name] = field(tuple, name)
  }
  Json::object(members)
}

///|
fn model_digest(value : Json) -> String raise {
  let text = @wire.string(value)
  guard text.length() == 64 &&
    text.to_array().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) else {
    raise Refused("invalid_digest")
  }
  text
}

///|
fn model_sha256(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}
