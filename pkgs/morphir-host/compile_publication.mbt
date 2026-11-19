///|
/// Schema-1 compile results describe the product published by this transaction.
pub(all) struct CompileRecordOptions {
  explicit_selection : Bool
  tree_product : String?
}

///|
priv struct CompilePublication {
  record_options : (String) -> CompileRecordOptions?
  before : (String, Array[(String, String?)]) -> Unit raise
  complete : (String) -> Unit raise
  close : () -> Unit
}

///|
fn CompilePublication::inactive() -> CompilePublication {
  {
    record_options: _ => None,
    before: (_, _) => (),
    complete: _ => (),
    close: () => (),
  }
}

///|
#cfg(not(target="native"))
fn begin_compile_publication(
  root : String,
  output_root : String,
  destinations : Array[String],
  options : CompileRecordOptions?,
  cancelled : () -> Bool,
) -> CompilePublication {
  ignore((root, output_root, destinations, options, cancelled))
  CompilePublication::inactive()
}

///|
fn compile_artifact_version(artifact : @engine.ContentArtifact) -> String? {
  guard (artifact.format == "morphir-json" || artifact.format == "ir-json") &&
    artifact.ir_json_version is Some(version) else {
    return None
  }
  version.check_supported() catch {
    _ => return None
  }
  let name = if version.minor == 0U && version.patch == 0U {
    version.major.to_string()
  } else {
    version.to_release_string()
  }
  Some("v" + name)
}
