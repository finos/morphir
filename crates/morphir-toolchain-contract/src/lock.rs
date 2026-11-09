//! The exact portable lock, `.morphir/toolchain.lock.json`.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::envelope;
use crate::ids::{DeploymentId, ImplementationId, Sha256, TargetDigest};
use crate::model::{self, LockedProvider, RecipeRef};
use crate::platform::PlatformId;
use crate::reader::{Node, inconsistent, join};
use crate::request::ToolchainRequest;
use semver::Version;
use serde_json::Value;
use std::collections::BTreeMap;

/// Member paths a `0.1.0-draft.1` lock reader understands.
///
/// Platform keys are data, so paths below `platforms` are not addressable.
pub const UNDERSTOOD_PATHS: &[&str] = &[
    "schemaVersion",
    "critical",
    "requestSha256",
    "recipe",
    "recipe.repositoryId",
    "recipe.target",
    "recipe.sha256",
    "host",
    "host.implementation",
    "host.version",
    "host.deployment",
    "platforms",
];

/// The exact host release a lock selects on every platform.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LockedHost {
    /// Implementation, such as `dotnet`.
    pub implementation: ImplementationId,
    /// Exact release.
    pub version: Version,
    /// Deployment offering.
    pub deployment: DeploymentId,
}

/// The complete dependency closure for one platform.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlatformClosure {
    /// The authenticated host artifact (`hostTarget`, `hostSha256`).
    pub host: TargetDigest,
    /// One provider per required operation.
    pub providers: Vec<LockedProvider>,
}

/// A parsed portable lock. It holds no absolute path and no credential.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolchainLock {
    /// SHA-256 of the exact request bytes the lock was resolved from.
    pub request_sha256: Sha256,
    /// The authenticated recipe the resolution used.
    pub recipe: RecipeRef,
    /// The exact host.
    pub host: LockedHost,
    /// Closures by platform.
    pub platforms: BTreeMap<PlatformId, PlatformClosure>,
}

/// Read a lock from its exact bytes.
pub fn read_lock(bytes: &[u8]) -> Result<ToolchainLock> {
    let value: Value = serde_json::from_slice(bytes).map_err(|error| {
        Diagnostic::new(Code::InvalidDocument, "", format!("not JSON: {error}"))
    })?;
    read_lock_value(&value)
}

pub(crate) fn locked_host(node: Node<'_>) -> Result<LockedHost> {
    let host = node.object()?;
    Ok(LockedHost {
        implementation: host.req("implementation", model::token(ImplementationId::parse))?,
        version: host.req("version", model::version)?,
        deployment: host.req("deployment", model::token(DeploymentId::parse))?,
    })
}

fn read_lock_value(value: &Value) -> Result<ToolchainLock> {
    envelope::check(value, UNDERSTOOD_PATHS)?;
    let root = Node::root(value).object()?;
    let request_sha256 = root.req("requestSha256", model::sha256)?;
    let recipe = root.req("recipe", model::recipe_ref)?;
    let host = root.req("host", locked_host)?;
    let platforms = root.req("platforms", |node| {
        let platforms = node.object()?;
        let closures = platforms.map(PlatformId::parse, |platform, node| {
            let closure = node.object()?;
            let host = model::digest_pair(&closure, "hostTarget", "hostSha256")?;
            let providers = closure.req("providers", |node| node.array(model::locked_provider))?;
            model::unique_operations(
                &join(&join("platforms", platform.as_str()), "providers"),
                providers.iter().map(|provider| &provider.operation),
            )?;
            Ok(PlatformClosure { host, providers })
        })?;
        if closures.is_empty() {
            return Err(inconsistent(
                "platforms",
                "a lock records at least one platform closure",
            ));
        }
        Ok(closures.into_iter().collect::<BTreeMap<_, _>>())
    })?;
    Ok(ToolchainLock {
        request_sha256,
        recipe,
        host,
        platforms,
    })
}

impl ToolchainLock {
    /// Refuse the lock unless it was resolved from exactly these request bytes.
    pub fn check_request(&self, request: &ToolchainRequest) -> Result<()> {
        if self.request_sha256 == request.identity {
            Ok(())
        } else {
            Err(Diagnostic::new(
                Code::RequestChanged,
                "requestSha256",
                format!(
                    "the lock was resolved from request {}, but the request bytes hash to {}; run an explicit setup or update",
                    self.request_sha256, request.identity
                ),
            ))
        }
    }

    /// Return the locked closure for a platform without resolving anything.
    pub fn closure(&self, platform: PlatformId) -> Result<&PlatformClosure> {
        self.platforms.get(&platform).ok_or_else(|| {
            Diagnostic::new(
                Code::PlatformNotLocked,
                "platforms",
                format!(
                    "the lock has no closure for {platform}; it records {}. Extend it with an explicit setup or update",
                    self.platforms
                        .keys()
                        .map(PlatformId::as_str)
                        .collect::<Vec<_>>()
                        .join(", ")
                ),
            )
        })
    }
}
