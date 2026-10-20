//! Internal original-source authority from real workspace providers.
//! No connected method or capability is advertised by this module.
use std::{
    path::{Path, PathBuf},
    sync::Arc,
};

pub use super::current::SelectedOriginalsOffer;
use cap_fs_ext::DirExt;
use cap_std::fs::Dir;
use morphir_devkit::config::ProjectSelection;
use morphir_devkit::{ConfigLoadOptions, discover_config_at, load_config_context_with};
use morphir_workspace as portable;
use same_file::Handle;

use super::{extension::ExtensionWorkspaceProvider, native::NativeWorkspaceProvider};
use crate::{
    commands::{
        out_context::OutOverrides,
        ui::{
            model_originals::{
                CaptureError, HostModelCaptureCapacity, ProviderCaptureError,
                RetainedEvidenceCredit, SelectedModule,
            },
            protocol::{WorkbenchSourceRef, project_key, protocol_error},
        },
    },
    error::CliError,
};

/// Host startup issues this grant explicitly. Request labels and ordinary v1
/// provider construction cannot authorize ambient compiler configuration lookup.
#[derive(Default)]
pub(super) enum HostOutputLookup {
    #[default]
    Unissued,
    Issued(Box<TrustedHostOutputLookup>),
}

pub(super) struct TrustedHostOutputLookup {
    directory: Dir,
    label: PathBuf,
    identity: Handle,
    options: ConfigLoadOptions,
    overrides: OutOverrides,
    offer: StartupOffer,
    ambient: cap_std::AmbientAuthority,
    #[cfg(test)]
    hooks: Option<Arc<dyn LookupHooks>>,
}
#[derive(Clone, Copy, Eq, PartialEq)]
struct StartupOffer(uuid::Uuid);
#[cfg(test)]
pub(in crate::commands::ui) trait LookupHooks: Send + Sync {
    fn before_current(&self) {}
    fn after_current(&self) {}
    fn before_module_copy(&self) {}
}
impl HostOutputLookup {
    pub(super) fn issue(
        directory: &Dir,
        label: &Path,
        options: &ConfigLoadOptions,
        overrides: &OutOverrides,
        ambient: cap_std::AmbientAuthority,
    ) -> Result<Self, CliError> {
        if !label.is_absolute() {
            return Err(protocol_error(
                "Original-source startup root must be absolute",
            ));
        }
        let identity = Handle::from_file(directory.try_clone()?.into_std_file())?;
        let current = Dir::open_ambient_dir(label, ambient)?;
        if Handle::from_file(current.into_std_file())? != identity {
            return Err(protocol_error(
                "Original-source startup root identity does not match its held directory",
            ));
        }
        Ok(Self::Issued(Box::new(TrustedHostOutputLookup {
            directory: directory.try_clone()?,
            label: label.to_owned(),
            identity,
            options: options.clone(),
            overrides: overrides.clone(),
            offer: StartupOffer(uuid::Uuid::new_v4()),
            ambient,
            #[cfg(test)]
            hooks: None,
        })))
    }
    #[cfg(test)]
    pub(super) fn set_hooks(&mut self, hooks: Arc<dyn LookupHooks>) {
        let Self::Issued(grant) = self else {
            panic!("lookup hooks require a genuine startup grant")
        };
        grant.hooks = Some(hooks);
    }
    pub(super) fn granted(&self) -> Result<&TrustedHostOutputLookup, CliError> {
        match self {
            Self::Issued(grant) => {
                grant.verify_root()?;
                Ok(grant)
            }
            Self::Unissued => Err(protocol_error(
                "Original-source host lookup was not authorized at startup",
            )),
        }
    }
}
impl TrustedHostOutputLookup {
    pub(super) fn verify_root(&self) -> Result<(), CliError> {
        let actual = Dir::open_ambient_dir(&self.label, self.ambient)?;
        if Handle::from_file(actual.into_std_file())? != self.identity {
            return Err(protocol_error("Original-source workspace root changed"));
        }
        Ok(())
    }
    pub(super) fn capture_discovery(
        &self,
    ) -> Result<morphir_devkit::CapturedWorkspaceDiscovery, CliError> {
        self.verify_root()?;
        morphir_devkit::WorkspaceDiscoveryRoot::from_directory(
            self.directory.try_clone()?,
            &self.label,
        )
        .map_err(CliError::from)?
        .capture(&self.options)
        .map_err(CliError::from)
    }
}

/// Captured request identities are labels, never directory authority.
#[derive(Clone, Debug)]
pub struct OriginalsSelection {
    source: RequestedSource,
    project: ProjectId,
}
#[derive(Clone, Debug)]
struct ProjectId(String);
#[derive(Clone, Debug)]
struct RequestedSource {
    provider_id: String,
    locator: String,
}
impl OriginalsSelection {
    pub fn parse(source: &WorkbenchSourceRef, project: &str) -> Result<Self, CaptureError> {
        Self::parse_identity(&source.provider_id, &source.locator, project)
    }
    /// Parse wire identities without inventing v1 display or discovery fields.
    /// Only a current host-owned provider can resolve these labels to authority.
    pub fn parse_identity(
        provider_id: &str,
        locator: &str,
        project: &str,
    ) -> Result<Self, CaptureError> {
        fn valid(text: &str, max: usize) -> bool {
            !text.is_empty() && text.len() <= max && !text.chars().any(char::is_control)
        }
        if !valid(provider_id, 128) || !valid(locator, 4096) || !valid(project, 12288) {
            return Err(CaptureError::InvalidIdentity);
        }
        Ok(Self {
            source: RequestedSource {
                provider_id: provider_id.to_owned(),
                locator: locator.to_owned(),
            },
            project: ProjectId(project.to_owned()),
        })
    }
    pub(super) fn validate_stored_source(
        &self,
        actual: &WorkbenchSourceRef,
    ) -> Result<(), CliError> {
        if self.source.provider_id != actual.provider_id || self.source.locator != actual.locator {
            return Err(protocol_error(
                "Requested source is not present in this provider session",
            ));
        }
        Ok(())
    }
}

/// Each variant owns an actual selected provider with its existing root Dir.
/// An identity payload alone cannot construct one of these provider instances.
#[derive(Clone)]
pub enum OriginalsProvider {
    Native(Arc<NativeWorkspaceProvider>),
    Installed(Arc<ExtensionWorkspaceProvider>),
}
impl OriginalsProvider {
    pub(in crate::commands::ui) fn workspace(&self) -> Arc<dyn super::WorkspaceCapability> {
        match self {
            Self::Native(provider) => provider.clone(),
            Self::Installed(provider) => provider.clone(),
        }
    }
    pub(super) fn validate_selection(
        &self,
        selection: &OriginalsSelection,
    ) -> Result<(), CliError> {
        match self {
            Self::Native(provider) => provider.validate_originals_selection(selection),
            Self::Installed(provider) => provider.validate_originals_selection(selection),
        }
    }
    pub(in crate::commands::ui) async fn resolve(
        &self,
        selection: &OriginalsSelection,
        capacity: &HostModelCaptureCapacity,
    ) -> Result<SourceResolution, ProviderCaptureError> {
        let credit = capacity.reserve_evidence(std::mem::size_of::<ResolvedProjectSource>())?;
        match self {
            Self::Native(provider) => provider.resolve_originals(selection, credit),
            Self::Installed(provider) => provider.resolve_originals(selection, credit).await,
        }
    }
}

pub(in crate::commands::ui) enum SourceResolution {
    Compiled(ResolvedProjectSource),
    NotCompiled,
}
/// Only the real provider resolver constructs this capability. It has no
/// serialization constructor or public accessor for the retained directory.
pub(in crate::commands::ui) struct ResolvedProjectSource {
    output: Dir,
    module: SelectedModule,
    project: Handle,
    output_identity: Handle,
    offer: StartupOffer,
    // All payloads and handles above are dropped before this returns credit.
    _credit: RetainedEvidenceCredit,
}
impl ResolvedProjectSource {
    pub(in crate::commands::ui) fn output(&self) -> &Dir {
        &self.output
    }
    pub(in crate::commands::ui) fn module(&self) -> &SelectedModule {
        &self.module
    }
    pub(in crate::commands::ui) fn same_authority(&self, current: &Self) -> bool {
        self.project == current.project
            && self.output_identity == current.output_identity
            && self.module == current.module
            && self.offer == current.offer
    }
}

// This is called only after the actual provider has validated its stored source
// and performed discovery. Installed membership remains the actual guest's
// response. Compiler output comes from the separately authorized existing host
// Current lookup, not a portable config sidecar or an all-project details map.
pub(super) fn resolve_selected(
    grant: &TrustedHostOutputLookup,
    source: &WorkbenchSourceRef,
    selection: &OriginalsSelection,
    membership: &portable::WorkspaceSnapshot,
    mut credit: RetainedEvidenceCredit,
) -> Result<SourceResolution, ProviderCaptureError> {
    let selected = membership
        .projects
        .iter()
        .find(|project| project_key(source, project.relative_path.as_str()) == selection.project.0)
        .ok_or_else(|| protocol_error("Unknown workspace project for original-source capture"))?;
    if selected.state != portable::ProjectState::Unloaded {
        return Err(
            protocol_error("Selected project is unavailable for original-source capture").into(),
        );
    }
    // The same nofollow traversal used by v1, with the already-owned root.
    grant.verify_root()?;
    let workspace = &grant.directory;
    let workspace_root = &grant.label;
    let project =
        super::project_model::open_project_directory(workspace, selected.relative_path.as_str())?;
    let project_identity = Handle::from_file(project.try_clone()?.into_std_file())?;
    let project_root = workspace_root.join(selected.relative_path.as_str());
    verify_project_label(grant, &project_root, &project_identity)?;
    #[cfg(test)]
    if let Some(hooks) = &grant.hooks {
        hooks.before_current();
    }
    // A coordination hook may hold this boundary in tests; production is also
    // subject to external rename races. Compare the selected label immediately
    // before invoking the trusted ambient Current loader, and again afterward.
    grant.verify_root()?;
    verify_project_label(grant, &project_root, &project_identity)?;
    let context = discover_config_at(&project_root)
        .map_err(CliError::from)?
        .map(|path| {
            let mut options = grant.options.clone();
            options.project = ProjectSelection::Current;
            load_config_context_with(&path, &options)
        })
        .transpose()
        .map_err(CliError::from)?;
    #[cfg(test)]
    if let Some(hooks) = &grant.hooks {
        hooks.after_current();
    }
    let cwd = std::env::current_dir()?;
    grant.verify_root()?;
    verify_project_label(grant, &project_root, &project_identity)?;
    let overrides = &grant.overrides;
    let explicit = overrides.flag.is_some()
        || overrides
            .env
            .as_ref()
            .is_some_and(|value| !value.is_empty());
    let base = if context.is_none() && !explicit {
        &project_root
    } else {
        &cwd
    };
    let out = crate::commands::out_context::OutContext::resolve(context.as_ref(), overrides, base);
    let mut module_bytes = 0_usize;
    for part in out.module.components() {
        let std::path::Component::Normal(name) = part else {
            return Err(protocol_error("Invalid compiler module path").into());
        };
        let text = name
            .to_str()
            .ok_or_else(|| protocol_error("Invalid compiler module Unicode"))?;
        module_bytes = module_bytes
            .checked_add(text.len() + usize::from(module_bytes != 0))
            .ok_or(CaptureError::Capacity)?;
    }
    // The temporary normalized string and the validated retained module each
    // own bytes. Reserve both before their first allocation/copy.
    credit.grow(module_bytes.checked_mul(2).ok_or(CaptureError::Capacity)?)?;
    #[cfg(test)]
    if let Some(hooks) = &grant.hooks {
        hooks.before_module_copy();
    }
    let mut module_text = String::with_capacity(module_bytes);
    for part in out.module.components() {
        if !module_text.is_empty() {
            module_text.push('/');
        }
        module_text.push_str(part.as_os_str().to_str().expect("validated module Unicode"));
    }
    let module =
        SelectedModule::parse(&module_text).map_err(|error| protocol_error(error.to_string()))?;
    let output_path = out.root;
    let output = if explicit {
        Dir::open_ambient_dir(&output_path, grant.ambient)
    } else {
        let relative = output_path
            .strip_prefix(workspace_root)
            .map_err(|_| protocol_error("Configured output root leaves the opened workspace"))?;
        open_output(workspace, relative)
    };
    let output = match output {
        Ok(output) => output,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(SourceResolution::NotCompiled);
        }
        Err(error) => return Err(error.into()),
    };
    let project = Handle::from_file(project.into_std_file())?;
    let output_identity = Handle::from_file(output.try_clone()?.into_std_file())?;
    Ok(SourceResolution::Compiled(ResolvedProjectSource {
        output,
        module,
        project,
        output_identity,
        offer: grant.offer,
        _credit: credit,
    }))
}
fn verify_project_label(
    grant: &TrustedHostOutputLookup,
    label: &Path,
    identity: &Handle,
) -> Result<(), CliError> {
    let actual = Dir::open_ambient_dir(label, grant.ambient)?;
    if Handle::from_file(actual.into_std_file())? != *identity {
        return Err(protocol_error("Original-source selected project changed"));
    }
    Ok(())
}
fn open_output(workspace: &Dir, path: &Path) -> std::io::Result<Dir> {
    let mut directory = workspace.try_clone()?;
    for part in path.components() {
        let std::path::Component::Normal(name) = part else {
            return Err(std::io::Error::other("Output directory is not confined"));
        };
        directory = directory.open_dir_nofollow(name)?;
    }
    Ok(directory)
}

#[cfg(test)]
mod tests;
