//! The exact portable lock, `.morphir/toolchain.lock.json`.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::envelope;
use crate::ids::{DeploymentId, ImplementationId, Sha256, TargetDigest};
use crate::model::{self, LockedProvider, Operation, RecipeRef};
use crate::platform::PlatformId;
use crate::reader::{Node, inconsistent, index, join};
use crate::recipe::ToolsetRecipe;
use crate::request::ToolchainRequest;
use semver::Version;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

/// Member paths a `0.1.0-draft.1` lock reader understands. `*` names any
/// platform key; provider members are named through the `providers` array.
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
    "platforms.*",
    "platforms.*.hostTarget",
    "platforms.*.hostSha256",
    "platforms.*.providers",
    "platforms.*.providers.operation",
    "platforms.*.providers.language",
    "platforms.*.providers.target",
    "platforms.*.providers.delivery",
    "platforms.*.providers.extensionId",
    "platforms.*.providers.version",
    "platforms.*.providers.abi",
    "platforms.*.providers.repositoryId",
    "platforms.*.providers.descriptorTarget",
    "platforms.*.providers.descriptorSha256",
    "platforms.*.providers.artifactTarget",
    "platforms.*.providers.artifactSha256",
    "platforms.*.providers.packageId",
    "platforms.*.providers.command",
    "platforms.*.providers.packageTarget",
    "platforms.*.providers.packageSha256",
    "platforms.*.providers.protocolVersion",
    "platforms.*.providers.modelTuple",
    "platforms.*.providers.modelTuple.operation",
    "platforms.*.providers.modelTuple.profile",
    "platforms.*.providers.modelTuple.codec",
    "platforms.*.providers.modelTuple.envelopeVersion",
    "platforms.*.providers.modelTuple.irVersion",
    "platforms.*.providers.modelInput",
    "platforms.*.providers.modelInput.profile",
    "platforms.*.providers.modelInput.codec",
    "platforms.*.providers.modelInput.irVersion",
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
    host: TargetDigest,
    providers: Vec<LockedProvider>,
}

impl PlatformClosure {
    pub(crate) fn new(host: TargetDigest, providers: Vec<LockedProvider>) -> Self {
        Self { host, providers }
    }
    /// The authenticated host artifact (`hostTarget`, `hostSha256`).
    pub fn host(&self) -> &TargetDigest {
        &self.host
    }
    /// One provider per required operation.
    pub fn providers(&self) -> &[LockedProvider] {
        &self.providers
    }
    fn operations(&self) -> BTreeSet<&Operation> {
        self.providers
            .iter()
            .map(LockedProvider::operation)
            .collect()
    }
}

/// A parsed portable lock. It holds no absolute path and no credential, and
/// every recorded platform has a complete closure for the same operations.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolchainLock {
    request_sha256: Sha256,
    recipe: RecipeRef,
    host: LockedHost,
    platforms: BTreeMap<PlatformId, PlatformClosure>,
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
            let providers_path = join(&join("platforms", platform.as_str()), "providers");
            let providers = closure.req("providers", |node| node.array(model::locked_provider))?;
            if providers.is_empty() {
                return Err(inconsistent(
                    providers_path,
                    "a closure has a provider for every required operation",
                ));
            }
            model::unique_operations(
                &providers_path,
                providers.iter().map(LockedProvider::operation),
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
    // The rule relates every closure to every other, so no single platform is
    // the faulty one: the refusal names `platforms`.
    let operations = platforms
        .values()
        .map(PlatformClosure::operations)
        .collect::<BTreeSet<_>>();
    if operations.len() > 1 {
        return Err(inconsistent(
            "platforms",
            "every recorded platform has a complete closure for the same operations",
        ));
    }
    Ok(ToolchainLock {
        request_sha256,
        recipe,
        host,
        platforms,
    })
}

fn recipe_mismatch(path: impl Into<String>, message: impl Into<String>) -> Diagnostic {
    Diagnostic::new(Code::LockRecipeMismatch, path, message)
}

impl ToolchainLock {
    /// SHA-256 of the exact request bytes the lock was resolved from.
    pub fn request_sha256(&self) -> &Sha256 {
        &self.request_sha256
    }
    /// The authenticated recipe the resolution used.
    pub fn recipe(&self) -> &RecipeRef {
        &self.recipe
    }
    /// The exact host.
    pub fn host(&self) -> &LockedHost {
        &self.host
    }
    /// Closures by platform.
    pub fn platforms(&self) -> &BTreeMap<PlatformId, PlatformClosure> {
        &self.platforms
    }

    /// Refuse the lock unless it was resolved from exactly these request bytes.
    pub fn check_request(&self, request: &ToolchainRequest) -> Result<()> {
        if &self.request_sha256 == request.identity() {
            Ok(())
        } else {
            Err(Diagnostic::new(
                Code::RequestChanged,
                "requestSha256",
                format!(
                    "the lock was resolved from request {}, but the request bytes hash to {}; run an explicit setup or update",
                    self.request_sha256,
                    request.identity()
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

    /// Refuse the lock unless it binds these exact recipe bytes and every
    /// closure is one the recipe allows: the offering's artifact for that
    /// platform, and for each recipe operation either the offering's
    /// built-in or a recipe provider bound for that platform.
    pub fn check_recipe(&self, recipe_bytes: &[u8], recipe: &ToolsetRecipe) -> Result<()> {
        if Sha256::of_bytes(recipe_bytes) != self.recipe.sha256 {
            return Err(recipe_mismatch(
                "recipe.sha256",
                "the lock binds other recipe bytes",
            ));
        }
        let host = recipe
            .hosts()
            .iter()
            .find(|host| {
                host.implementation() == &self.host.implementation
                    && host.deployment() == &self.host.deployment
                    && host.version() == &self.host.version
            })
            .ok_or_else(|| recipe_mismatch("host", "the recipe does not offer the locked host"))?;
        let operations = recipe.operations().iter().collect::<BTreeSet<_>>();
        for (platform, closure) in &self.platforms {
            let path = join("platforms", platform.as_str());
            if host.platforms().get(platform) != Some(&closure.host) {
                return Err(recipe_mismatch(
                    join(&path, "hostTarget"),
                    format!("the recipe binds another {platform} host artifact"),
                ));
            }
            if closure.operations() != operations {
                return Err(recipe_mismatch(
                    join(&path, "providers"),
                    "the closure's operations are not the recipe's",
                ));
            }
            for (position, provider) in closure.providers.iter().enumerate() {
                let allowed =
                    crate::resolve::allowed(recipe, host, *platform, provider.operation());
                if !allowed.contains(provider) {
                    return Err(recipe_mismatch(
                        index(&join(&path, "providers"), position),
                        "the recipe binds no such provider for this platform",
                    ));
                }
            }
        }
        Ok(())
    }
}
