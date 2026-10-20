//! Actual host session registrations. Public construction and wire manifests
//! remain unchanged; only the host can replace/revoke this private owner.
use std::sync::{Arc, Mutex, Weak};

use super::{
    PlaygroundCapability, SessionCapabilities, WorkspaceCapability,
    originals::{OriginalsProvider, OriginalsSelection},
};
use crate::{
    commands::ui::{model_originals::ProviderCaptureError, protocol::protocol_error},
    error::CliError,
};

#[derive(Clone)]
pub(crate) struct CurrentSessionCapabilities(Arc<Mutex<CurrentCapabilities>>);

/// A host-issued control over the actual workspace registration. Cloning this
/// handle grants only revocation, never provider selection or registration.
#[derive(Clone)]
pub struct WorkspaceSessionControl(CurrentSessionCapabilities);
impl WorkspaceSessionControl {
    /// Revoke the current workspace and its original-source offer atomically.
    /// This is idempotent and shares the same guard as capture publication.
    pub fn revoke(&self) {
        self.0.revoke_workspace();
    }
}
struct CurrentCapabilities {
    capabilities: SessionCapabilities,
    originals: Option<OriginalsRegistration>,
}
struct OriginalsRegistration {
    id: RegistrationId,
    provider: OriginalsProvider,
}
#[derive(Clone, Copy, Eq, PartialEq)]
struct RegistrationId(uuid::Uuid);

impl CurrentSessionCapabilities {
    pub(crate) fn workspace_control(&self) -> WorkspaceSessionControl {
        WorkspaceSessionControl(self.clone())
    }
    pub(crate) fn new(capabilities: SessionCapabilities) -> Self {
        Self(Arc::new(Mutex::new(CurrentCapabilities {
            capabilities,
            originals: None,
        })))
    }
    pub(crate) fn workspace(&self) -> Option<Arc<dyn WorkspaceCapability>> {
        self.0
            .lock()
            .expect("current UI capabilities")
            .capabilities
            .workspace
            .clone()
    }
    pub(crate) fn playground(&self) -> Option<Arc<dyn PlaygroundCapability>> {
        self.0
            .lock()
            .expect("current UI capabilities")
            .capabilities
            .playground
            .clone()
    }
    /// Register only the typed instance already offered as the actual workspace.
    /// This does not add anything to the public session/capability manifest.
    pub(crate) fn register_originals(&self, provider: OriginalsProvider) -> Result<(), CliError> {
        let mut current = self.0.lock().expect("current UI capabilities");
        let workspace = provider.workspace();
        if !current
            .capabilities
            .workspace
            .as_ref()
            .is_some_and(|actual| Arc::ptr_eq(actual, &workspace))
        {
            return Err(protocol_error(
                "Original-source provider is not the registered workspace",
            ));
        }
        current.originals = Some(OriginalsRegistration {
            id: RegistrationId(uuid::Uuid::new_v4()),
            provider,
        });
        Ok(())
    }
    /// Actual host control updates the same workspace read by v1 snapshots.
    /// No request or source label can invoke this operation.
    pub(crate) fn revoke_workspace(&self) {
        self.replace_workspace(None);
    }
    pub(crate) fn replace_workspace(&self, workspace: Option<Arc<dyn WorkspaceCapability>>) {
        let previous = {
            let mut current = self.0.lock().expect("current UI capabilities");
            let originals = current.originals.take();
            let workspace = std::mem::replace(&mut current.capabilities.workspace, workspace);
            (originals, workspace)
        };
        // A provider's destructor is external code, so never drop its final
        // reference under the session-registration mutex.
        drop(previous);
    }
    pub(crate) fn select_originals(
        &self,
        selection: OriginalsSelection,
    ) -> Result<SelectedOriginalsOffer, CliError> {
        let current = self.0.lock().expect("current UI capabilities");
        let offered = current.originals.as_ref().ok_or_else(|| {
            protocol_error("Original-source offer is not present in this session")
        })?;
        Ok(SelectedOriginalsOffer {
            owner: Arc::downgrade(&self.0),
            registration: offered.id,
            provider: offered.provider.clone(),
            selection,
        })
    }
}

/// Unforgeable selection of one actual host registration, source and project.
/// Holding a provider Arc is insufficient to construct this type.
pub struct SelectedOriginalsOffer {
    owner: Weak<Mutex<CurrentCapabilities>>,
    registration: RegistrationId,
    provider: OriginalsProvider,
    selection: OriginalsSelection,
}
impl SelectedOriginalsOffer {
    pub(in crate::commands::ui) fn provider(&self) -> &OriginalsProvider {
        &self.provider
    }
    pub(in crate::commands::ui) fn selection(&self) -> &OriginalsSelection {
        &self.selection
    }
    pub(in crate::commands::ui) fn with_current<T>(
        &self,
        commit: impl FnOnce(Result<(), ProviderCaptureError>) -> Result<T, ProviderCaptureError>,
    ) -> Result<T, ProviderCaptureError> {
        let Some(owner) = self.owner.upgrade() else {
            return commit(Err(ProviderCaptureError::Changed));
        };
        let current = owner.lock().expect("current UI capabilities");
        let valid = (|| {
            let offered = current
                .originals
                .as_ref()
                .ok_or(ProviderCaptureError::Changed)?;
            let workspace = self.provider.workspace();
            if offered.id != self.registration
                || !current
                    .capabilities
                    .workspace
                    .as_ref()
                    .is_some_and(|actual| Arc::ptr_eq(actual, &workspace))
            {
                return Err(ProviderCaptureError::Changed);
            }
            offered.provider.validate_selection(&self.selection)?;
            Ok(())
        })();
        // Lock order: current session registration -> connection lifecycle.
        // Revoke/replace take only this lock. Never await or do config/guest I/O
        // while held. Prepared publication must execute inside this guard.
        commit(valid)
    }
}
