///|
// A MoonBit adapter carrier, not a registered MEP enrichment vocabulary.
const NODE_METADATA_OWNER : String = "urn:finos:morphir-moonbit:node-metadata:v1"

///|
priv struct RetainedInput {
  input : @generator.Input
  bytes : Bytes
  model : Json
}

///|
fn ion_member(value : @ion.IonValue, name : String) -> @ion.IonValue raise {
  guard value.kind() is Struct(fields) else { raise Refused("invalid_profile") }
  let matches = fields.filter(f => f.name().text() == Some(name))
  guard matches.length() == 1 else { raise Refused("invalid_profile") }
  matches[0].value()
}

///|
fn ion_string(value : @ion.IonValue) -> String raise {
  guard value.kind() is String(text) && !text.trim().is_empty() else {
    raise Refused("invalid_profile")
  }
  text
}

///|
fn ion_list(value : @ion.IonValue) -> Array[@ion.IonValue] raise {
  guard value.kind() is List(values) else { raise Refused("invalid_profile") }
  values
}

///|
// Only the semantic IR uses its JSON-shaped wire schema. Rich enrichments and
// provenance never pass through this conversion. Reject unrepresentable facts.
fn semantic_json(value : @ion.IonValue) -> Json raise {
  let annotations = value.annotations()
  if !annotations.is_empty() {
    guard annotations.length() == 1 &&
      annotations[0].text() == Some("morphir_json_number") &&
      value.kind() is String(text) else {
      raise Refused("unsupported_semantic_value")
    }
    return @wire.number(text)
  }
  match value.kind() {
    Null(@ion.Null) => Json::null()
    Bool(value) => Json(value)
    Int(value) => @wire.number(value.to_string())
    Decimal(value) => {
      let coefficient = if value.is_negative_zero() {
        "-0"
      } else {
        value.coefficient().to_string()
      }
      @wire.number(coefficient + "e" + value.exponent().to_string())
    }
    Float(value) => {
      let json = Json(value)
      ignore(@wire.float(json))
      json
    }
    String(text) => Json::string(text)
    List(values) => Json::array(values.map(semantic_json))
    Struct(fields) => {
      let result : Map[String, Json] = Map([])
      for field in fields {
        guard field.name().text() is Some(name) && !result.contains(name) else {
          raise Refused("invalid_profile")
        }
        result[name] = semantic_json(field.value())
      }
      Json::object(result)
    }
    _ => raise Refused("unsupported_semantic_value")
  }
}

///|
fn model_ir(value : Json) -> @generator.Input raise {
  let declared = @wire.field(value, "formatVersion")
  guard declared == Json::string("4.0.0") || @wire.integer_text(declared) == "4" else {
    raise Refused("unsupported_ir_version")
  }
  @generator.Input::new("mep", @ir_json.from_json(value))
}

///|
fn rich_input(root : @ion.IonValue) -> @generator.Input raise {
  guard root.annotations().any(a => a.text() == Some("morphir_model")) else {
    raise Refused("invalid_profile")
  }
  let base = model_ir(semantic_json(ion_member(root, "ir")))
  let provenance = ion_list(ion_member(root, "provenance"))
  let enrichments = ion_list(ion_member(root, "enrichments"))
  let metadata : Array[@generator.NodeMetadata] = []
  let mut unit_id = "mep"
  let mut annotations = root.annotations()
  let mut found = false
  for enrichment in enrichments {
    let owner = ion_string(ion_member(enrichment, "owner"))
    let data = ion_member(enrichment, "data")
    if owner == NODE_METADATA_OWNER {
      guard !found else { raise Refused("duplicate_node_carrier") }
      found = true
      unit_id = ion_string(ion_member(data, "sourceUnitId"))
      annotations = ion_list(ion_member(data, "sourceAnnotations")).map(value => {
        guard value.kind() is Symbol(token) else {
          raise Refused("invalid_node_carrier")
        }
        token
      })
      let seen : Map[String, Bool] = Map([])
      for entry in ion_list(ion_member(data, "nodes")) {
        let node_id = ion_string(ion_member(entry, "nodeId"))
        guard !seen.contains(node_id) else {
          raise Refused("duplicate_node_identity")
        }
        seen[node_id] = true
        metadata.push({ node_id, data: ion_member(entry, "data"), })
      }
    }
  }
  { ..base, unit_id, metadata, annotations, provenance, }
}

///|
fn model_evidence(model : Json) -> Array[Json] raise {
  @wire.optional(model, "evidence").map(@wire.array).unwrap_or([])
}

///|
fn retain_input(
  params : Json,
  transport : ModelTransport,
) -> RetainedInput raise {
  @wire.fields(params, [
    "model", "input", "target", "contextDigest", "requiredGuarantees", "options",
  ])
  guard @wire.field(params, "target") == Json::string("moonbit") else {
    raise Refused("capability_unavailable")
  }
  let options = @wire.optional(params, "options").unwrap_or(Json::object({}))
  guard @wire.object(options).is_empty() else {
    raise Refused("unsupported_options")
  }
  ignore(model_digest(@wire.field(params, "contextDigest")))
  let tuple = @wire.field(params, "input")
  guard transport.tuples.contains(tuple) &&
    field(tuple, "operation") == Json::string(GENERATE_MODEL) else {
    raise Refused("unsupported_tuple")
  }
  let model = @wire.field(params, "model")
  for name in ["envelopeVersion", "profile", "irVersion"] {
    guard @wire.field(model, name) == @wire.field(tuple, name) else {
      raise Refused("unsupported_tuple")
    }
  }
  ignore(model_text(@wire.field(model, "modelId")))
  ignore(model_text(@wire.field(model, "revision")))
  for path in @wire.optional(model, "critical").map(@wire.array).unwrap_or([]) {
    let path = @wire.string(path)
    guard [
      "envelopeVersion", "modelId", "revision", "irVersion", "profile", "payload",
      "payload.codec", "payload.layout", "payload.decodedByteLength", "payload.sha256",
      "payload.content", "evidence", "critical",
    ].contains(path) else {
      raise Refused("unknown_critical_path")
    }
  }
  let payload = @wire.field(model, "payload")
  guard @wire.field(payload, "codec") == @wire.field(tuple, "codec") else {
    raise Refused("unsupported_tuple")
  }
  let evidence = model_evidence(model)
  let budget = ModelBudget::new(transport.limits)
  budget.reserve(payload)
  for claim in evidence {
    budget.reserve(@wire.field(claim, "evidence"))
  }
  let bytes = budget.decode(payload)
  let input = if @wire.field(payload, "codec") == Json::string("ion-binary") {
    budget.inspect_binary(bytes)
    rich_input(read_model_binary(bytes, transport.limits))
  } else {
    model_ir(budget.read_json(bytes))
  }
  for claim in evidence {
    for name in ["guarantee", "modelId", "modelRevision", "scope", "producer"] {
      ignore(model_text(@wire.field(claim, name)))
    }
    ignore(model_digest(@wire.field(claim, "contextDigest")))
    let evidence_payload = @wire.field(claim, "evidence")
    let evidence_bytes = budget.decode(evidence_payload)
    match @wire.string(@wire.field(evidence_payload, "codec")) {
      "ion-binary" => {
        budget.inspect_binary(evidence_bytes)
        ignore(read_model_binary(evidence_bytes, transport.limits))
      }
      "morphir-json" => ignore(budget.read_json(evidence_bytes))
      _ => raise Refused("unsupported_codec")
    }
  }
  let required = @wire.optional(params, "requiredGuarantees")
    .map(@wire.array)
    .unwrap_or([])
  for requirement in required {
    ignore(model_text(@wire.field(requirement, "guarantee")))
    ignore(model_text(@wire.field(requirement, "scope")))
  }
  // No remote guarantee vocabulary/checker is available. Attribution, hashes,
  // matching evidence bindings and enrichment owners never grant authority.
  guard required.is_empty() else { raise Refused("unknown_required_guarantee") }
  { input, bytes, model, }
}

///|
/// Decode the existing MEP MorphirModel value through its maintained semantic
/// boundary. Transport envelopes, payload hashes and guarantees remain separate.
/// The caller must retain the source envelope when preserving unknown enrichments.
pub fn decode_morphir_model(root : @ion.IonValue) -> @generator.Input raise {
  rich_input(root)
}
