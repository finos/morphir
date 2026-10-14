///|
/// Frozen project identity and selections. Paths remain selections with their
/// configuration origins; the host must resolve them against its own grants.
pub(all) struct ProjectMetadataScope {
  workspace_root : String
  project_root : String
  project_name : String
  request : @configuration.MetadataProviderRequest
} derive(Eq, Debug)

///|
pub extend ProjectMetadataScope with Eq::{equal, not_equal}

///|
pub extend ProjectMetadataScope with @debug.Debug::{to_repr}

///|
/// Bind a distinct capability closure to each planned MoonBit project. This
/// callback must be effect-free: restoration belongs in restore_library at
/// execution time. It must not allocate resources requiring plan disposal.
/// Static constructor capabilities and a project binder are separate authorities.
pub fn Engine::register_project_metadata_provider(
  self : Engine,
  bind : (ProjectMetadataScope) -> @linked_metadata.Capabilities raise,
) -> Unit raise {
  if self.static_metadata_authority || self.project_metadata_provider is Some(_) {
    raise @configuration.Invalid(
      "metadata.ambiguous_authority: Use either static metadata capabilities or one project metadata provider",
    )
  }
  self.project_metadata_provider = Some(bind)
}

///|
fn Engine::bind_project_metadata(
  self : Engine,
  name : String,
  backend : GenerationBackend?,
  scope : ProjectMetadataScope,
) -> GenerationBackend? raise {
  guard name == "moonbit" &&
    backend is Some(generator) &&
    self.project_metadata_provider is Some(bind) else {
    return backend
  }
  let capabilities = bind(scope)
  Some({
    ..generator,
    generate: fn(unit, options, cancelled) raise {
      moonbit_generation(unit, options, cancelled, capabilities)
    },
  })
}
