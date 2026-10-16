///|
pub fn Registry::new(limits~ : Limits = Limits::default()) -> Registry raise {
  if limits.max_bytes <= 0 || limits.max_depth < 0 || limits.max_values <= 0 {
    raise Invalid("data.invalid_limits", "Limits must be positive")
  }
  let registry = Registry::{ codecs: Map([]), limits, }
  registry.register("morphir-json", {
    decode: fn(source, _) raise {
      let text = require_text(source.content)
      let file = @migration.to_current(@versioned_json.read(text))
      IRUnit::new(source.unit_id, file)
    },
    encode: fn(unit, _) raise {
      if !unit.metadata.is_empty() ||
        !unit.provenance.is_empty() ||
        !profile_annotations_only(unit.annotations) {
        raise Invalid(
          "data.lossy_conversion", "Morphir JSON cannot carry engine metadata",
        )
      }
      Text(@ir_json.write(unit.distribution))
    },
  })
  registry.register("ion-text", {
    decode: fn(source, limits) raise {
      let value = @ion_text.read_ion(require_text(source.content)[:])
      read_envelope(value, source.unit_id, limits)
    },
    encode: fn(unit, limits) raise {
      Text(@ion_text.write_ion(write_envelope(unit, limits)))
    },
  })
  registry.register("ion-binary", {
    decode: fn(source, limits) raise {
      let bytes = match source.content {
        Binary(bytes) => bytes
        Text(_) => raise Invalid("data.encoding_mismatch", "Expected bytes")
      }
      read_envelope(
        @ion_binary.read_binary_value(bytes[:]),
        source.unit_id,
        limits,
      )
    },
    encode: fn(unit, limits) raise {
      Binary(@ion_binary.write_binary_value(write_envelope(unit, limits)))
    },
  })
  registry
}

///|
/// Registration conflicts fail instead of changing an existing plan's codec.
pub fn Registry::register(
  self : Registry,
  id : String,
  codec : Codec,
) -> Unit raise BoundaryError {
  if id == "" || self.codecs.contains(id) {
    raise Invalid("data.codec_conflict", id)
  }
  self.codecs[id] = codec
}

///|
pub fn Registry::decode(
  self : Registry,
  id : String,
  source : SourceSnapshot,
) -> IRUnit raise BoundaryError {
  check_content(source.content, self.limits)
  let codec = self.lookup(id)
  try {
    let unit = (codec.decode)(source, self.limits)
    if unit.id != source.unit_id {
      raise Invalid("data.unit_mismatch", source.unit_id)
    }
    ignore(write_envelope(unit, self.limits))
    unit
  } catch {
    Invalid(_, _) as error => raise error
    @wire.Invalid(code, detail) => raise Invalid(code, detail)
    @ion.Syntax(detail) | @ion.DataModel(detail) | @ion.Unsupported(detail) =>
      raise Invalid("data.decode_failed", detail)
    error =>
      raise Invalid(
        boundary_code(error, "data.decode_failed"),
        error.to_string(),
      )
  }
}

///|
/// Open a self-contained checkpoint without replacing its logical unit identity.
/// This does not grant filesystem or provider authority. Raw Morphir JSON has no
/// unit identity; the local checkpoint reader supplies a stable logical default.
pub fn Registry::open_checkpoint(
  self : Registry,
  codec : String,
  content : Content,
) -> IRUnit raise BoundaryError {
  check_content(content, self.limits)
  try {
    let unit_id = if codec == "morphir-json" {
      "workbench"
    } else {
      let value = match (codec, content) {
        ("ion-text", Text(text)) => @ion_text.read_ion(text[:])
        ("ion-binary", Binary(bytes)) => @ion_binary.read_binary_value(bytes[:])
        _ =>
          raise Invalid(
            "data.encoding_mismatch", "Expected a supported checkpoint codec and matching content",
          )
      }
      string_field(schema_fields(value), "unit_id")
    }
    self.decode(codec, { unit_id, content, })
  } catch {
    Invalid(_, _) as error => raise error
    @ion.Syntax(message)
    | @ion.DataModel(message)
    | @ion.Unsupported(message) => raise Invalid("data.decode_failed", message)
    error => raise Invalid("data.decode_failed", error.to_string())
  }
}

///|
pub fn Registry::encode(
  self : Registry,
  id : String,
  unit : IRUnit,
) -> Content raise BoundaryError {
  let codec = self.lookup(id)
  try {
    ignore(write_envelope(unit, self.limits))
    let content = (codec.encode)(unit, self.limits)
    check_content(content, self.limits)
    content
  } catch {
    Invalid(_, _) as error => raise error
    @wire.Invalid(code, detail) => raise Invalid(code, detail)
    @ion.Syntax(detail) | @ion.DataModel(detail) | @ion.Unsupported(detail) =>
      raise Invalid("data.encode_failed", detail)
    error =>
      raise Invalid(
        boundary_code(error, "data.encode_failed"),
        error.to_string(),
      )
  }
}

///|
pub fn Registry::checkpoint(
  self : Registry,
  unit : IRUnit,
  codec~ : String = "ion-binary",
) -> Content raise BoundaryError {
  self.encode(codec, unit)
}

///|
fn Registry::lookup(self : Registry, id : String) -> Codec raise BoundaryError {
  match self.codecs.get(id) {
    Some(codec) => codec
    None => raise Invalid("data.unknown_codec", id)
  }
}

///|
fn require_text(content : Content) -> String raise BoundaryError {
  match content {
    Text(text) => text
    Binary(_) => raise Invalid("data.encoding_mismatch", "Expected text")
  }
}

///|
fn check_content(
  content : Content,
  limits : Limits,
) -> Unit raise BoundaryError {
  let length = match content {
    Text(text) => @utf8.encode(text).length()
    Binary(bytes) => bytes.length()
  }
  if length > limits.max_bytes {
    raise Invalid("data.byte_limit", "Content exceeds the byte budget")
  }
}

///|
fn profile_annotations_only(annotations : Array[@ion.SymbolToken]) -> Bool {
  annotations.length() == 1 && annotations[0].text() == Some("morphir_pipeline")
}

///|
fn boundary_code(error : Error, fallback : String) -> String {
  let code = @wire.diagnostic(error)
  if code == "unknown_error" {
    fallback
  } else {
    code
  }
}

///|
pub fn Registry::has_codec(self : Registry, id : String) -> Bool {
  self.codecs.contains(id)
}
