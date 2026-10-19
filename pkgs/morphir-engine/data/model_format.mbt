///|
/// Physical model representation, independent of source language and backend.
pub(all) enum ModelFormat {
  JSON
  YAML
  IonText
  IonBinary
} derive(Eq, Debug)

///|
pub extend ModelFormat with Eq::{equal, not_equal}

///|
pub extend ModelFormat with @debug.Debug::{to_repr}

///|
pub fn ModelFormat::from_control(
  value : String,
) -> ModelFormat raise BoundaryError {
  match value {
    "json" | "morphir-json" => JSON
    "yaml" | "yml" | "morphir-yaml" => YAML
    "ion" | "ion-text" => IonText
    "ionb" | "ion-binary" => IonBinary
    _ => raise Invalid("data.unknown_codec", value)
  }
}

///|
pub fn ModelFormat::infer_path(path : String) -> ModelFormat? {
  let path = path.to_lower()
  if path.has_suffix(".yaml") || path.has_suffix(".yml") {
    Some(YAML)
  } else if path.has_suffix(".json") {
    Some(JSON)
  } else if path.has_suffix(".ionb") {
    Some(IonBinary)
  } else if path.has_suffix(".ion") {
    Some(IonText)
  } else {
    None
  }
}

///|
pub fn ModelFormat::codec_id(self : ModelFormat) -> String {
  match self {
    JSON => "morphir-json"
    YAML => "morphir-yaml"
    IonText => "ion-text"
    IonBinary => "ion-binary"
  }
}

///|
pub fn ModelFormat::is_binary(self : ModelFormat) -> Bool {
  self is IonBinary
}

///|
/// Decode strict UTF-8 or binary at the shared boundary. The caller retains the
/// original bytes for exact export; normalization never replaces those bytes.
pub fn decode_model(
  format : ModelFormat,
  bytes : Bytes,
  unit_id~ : String = "workbench",
  limits~ : Limits = Limits::default(),
) -> IRUnit raise BoundaryError {
  inspect_model_source(format, bytes, unit_id~, limits~).unit
}

///|
/// Filesystem and picker adapters supply only relative paths and captured bytes.
/// All format, version, tree ownership and assembly decisions stay shared.
pub fn inspect_model_tree(
  files : Map[String, Bytes],
  unit_id~ : String = "workbench",
  limits~ : Limits = Limits::default(),
) -> CheckpointInspection raise BoundaryError {
  guard files.length() <= model_tree_file_limit else {
    raise Invalid("data.byte_limit", "Tree exceeds the 4096-file budget")
  }
  let mut total = 0
  for _, bytes in files {
    guard bytes.length() <= limits.max_bytes - total else {
      raise Invalid("data.byte_limit", "Tree exceeds the source byte budget")
    }
    total += bytes.length()
  }
  let text : Map[String, String] = Map([])
  for path, bytes in files {
    let relevant = (
        path == "manifest.yaml" ||
        path == "manifest.yml" ||
        path == "manifest.json" ||
        path.has_prefix("pkg/") ||
        path.has_prefix("deps/")
      ) &&
      (
        path.has_suffix(".yaml") ||
        path.has_suffix(".yml") ||
        path.has_suffix(".json")
      )
    text[path] = if relevant {
      @utf8.decode(bytes[:], ignore_bom=true) catch {
        _ => raise Invalid("data.invalid_utf8", "Tree text must be valid UTF-8")
      }
    } else {
      ""
    }
  }
  try {
    let source = @yaml.read_tree_versioned(text, limits={
      ..@yaml.Limits::default(),
      max_bytes: limits.max_bytes,
      max_depth: limits.max_depth,
      max_nodes: limits.max_values,
      max_assembly_nodes: limits.max_values,
    })
    let unit = IRUnit::new(unit_id, @migration.to_current(source))
    unit.validate(limits~)
    { unit, original_format_version: source.format_version(), }
  } catch {
    @wire.Invalid(code, detail) => raise Invalid(code, detail)
    Invalid(code, detail) => raise Invalid(code, detail)
    error => raise Invalid("data.decode_failed", error.to_string())
  }
}

///|
/// Maximum captured files, including ignored sidecars. Adapters check before insert.
pub let model_tree_file_limit : Int32 = 4096

///|
pub fn decode_model_tree(
  files : Map[String, Bytes],
  unit_id~ : String = "workbench",
  limits~ : Limits = Limits::default(),
) -> IRUnit raise BoundaryError {
  inspect_model_tree(files, unit_id~, limits~).unit
}
