///|
/// Deliberate model-envelope selection. A MorphirModel is not an engine
/// checkpoint; its existing decoder is reused, with its source context retained.
pub fn inspect_model_source(
  format : ModelFormat,
  bytes : Bytes,
  unit_id~ : String = "workbench",
  limits~ : Limits = Limits::default(),
) -> CheckpointInspection raise BoundaryError {
  let registry = Registry::new(limits~)
  guard bytes.length() <= limits.max_bytes else {
    raise Invalid("data.byte_limit", "Model source exceeds the byte budget")
  }
  if format is (JSON | YAML) {
    let content = Text(
      @utf8.decode(bytes[:], ignore_bom=true) catch {
        _ =>
          raise Invalid("data.invalid_utf8", "Model text must be valid UTF-8")
      },
    )
    let result = registry.inspect_checkpoint(format.codec_id(), content)
    let unit = { ..result.unit, id: unit_id, }
    unit.validate(limits~) catch {
      Invalid(_, _) as error => raise error
      error => raise Invalid("data.decode_failed", error.to_string())
    }
    return { ..result, unit, }
  }
  try {
    let content = if format is IonBinary {
      Binary(bytes)
    } else {
      Text(@utf8.decode(bytes[:], ignore_bom=true))
    }
    check_content(content, limits)
    let root = match content {
      Binary(bytes) => @ion_binary.read_binary_value(bytes[:])
      Text(text) => @ion_text.read_ion(text[:])
    }
    check_tree(root, limits)
    let pipeline = root
      .annotations()
      .any(a => a.text() == Some("morphir_pipeline"))
    let model = root.annotations().any(a => a.text() == Some("morphir_model"))
    if pipeline && model {
      raise Invalid(
        "data.ambiguous_envelope", "A source cannot be both model and checkpoint",
      )
    }
    if !model {
      return registry.inspect_checkpoint(format.codec_id(), content)
    }
    let decoded = @mep_model.decode_morphir_model(root) catch {
      error => raise Invalid("data.invalid_mep_model", error.to_string())
    }
    // This is an import-capture event containing the opaque original model,
    // not an interpretation or endorsement of its enrichment owners.
    let capture = @ion.IonValue::from_fields([
      @ion.Field::new("source_envelope", root),
    ]).with_annotation(@ion.SymbolToken::new("morphir_model_import"))
    let unit : IRUnit = {
      id: decoded.unit_id,
      distribution: decoded.ir,
      metadata: decoded.metadata.map(m => { node_id: m.node_id, data: m.data, }),
      annotations: [@ion.SymbolToken::new("morphir_pipeline")],
      provenance: decoded.provenance + [capture],
    }
    unit.validate(limits~)
    { unit, original_format_version: decoded.ir.format_version, }
  } catch {
    Invalid(_, _) as error => raise error
    @ion.LimitExceeded(detail) => raise Invalid("data.tree_limit", detail)
    @ion.Syntax(detail) | @ion.DataModel(detail) | @ion.Unsupported(detail) =>
      raise Invalid("invalid_ion", detail)
    error => raise Invalid("data.decode_failed", error.to_string())
  }
}
