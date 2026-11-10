//! The project toolchain request, `.morphir/toolchain.toml` (TOML 1.0).

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::envelope;
use crate::ids::{DeploymentId, ExtensionIdentity, ImplementationId, PresetId, Sha256, WasmAbi};
use crate::model::{self, DeliveryKind, Operation};
use crate::platform::PlatformId;
use crate::reader::{Node, inconsistent};
use morphir_distribution::Channel;
use semver::Version;
use serde_json::Value;
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

/// Member paths a `0.1.0-draft.1` request reader understands.
pub const UNDERSTOOD_PATHS: &[&str] = &[
    "schemaVersion",
    "critical",
    "platforms",
    "host",
    "host.implementation",
    "host.deployment",
    "host.channel",
    "host.version",
    "toolset",
    "toolset.preset",
    "toolset.providers",
    "toolset.providers.operation",
    "toolset.providers.language",
    "toolset.providers.target",
    "toolset.providers.delivery",
    "toolset.providers.extensionId",
    "toolset.providers.abi",
];

/// How the request selects a host release. Exactly one applies.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HostSelection {
    /// Resolve a moving channel.
    Channel(Channel),
    /// Select one exact release.
    Exact(Version),
}

/// The requested host.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequestedHost {
    /// Implementation, such as `dotnet`.
    pub implementation: ImplementationId,
    /// Deployment offering, such as `native-aot`.
    pub deployment: DeploymentId,
    /// Channel or exact release.
    pub selection: HostSelection,
}

/// An explicit provider choice for one operation. An explicit choice always
/// wins over a built-in, and it is the only way to choose a provider that is
/// not the recipe's first for its operation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProviderSelection {
    /// Operation the choice applies to.
    pub operation: Operation,
    /// Required delivery, when stated.
    pub delivery: Option<DeliveryKind>,
    /// Required provider identity, when stated.
    pub extension_id: Option<ExtensionIdentity>,
    /// Required WASM ABI, when stated.
    pub abi: Option<WasmAbi>,
}

/// A parsed toolchain request and its identity.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolchainRequest {
    identity: Sha256,
    platforms: Vec<PlatformId>,
    host: RequestedHost,
    preset: PresetId,
    providers: Vec<ProviderSelection>,
}

impl ToolchainRequest {
    /// SHA-256 of the exact request bytes. Reformatting changes it.
    pub fn identity(&self) -> &Sha256 {
        &self.identity
    }
    /// Unique platforms setup prepares closures for; the current platform when empty.
    pub fn platforms(&self) -> &[PlatformId] {
        &self.platforms
    }
    /// The requested host.
    pub fn host(&self) -> &RequestedHost {
        &self.host
    }
    /// The requested preset.
    pub fn preset(&self) -> &PresetId {
        &self.preset
    }
    /// Explicit provider choices, at most one per operation.
    pub fn providers(&self) -> &[ProviderSelection] {
        &self.providers
    }
}

impl ToolchainRequest {
    /// The platforms a setup on `current` locks: the request's `platforms`
    /// together with `current`, each once, in platform table order.
    pub fn setup_platforms(&self, current: PlatformId) -> Vec<PlatformId> {
        let mut platforms: BTreeSet<PlatformId> = self.platforms().iter().copied().collect();
        platforms.insert(current);
        platforms.into_iter().collect()
    }
}

/// The project request a command started in `start` uses: the
/// `.morphir/toolchain.toml` of `start` or of its nearest ancestor that has
/// one, searching no higher than the host's discovery `boundary`. A
/// workspace root's request therefore applies to every member without one of
/// its own, and requests are never merged. A `start` outside `boundary` has
/// no project request. `exists` says whether a file exists, so the rule is
/// testable without a filesystem.
pub fn discover_request(
    start: &Path,
    boundary: &Path,
    exists: impl Fn(&Path) -> bool,
) -> Option<PathBuf> {
    if !start.starts_with(boundary) {
        return None;
    }
    start
        .ancestors()
        .take_while(|directory| directory.starts_with(boundary))
        .map(|directory| directory.join(".morphir").join("toolchain.toml"))
        .find(|candidate| exists(candidate))
}

/// Read a request from its exact UTF-8 bytes.
pub fn read_request(bytes: &[u8]) -> Result<ToolchainRequest> {
    let text = std::str::from_utf8(bytes).map_err(|error| {
        Diagnostic::new(Code::InvalidDocument, "", format!("not UTF-8: {error}"))
    })?;
    let parsed: toml::Table = toml::from_str(text).map_err(|error| {
        Diagnostic::new(Code::InvalidDocument, "", format!("not TOML: {error}"))
    })?;
    let value = serde_json::to_value(parsed)
        .map_err(|error| Diagnostic::new(Code::InvalidDocument, "", error.to_string()))?;
    read_request_value(&value, Sha256::of_bytes(bytes))
}

fn read_request_value(value: &Value, identity: Sha256) -> Result<ToolchainRequest> {
    envelope::check(value, UNDERSTOOD_PATHS)?;
    let root = Node::root(value).object()?;
    let platforms = root
        .opt("platforms", |node| node.array(model::platform))?
        .unwrap_or_default();
    if platforms.iter().collect::<BTreeSet<_>>().len() != platforms.len() {
        return Err(inconsistent("platforms", "platforms must be unique"));
    }
    let host = root.req("host", |node| {
        let host = node.object()?;
        let implementation = host.req("implementation", model::token(ImplementationId::parse))?;
        let deployment = host.req("deployment", model::token(DeploymentId::parse))?;
        let channel = host.opt("channel", |node| {
            node.parse(Code::InvalidValue, |text| {
                Channel::parse(text).map_err(|error| error.to_string())
            })
        })?;
        let exact = host.opt("version", model::version)?;
        let selection = match (channel, exact) {
            (Some(channel), None) => HostSelection::Channel(channel),
            (None, Some(version)) => HostSelection::Exact(version),
            (Some(_), Some(_)) => {
                return Err(inconsistent(
                    host.path(),
                    "set channel or version, not both",
                ));
            }
            (None, None) => {
                return Err(inconsistent(
                    host.path(),
                    "set exactly one of channel or version",
                ));
            }
        };
        Ok(RequestedHost {
            implementation,
            deployment,
            selection,
        })
    })?;
    let (preset, providers) = root.req("toolset", |node| {
        let toolset = node.object()?;
        let preset = toolset.req("preset", model::token(PresetId::parse))?;
        let providers = toolset
            .opt("providers", |node| {
                node.array(|item| {
                    let selection = item.object()?;
                    let operation = model::operation(&selection)?;
                    let delivery =
                        selection.opt("delivery", |node| node.case(DeliveryKind::CASES))?;
                    let extension_id = selection.opt("extensionId", model::extension_id)?;
                    let abi = selection.opt("abi", model::token(WasmAbi::parse))?;
                    if delivery.is_none() && extension_id.is_none() {
                        return Err(inconsistent(
                            selection.path(),
                            "a provider selection names a delivery, an extensionId or both",
                        ));
                    }
                    if abi.is_some() && delivery != Some(DeliveryKind::Wasm) {
                        return Err(inconsistent(
                            selection.member_path("abi"),
                            "an ABI is chosen only with the wasm delivery",
                        ));
                    }
                    Ok(ProviderSelection {
                        operation,
                        delivery,
                        extension_id,
                        abi,
                    })
                })
            })?
            .unwrap_or_default();
        model::unique_operations(
            "toolset.providers",
            providers.iter().map(|selection| &selection.operation),
        )?;
        Ok((preset, providers))
    })?;
    Ok(ToolchainRequest {
        identity,
        platforms,
        host,
        preset,
        providers,
    })
}
