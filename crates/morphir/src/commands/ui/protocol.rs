//! Versioned wire types shared by the loopback web host and Morphir Web.

use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::error::CliError;

pub const CONNECTED_PROTOCOL_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum ConnectedMethod {
    #[serde(rename = "morphir.session.initialize")]
    Initialize,
    #[serde(rename = "morphir.development.inspect")]
    DevelopmentInspect,
    #[serde(rename = "morphir.workspace.open")]
    WorkspaceOpen,
    #[serde(rename = "morphir.workspace.watch")]
    WorkspaceWatch,
    #[serde(rename = "morphir.workspace.unwatch")]
    WorkspaceUnwatch,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct JsonRpcRequest {
    pub jsonrpc: JsonRpcVersion,
    pub id: u64,
    pub method: ConnectedMethod,
    pub params: Value,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum JsonRpcVersion {
    #[serde(rename = "2.0")]
    V2,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkbenchSourceRef {
    pub provider_id: String,
    pub locator: String,
    pub display_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub persistence: Option<SourcePersistence>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum SourcePersistence {
    Session,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkbenchCapability {
    pub name: String,
    pub version: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProviderProvenance {
    pub extension_id: String,
    pub extension_version: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProviderManifest {
    pub id: String,
    pub name: String,
    pub kind: ProviderKind,
    pub status: ProviderStatus,
    pub capabilities: Vec<WorkbenchCapability>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provenance: Option<ProviderProvenance>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum ProviderKind {
    Connected,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum ProviderStatus {
    Available,
    Disconnected,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SessionManifest {
    pub protocol_version: u32,
    pub web_socket_path: String,
    pub session_id: String,
    pub providers: Vec<ProviderManifest>,
    pub initial_sources: Vec<WorkbenchSourceRef>,
}

impl SessionManifest {
    pub fn validate(self) -> Result<Self, CliError> {
        if self.protocol_version != CONNECTED_PROTOCOL_VERSION {
            return Err(protocol_error(format!(
                "Unsupported connected protocol version {}",
                self.protocol_version
            )));
        }
        if self.web_socket_path != "/rpc" {
            return Err(protocol_error("The connected WebSocket path must be /rpc"));
        }
        let provider_ids = self
            .providers
            .iter()
            .map(|provider| provider.id.as_str())
            .collect::<BTreeSet<_>>();
        if provider_ids.len() != self.providers.len() {
            return Err(protocol_error(
                "Connected session provider IDs must be unique",
            ));
        }
        if self
            .initial_sources
            .iter()
            .any(|source| !provider_ids.contains(source.provider_id.as_str()))
        {
            return Err(protocol_error(
                "Connected session initial sources must reference an advertised provider",
            ));
        }
        Ok(self)
    }
}

#[derive(Default)]
pub struct RequestLedger {
    seen: BTreeSet<u64>,
}

impl RequestLedger {
    pub fn register(&mut self, id: u64) -> Result<(), CliError> {
        if self.seen.insert(id) {
            Ok(())
        } else {
            Err(protocol_error(format!(
                "JSON-RPC request ID {id} was already used"
            )))
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DevelopmentWorkbenchDescriptor {
    pub id: String,
    pub source: WorkbenchSourceRef,
    pub name: String,
    pub kind: DevelopmentWorkbenchKind,
    pub route: DevelopmentWorkbenchRoute,
    pub opened_at: String,
    pub last_used_at: String,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum DevelopmentWorkbenchKind {
    Development,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum DevelopmentWorkbenchRoute {
    Overview,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct InspectResult {
    pub descriptor: DevelopmentWorkbenchDescriptor,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkspaceSnapshot {
    pub id: String,
    pub root: WorkbenchSourceRef,
    pub name: Option<String>,
    pub config_anchor: Option<String>,
    pub state: WorkspaceState,
    pub projects: Vec<ProjectSnapshot>,
    pub model_sources: Vec<WorkbenchSourceRef>,
    pub knowledge_base_sources: Vec<WorkbenchSourceRef>,
    pub diagnostics: Vec<WorkspaceDiagnostic>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum WorkspaceState {
    Open,
    Error,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectSnapshot {
    pub id: String,
    pub name: String,
    pub version: Option<String>,
    pub relative_path: String,
    pub config_anchor: Option<String>,
    pub source_directory: String,
    pub state: ProjectState,
    pub model_sources: Vec<WorkbenchSourceRef>,
    pub knowledge_base_sources: Vec<WorkbenchSourceRef>,
    pub diagnostics: Vec<WorkspaceDiagnostic>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum ProjectState {
    Unloaded,
    Error,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkspaceDiagnostic {
    pub severity: DiagnosticSeverity,
    pub code: Option<String>,
    pub message: String,
    pub path: Option<String>,
    pub project_id: Option<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum DiagnosticSeverity {
    Info,
    Warning,
    Error,
}

pub fn source_key(source: &WorkbenchSourceRef) -> String {
    serde_json::to_string(&[source.provider_id.as_str(), source.locator.as_str()])
        .expect("source keys contain only strings")
}

pub fn project_key(root: &WorkbenchSourceRef, relative_path: &str) -> String {
    serde_json::to_string(&[
        root.provider_id.as_str(),
        root.locator.as_str(),
        relative_path,
    ])
    .expect("project keys contain only strings")
}

pub(crate) fn protocol_error(message: impl Into<String>) -> CliError {
    CliError::Validation {
        message: message.into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest() -> SessionManifest {
        SessionManifest {
            protocol_version: 1,
            web_socket_path: "/rpc".into(),
            session_id: "session-1".into(),
            providers: vec![ProviderManifest {
                id: "cli:session-1".into(),
                name: "Morphir CLI".into(),
                kind: ProviderKind::Connected,
                status: ProviderStatus::Available,
                capabilities: vec![],
                provenance: None,
            }],
            initial_sources: vec![WorkbenchSourceRef {
                provider_id: "cli:session-1".into(),
                locator: "workspace:initial".into(),
                display_name: "orders".into(),
                persistence: None,
            }],
        }
    }

    #[test]
    fn session_manifest_round_trips_and_enforces_references() {
        let encoded = serde_json::to_string(&manifest()).unwrap();
        let decoded = serde_json::from_str::<SessionManifest>(&encoded)
            .unwrap()
            .validate()
            .unwrap();
        assert_eq!(decoded, manifest());

        let mut duplicate = manifest();
        duplicate.providers.push(duplicate.providers[0].clone());
        assert!(duplicate.validate().is_err());

        let mut foreign = manifest();
        foreign.initial_sources[0].provider_id = "cli:other".into();
        assert!(foreign.validate().is_err());
    }

    #[test]
    fn rejects_unknown_methods_and_protocol_versions() {
        assert!(
            serde_json::from_value::<JsonRpcRequest>(serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "morphir.filesystem.read",
                "params": {}
            }))
            .is_err()
        );
        let mut incompatible = manifest();
        incompatible.protocol_version = 2;
        assert!(incompatible.validate().is_err());
    }

    #[test]
    fn request_ids_cannot_be_reused() {
        let mut ledger = RequestLedger::default();
        ledger.register(7).unwrap();
        assert!(ledger.register(7).is_err());
    }
}
