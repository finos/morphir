///|
/// Paths are relative to a host-owned root. list recursively returns file paths.
pub(all) struct Host {
  read : (String) -> String raise
  exists : (String) -> Bool raise
  list : (String) -> Array[String] raise
}

///|
/// An immutable snapshot is useful for editors, tests, WASM and remote hosts.
pub fn Host::memory(files : Map[String, String]) -> Host raise {
  let snapshot : Map[String, String] = Map([])
  for path, content in files {
    let normalized = normalize(path)
    if snapshot.contains(normalized) {
      raise @scheme.Invalid("Duplicate host path: " + normalized)
    }
    snapshot[normalized] = content
  }
  {
    read: fn(path) raise {
      match snapshot.get(path) {
        Some(content) => content
        None => raise @scheme.Invalid("File not found: " + path)
      }
    },
    exists: fn(path) { snapshot.contains(path) },
    list: fn(root) {
      snapshot.keys().filter(path => within(root, path)).collect()
    },
  }
}

///|
pub(all) enum Input {
  File(String)
  Directory(String)
  Project(String)
  Workspace(String)
}

///|
pub(all) struct Source {
  path : String
  relative_path : String
  content : String
  package_name : String
  module_name : String
}

///|
/// One backend output per input. Hosts decide when and where to persist artifacts.
pub(all) struct Artifact {
  path : String
  source : String
  content : String
}

///|
pub(all) struct Diagnostic {
  path : String
  stage : String
  message : String
  details : @diagnostics.Warning?
}

///|
pub(all) struct Report {
  artifacts : Array[Artifact]
  diagnostics : Array[Diagnostic]
  processed : Int
}

///|
pub fn Report::successful(self : Report) -> Bool {
  self.diagnostics.is_empty()
}

///|
struct Frontend {
  extensions : Array[String]
  compiler : SourceCompiler
  profile : String?
  dependencies : Map[String, String]
  provider : String
  default_profile : Bool
  available_profiles : Array[String]
  capabilities : SourceCapabilities?
  evidence : SourceEvidence
}

///|
struct Backend {
  extension : String
  emit : (@ir.IRFile) -> String raise
}

///|
/// Registries are explicit; every run creates isolated script sessions.
pub struct Engine {
  priv frontends : Map[String, Frontend]
  priv source_providers : Map[String, SourceProvider]
  priv backends : Map[String, Backend]
  priv generators : Map[String, GenerationBackend]
  priv components : Map[String, Component]
  priv metadata_policies : Map[String, @data.MetadataPolicy]
  priv data_formats : Map[String, DataFormat]
  priv limits : @scheme.Limits
  priv static_metadata_authority : Bool
  priv mut project_metadata_provider : ((ProjectMetadataScope) -> @linked_metadata.Capabilities raise)?
}

///|
pub fn Engine::new(
  limits? : @scheme.Limits = @scheme.Limits::default(),
  metadata_capabilities? : @linked_metadata.Capabilities = @linked_metadata.Capabilities::unavailable(),
) -> Engine {
  let engine = {
    static_metadata_authority: metadata_capabilities.restore_library is Some(_) ||
    metadata_capabilities.load_context is Some(_) ||
    metadata_capabilities.target_names_interpreter,
    project_metadata_provider: None,
    frontends: Map([]),
    source_providers: Map([]),
    components: Map::from_array([
      (
        "json-identity",
        Component::JSON(fn(text) { { content: text, lineage: None, } }),
      ),
    ]),
    metadata_policies: Map::from_array([
      ("retain", @data.MetadataPolicy::retain()),
      ("copy-single-origin", @data.MetadataPolicy::copy_single_origin()),
    ]),
    backends: Map([]),
    generators: Map::from_array([
      (
        "moonbit",
        GenerationBackend::{
          generate: fn(unit, options, cancelled) raise {
            moonbit_generation(unit, options, cancelled, metadata_capabilities)
          },
          write_bytes: true,
          validate_options: moonbit_validate_options,
          targets: ["wasm", "wasm-gc", "js", "native"],
        },
      ),
      (
        "elm",
        GenerationBackend::{
          generate: elm_generation,
          write_bytes: false,
          validate_options: elm_validate_options,
          targets: [],
        },
      ),
    ]),
    limits,
    data_formats: Map::from_array([
      (
        "morphir-json",
        DataFormat::{
          codec: "morphir-json",
          extensions: [".json"],
          suffix: ".json",
          binary: false,
        },
      ),
      (
        "ion-text",
        DataFormat::{
          codec: "ion-text",
          extensions: [".ion"],
          suffix: ".ion",
          binary: false,
        },
      ),
      (
        "ion-binary",
        DataFormat::{
          codec: "ion-binary",
          extensions: [".ionb", ".10n"],
          suffix: ".ionb",
          binary: true,
        },
      ),
    ]),
  }
  engine.register_frontend("scheme", [".scm", ".ss"], fn(source) raise {
    @frontend.compile_file(
      source.content,
      package_name=canonical_path(source.package_name),
      module_name=canonical_path(source.module_name),
    )
  })
  engine.register_frontend("ir-json", [".json"], fn(source) raise {
    @migration.to_current(@versioned_json.read(source.content))
  })
  engine.register_backend("scheme", ".scm", @backend.emit_file)
  engine.register_backend("ir-json", ".ir.json", @ir_json.write)
  engine
}

///|
pub fn Engine::register_frontend(
  self : Engine,
  name : String,
  extensions : Array[String],
  compile : (Source) -> @ir.IRFile raise,
) -> Unit {
  self.frontends[name] = {
    extensions: extensions.copy(),
    compiler: FileCompiler(compile),
    profile: None,
    dependencies: Map([]),
    provider: name,
    default_profile: true,
    available_profiles: [],
    capabilities: None,
    evidence: Declared,
  }
}

///|
pub fn Engine::register_backend(
  self : Engine,
  name : String,
  extension : String,
  emit : (@ir.IRFile) -> String raise,
) -> Unit {
  self.backends[name] = { extension, emit, }
}
