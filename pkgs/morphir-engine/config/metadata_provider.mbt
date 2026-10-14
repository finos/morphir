///|
/// A path selection, not a filesystem grant. The host resolves it from its
/// configuration origin and enforces its own accepted roots.
pub(all) struct MetadataPath {
  path : String
  origin : String
} derive(Eq, Debug)

///|
pub extend MetadataPath with Eq::{equal, not_equal}

///|
pub extend MetadataPath with @debug.Debug::{to_repr}

///|
pub(all) struct MetadataRestoreConfig {
  service : MetadataPath
  policy : MetadataPath
  lock : MetadataPath
  registry : MetadataPath
  state : MetadataPath
  release : String
  assurance : String
} derive(Eq, Debug)

///|
pub extend MetadataRestoreConfig with Eq::{equal, not_equal}

///|
pub extend MetadataRestoreConfig with @debug.Debug::{to_repr}

///|
/// Immutable service selections for a host binder. Disabled requests no CLI
/// service; it does not revoke capabilities explicitly granted by an embedding.
/// Parsing performs no restoration,
/// trust initialization or capability acquisition.
pub(all) enum MetadataProviderRequest {
  Disabled
  SharedLocalRestore(MetadataRestoreConfig)
} derive(Eq, Debug)

///|
pub extend MetadataProviderRequest with Eq::{equal, not_equal}

///|
pub extend MetadataProviderRequest with @debug.Debug::{to_repr}

///|
fn metadata_origin(document : Document, key : String) -> String {
  document.provenance
  .get(key)
  .unwrap_or(
    document.provenance.get("metadata.provider").unwrap_or("<unknown>"),
  )
}

///|
fn[T] metadata_invalid(
  document : Document,
  key : String,
  detail : String,
) -> T raise {
  raise Invalid(
    "metadata.invalid_configuration: " +
    key +
    " " +
    detail +
    " (set in " +
    metadata_origin(document, key) +
    ")",
  )
}

///|
fn metadata_text(document : Document, key : String) -> String raise {
  match document.get(key) {
    Some(TomlString(text)) if text.trim() != "" && !text.contains("\u0000") =>
      text
    None => metadata_invalid(document, key, "is required")
    _ => metadata_invalid(document, key, "must be a nonempty string")
  }
}

///|
fn metadata_path(document : Document, key : String) -> MetadataPath raise {
  {
    path: metadata_text(document, key),
    origin: metadata_origin(document, key),
  }
}

///|
fn metadata_release_segment(text : StringView) -> Bool {
  text != "" &&
  text
  .split("-")
  .collect()
  .all(part => {
    part != "" &&
    part
    .to_owned()
    .to_array()
    .all(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
  })
}

///|
fn exact_provider_release(text : String) -> Bool {
  let selection = text.split("@").collect()
  if selection.length() != 2 {
    return false
  }
  let package_parts = selection[0].split("/").collect()
  if package_parts.length() < 2 || !package_parts[0].contains(".") {
    return false
  }
  if !package_parts[0].split(".").collect().all(metadata_release_segment) ||
    !package_parts[1:].all(metadata_release_segment) {
    return false
  }
  let parts = selection[1].split(".").collect()
  parts.length() == 3 &&
  parts.all(p => {
    p != "" &&
    (p == "0" || !p.has_prefix("0")) &&
    p.to_owned().to_array().all(c => c >= '0' && c <= '9')
  })
}

///|
/// Read only the owned provider selections. Other metadata configuration stays
/// available to its own consumers. Release semantics are finally checked by the
/// shared restore service; this parser admits canonical stable release syntax.
pub fn Document::metadata_provider_request(
  self : Document,
) -> MetadataProviderRequest raise {
  match self.get("metadata") {
    None | Some(TomlTable(_)) => ()
    _ => metadata_invalid(self, "metadata", "must be a table")
  }
  match self.get("metadata.naming") {
    None | Some(TomlTable(_)) => ()
    _ => metadata_invalid(self, "metadata.naming", "must be a table")
  }
  let provider = match self.get("metadata.provider") {
    None => "none"
    Some(TomlString(text)) => text
    _ => metadata_invalid(self, "metadata.provider", "must be a string")
  }
  if provider == "none" {
    for
      key in [
        "metadata.service", "metadata.policy", "metadata.lock", "metadata.registry",
        "metadata.state", "metadata.assurance", "metadata.naming.release",
      ] {
      if self.get(key) is Some(_) {
        metadata_invalid(
          self, key, "requires metadata.provider = 'shared-local-restore'",
        )
      }
    }
    return Disabled
  }
  if provider != "shared-local-restore" {
    metadata_invalid(
      self, "metadata.provider", "must be 'none' or 'shared-local-restore'",
    )
  }
  let service = metadata_path(self, "metadata.service")
  let policy = metadata_path(self, "metadata.policy")
  let lock = metadata_path(self, "metadata.lock")
  let registry = metadata_path(self, "metadata.registry")
  let state = metadata_path(self, "metadata.state")
  let assurance = metadata_text(self, "metadata.assurance")
  if assurance != "portable" {
    metadata_invalid(
      self, "metadata.assurance", "must be 'portable'; hardened is unavailable",
    )
  }
  let release = metadata_text(self, "metadata.naming.release")
  if !exact_provider_release(release) {
    metadata_invalid(
      self, "metadata.naming.release", "must be an authority-qualified PACKAGE@MAJOR.MINOR.PATCH release; the IR name morphir/naming is checked separately",
    )
  }
  SharedLocalRestore({
    service,
    policy,
    lock,
    registry,
    state,
    release,
    assurance,
  })
}
