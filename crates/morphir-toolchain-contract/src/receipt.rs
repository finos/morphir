//! The local installation receipt of one toolchain generation, kept under
//! `MORPHIR_HOME/toolchains/generations/<id>/`.
//!
//! A receipt is local data. It binds the SHA-256 of the exact lock bytes, the
//! platform and every installed object identity, and records launch paths,
//! ownership, authentication, claim-check status and readiness evidence.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::envelope;
use crate::ids::{
    DeploymentId, GenerationId, ImplementationId, PackageId, PackageManagerId, Sha256,
    TargetDigest, TargetPath, WorkflowId,
};
use crate::lock::ToolchainLock;
use crate::model::{self, DeliveryKind, LockedProvider, RecipeRef};
use crate::platform::PlatformId;
use crate::reader::{Node, Obj, inconsistent, index, join};
use semver::Version;
use serde_json::Value;

/// Member paths a `0.1.0-draft.1` receipt reader understands.
pub const UNDERSTOOD_PATHS: &[&str] = &[
    "schemaVersion",
    "critical",
    "generationId",
    "platform",
    "lockSha256",
    "recipe",
    "host",
    "host.identity",
    "host.execution",
    "host.installation",
    "host.readiness",
    "host.checks",
    "providers",
    "providers.identity",
    "providers.installation",
    "providers.readiness",
    "providers.checks",
    "readiness",
    "checks",
];

/// Who owns an installation and therefore who updates or removes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Ownership {
    /// Installed and updated by the manager under Morphir Home.
    ManagerOwned,
    /// Extracted from a direct archive by the user.
    DirectArchive,
    /// Installed by `dotnet tool`; updated with the dotnet tool mechanism.
    DotnetTool {
        /// Package id.
        package_id: PackageId,
        /// Installation scope.
        scope: DotnetToolScope,
    },
    /// Installed by a system package manager.
    SystemPackage {
        /// Package manager.
        manager: PackageManagerId,
    },
}

/// A `dotnet tool` installation scope.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DotnetToolScope {
    /// `dotnet tool install --global`.
    Global,
    /// `dotnet tool install --tool-path`.
    ToolPath,
    /// A local tool manifest.
    LocalManifest,
}

/// How the installed bytes were authenticated. This is a separate fact from
/// the extension's claim-check status.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Authentication {
    /// TUF target metadata authenticated the bytes directly.
    RepositoryTarget {
        /// Repository identity.
        repository_id: Sha256,
        /// The trusted targets metadata version.
        targets_version: u64,
    },
    /// The bytes matched a digest in an authenticated recipe.
    RecipeDigest {
        /// Repository identity holding the recipe.
        repository_id: Sha256,
        /// Recipe target.
        recipe_target: TargetPath,
        /// Recipe digest.
        recipe_sha256: Sha256,
    },
    /// An unsigned artifact admitted by explicit developer policy. It carries
    /// no publisher authentication.
    LocalDeveloper,
    /// An externally owned installation the manager did not acquire.
    ExternalOwner,
}

/// How an extension's capability claims were checked at installation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClaimCheck {
    /// The artifact ran and reported its claims.
    Probed(ProbeSource),
    /// The claims were not checked against the artifact.
    Unchecked,
}

/// How a probe read the claims.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProbeSource {
    /// `morphir.extension.describe`.
    Describe,
    /// A session, because the extension does not implement `describe`.
    SessionFallback,
}

/// An absolute local launch command.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Launch {
    /// Absolute program path on this machine.
    pub program: String,
    /// Fixed leading arguments.
    pub args: Vec<String>,
}

/// Installation facts for a host or an external provider.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Installation {
    /// Owner.
    pub ownership: Ownership,
    /// Authentication of the installed bytes.
    pub authentication: Authentication,
    /// Launch command.
    pub launch: Launch,
}

/// Readiness of one component or of the whole generation, in order.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Readiness {
    /// The bytes are present.
    Acquired,
    /// The bytes match their authenticated or locked digests.
    IntegrityVerified,
    /// The host and provider agree on the selected operation and tuple.
    CapabilityChecked,
    /// The fixed compile and generate workflow produced the expected outputs.
    WorkflowQualified,
}

impl Readiness {
    pub(crate) const CASES: &'static [&'static str] = &[
        "acquired",
        "integrity-verified",
        "capability-checked",
        "workflow-qualified",
    ];

    pub(crate) fn from_tag(tag: &str) -> Self {
        match tag {
            "acquired" => Self::Acquired,
            "integrity-verified" => Self::IntegrityVerified,
            "capability-checked" => Self::CapabilityChecked,
            _ => Self::WorkflowQualified,
        }
    }
}

/// A readiness check.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CheckKind {
    /// Digest verification.
    Integrity,
    /// Capability agreement or handshake.
    Capability,
    /// The fixed workflow.
    Workflow,
}

impl CheckKind {
    pub(crate) const CASES: &'static [&'static str] = &["integrity", "capability", "workflow"];

    pub(crate) fn from_tag(tag: &str) -> Self {
        match tag {
            "integrity" => Self::Integrity,
            "capability" => Self::Capability,
            _ => Self::Workflow,
        }
    }

    /// The readiness a passed check of this kind reaches.
    pub fn reaches(&self) -> Readiness {
        match self {
            Self::Integrity => Readiness::IntegrityVerified,
            Self::Capability => Readiness::CapabilityChecked,
            Self::Workflow => Readiness::WorkflowQualified,
        }
    }
}

/// The outcome of a check. Every non-passed outcome stays visible.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CheckStatus {
    /// The check passed.
    Passed,
    /// The check ran and failed.
    Failed(String),
    /// The check did not run.
    Skipped(String),
    /// The check cannot run for this component.
    Unsupported(String),
}

/// One recorded check.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Check {
    /// Kind.
    pub kind: CheckKind,
    /// Outcome.
    pub status: CheckStatus,
    /// The workflow, for a workflow check.
    pub workflow: Option<WorkflowId>,
}

/// The installed host's runtime arrangement.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuntimeOrigin {
    /// Native AOT code needs no runtime.
    None,
    /// An application-local runtime shipped with the host.
    Bundled(Version),
    /// A runtime installed on the system.
    System(Version),
}

/// The exact host identity a receipt binds.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostIdentity {
    /// Implementation.
    pub implementation: ImplementationId,
    /// Exact release.
    pub version: Version,
    /// Deployment offering.
    pub deployment: DeploymentId,
    /// Installed host artifact.
    pub artifact: TargetDigest,
}

/// The installed host.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstalledHost {
    /// Identity.
    pub identity: HostIdentity,
    /// Execution mode and runtime origin.
    pub execution: (crate::recipe::Execution, RuntimeOrigin),
    /// Installation facts.
    pub installation: Installation,
    /// Readiness.
    pub readiness: Readiness,
    /// Integrity and capability checks.
    pub checks: Vec<Check>,
}

/// An installed provider. A built-in has no installation of its own.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstalledProvider {
    /// The locked identity.
    pub identity: LockedProvider,
    /// Installation facts and claim-check status, absent for a built-in.
    pub installation: Option<(Installation, ClaimCheck)>,
    /// Readiness.
    pub readiness: Readiness,
    /// Integrity and capability checks.
    pub checks: Vec<Check>,
}

/// A parsed receipt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallationReceipt {
    /// Local opaque generation id.
    pub generation_id: GenerationId,
    /// Platform the generation was installed for.
    pub platform: PlatformId,
    /// SHA-256 of the exact lock bytes.
    pub lock_sha256: Sha256,
    /// Recipe the lock used.
    pub recipe: RecipeRef,
    /// Installed host.
    pub host: InstalledHost,
    /// Installed providers, in lock order.
    pub providers: Vec<InstalledProvider>,
    /// Generation readiness.
    pub readiness: Readiness,
    /// Generation checks (the workflow).
    pub checks: Vec<Check>,
}

/// Member names that carry credentials. A document refuses them at any depth,
/// including inside members it otherwise ignores.
pub(crate) const CREDENTIAL_MEMBERS: &[&str] = &[
    "password",
    "passwd",
    "secret",
    "token",
    "apikey",
    "api-key",
    "authorization",
    "credential",
    "credentials",
    "cookie",
];

pub(crate) fn refuse_credentials(value: &Value, path: &str) -> Result<()> {
    match value {
        Value::Object(map) => map.iter().try_for_each(|(key, value)| {
            let member = join(path, key);
            if CREDENTIAL_MEMBERS.contains(&key.to_ascii_lowercase().as_str()) {
                Err(Diagnostic::new(
                    Code::CredentialInDocument,
                    member,
                    "credential members never appear in plans, receipts or diagnostics",
                ))
            } else {
                refuse_credentials(value, &member)
            }
        }),
        Value::Array(values) => values
            .iter()
            .enumerate()
            .try_for_each(|(position, value)| refuse_credentials(value, &index(path, position))),
        _ => Ok(()),
    }
}

/// Read a receipt from its exact bytes.
pub fn read_receipt(bytes: &[u8]) -> Result<InstallationReceipt> {
    let value: Value = serde_json::from_slice(bytes).map_err(|error| {
        Diagnostic::new(Code::InvalidDocument, "", format!("not JSON: {error}"))
    })?;
    envelope::check(&value, UNDERSTOOD_PATHS)?;
    refuse_credentials(&value, "")?;
    let root = Node::root(&value).object()?;
    let platform = root.req("platform", model::platform)?;
    let receipt = InstallationReceipt {
        generation_id: root.req("generationId", model::token(GenerationId::parse))?,
        platform,
        lock_sha256: root.req("lockSha256", model::sha256)?,
        recipe: root.req("recipe", model::recipe_ref)?,
        host: root.req("host", |node| installed_host(node, platform))?,
        providers: root.req("providers", |node| {
            node.array(|item| installed_provider(item, platform))
        })?,
        readiness: root.req("readiness", readiness)?,
        checks: root.req("checks", |node| node.array(check))?,
    };
    validate_generation(&receipt)?;
    Ok(receipt)
}

fn readiness(node: Node<'_>) -> Result<Readiness> {
    let tag = node.str()?;
    Readiness::CASES
        .iter()
        .find(|case| **case == tag)
        .map(|case| Readiness::from_tag(case))
        .ok_or_else(|| {
            Diagnostic::new(
                Code::UnsupportedCase,
                node.path(),
                format!("'{tag}' is not one of {}", Readiness::CASES.join(", ")),
            )
        })
}

pub(crate) fn check(node: Node<'_>) -> Result<Check> {
    let object = node.object()?;
    let kind = CheckKind::from_tag(object.tag("check", CheckKind::CASES)?);
    let reason = || -> Result<String> {
        object.req("reason", model::non_empty_string).map_err(|_| {
            inconsistent(
                object.member_path("reason"),
                "a check that did not pass states its reason",
            )
        })
    };
    let status = match object.tag("status", &["passed", "failed", "skipped", "unsupported"])? {
        "passed" => CheckStatus::Passed,
        "failed" => CheckStatus::Failed(reason()?),
        "skipped" => CheckStatus::Skipped(reason()?),
        _ => CheckStatus::Unsupported(reason()?),
    };
    let workflow = object.opt("workflow", model::token(WorkflowId::parse))?;
    if (kind == CheckKind::Workflow) != workflow.is_some() {
        return Err(inconsistent(
            object.member_path("workflow"),
            "a workflow check, and only a workflow check, names its workflow",
        ));
    }
    Ok(Check {
        kind,
        status,
        workflow,
    })
}

fn absolute_program(platform: PlatformId) -> impl Fn(&str) -> std::result::Result<String, String> {
    move |text| {
        let bytes = text.as_bytes();
        let absolute = if platform.is_windows() {
            (bytes.len() > 3
                && bytes[0].is_ascii_alphabetic()
                && bytes[1] == b':'
                && matches!(bytes[2], b'\\' | b'/'))
                || text.starts_with("\\\\")
        } else {
            text.starts_with('/')
        };
        if absolute && !text.contains('\0') {
            Ok(text.to_owned())
        } else {
            Err(format!(
                "'{text}' is not an absolute {platform} launch path"
            ))
        }
    }
}

fn installation(object: &Obj<'_>, platform: PlatformId) -> Result<Installation> {
    let ownership = object.req("ownership", |node| {
        let owner = node.object()?;
        match owner.tag(
            "kind",
            &[
                "manager-owned",
                "direct-archive",
                "dotnet-tool",
                "system-package",
            ],
        )? {
            "manager-owned" => Ok(Ownership::ManagerOwned),
            "direct-archive" => Ok(Ownership::DirectArchive),
            "dotnet-tool" => Ok(Ownership::DotnetTool {
                package_id: owner.req("packageId", model::token(PackageId::parse))?,
                scope: match owner.tag("scope", &["global", "tool-path", "local-manifest"])? {
                    "global" => DotnetToolScope::Global,
                    "tool-path" => DotnetToolScope::ToolPath,
                    _ => DotnetToolScope::LocalManifest,
                },
            }),
            _ => Ok(Ownership::SystemPackage {
                manager: owner.req("manager", model::token(PackageManagerId::parse))?,
            }),
        }
    })?;
    let authentication = object.req("authentication", |node| {
        let auth = node.object()?;
        match auth.tag(
            "kind",
            &[
                "repository-target",
                "recipe-digest",
                "local-developer",
                "external-owner",
            ],
        )? {
            "repository-target" => Ok(Authentication::RepositoryTarget {
                repository_id: auth.req("repositoryId", model::sha256)?,
                targets_version: auth.req("targetsVersion", |node| node.u64())?,
            }),
            "recipe-digest" => Ok(Authentication::RecipeDigest {
                repository_id: auth.req("repositoryId", model::sha256)?,
                recipe_target: auth.req("recipeTarget", model::target_path)?,
                recipe_sha256: auth.req("recipeSha256", model::sha256)?,
            }),
            "local-developer" => {
                if auth.str("policy")? != "developer" {
                    return Err(inconsistent(
                        auth.member_path("policy"),
                        "an unsigned developer artifact requires the explicit developer policy",
                    ));
                }
                Ok(Authentication::LocalDeveloper)
            }
            _ => Ok(Authentication::ExternalOwner),
        }
    })?;
    if authentication == Authentication::LocalDeveloper && ownership != Ownership::ManagerOwned {
        return Err(inconsistent(
            object.member_path("ownership"),
            "a developer artifact is admitted only into manager-owned storage",
        ));
    }
    if authentication == Authentication::ExternalOwner && ownership == Ownership::ManagerOwned {
        return Err(inconsistent(
            object.member_path("authentication"),
            "a manager-owned installation records how the manager authenticated it",
        ));
    }
    let launch = object.req("launch", |node| {
        let launch = node.object()?;
        Ok(Launch {
            program: launch.req("program", |node| {
                node.parse(Code::InvalidValue, absolute_program(platform))
            })?,
            args: launch.req("args", |node| {
                node.array(|item| item.str().map(str::to_owned))
            })?,
        })
    })?;
    Ok(Installation {
        ownership,
        authentication,
        launch,
    })
}

fn component_checks(object: &Obj<'_>) -> Result<(Readiness, Vec<Check>)> {
    let readiness_path = object.member_path("readiness");
    let readiness = object.req("readiness", readiness)?;
    let checks = object.req("checks", |node| node.array(check))?;
    let find = |kind: CheckKind| {
        checks
            .iter()
            .filter(|check| check.kind == kind)
            .collect::<Vec<_>>()
    };
    let integrity = find(CheckKind::Integrity);
    let capability = find(CheckKind::Capability);
    if integrity.len() != 1 || capability.len() != 1 || !find(CheckKind::Workflow).is_empty() {
        return Err(inconsistent(
            object.member_path("checks"),
            "a component records exactly one integrity and one capability check",
        ));
    }
    let derived = match (&integrity[0].status, &capability[0].status) {
        (CheckStatus::Passed, CheckStatus::Passed) => Readiness::CapabilityChecked,
        (CheckStatus::Passed, _) => Readiness::IntegrityVerified,
        _ => Readiness::Acquired,
    };
    if readiness != derived {
        return Err(inconsistent(
            readiness_path,
            format!("the recorded checks reach {derived:?}, not {readiness:?}"),
        ));
    }
    Ok((readiness, checks))
}

fn installed_host(node: Node<'_>, platform: PlatformId) -> Result<InstalledHost> {
    let host = node.object()?;
    let identity = host.req("identity", |node| {
        let identity = node.object()?;
        Ok(HostIdentity {
            implementation: identity
                .req("implementation", model::token(ImplementationId::parse))?,
            version: identity.req("version", model::version)?,
            deployment: identity.req("deployment", model::token(DeploymentId::parse))?,
            artifact: model::digest_pair(&identity, "target", "sha256")?,
        })
    })?;
    let execution = host.req("execution", |node| {
        let execution = node.object()?;
        let mode = match execution.tag("mode", &["native-aot", "jit"])? {
            "native-aot" => crate::recipe::Execution::NativeAot,
            _ => crate::recipe::Execution::Jit,
        };
        let runtime = execution.req("runtime", |node| {
            let runtime = node.object()?;
            match runtime.tag("kind", &["none", "bundled", "system"])? {
                "none" => Ok(RuntimeOrigin::None),
                "bundled" => Ok(RuntimeOrigin::Bundled(
                    runtime.req("version", model::version)?,
                )),
                _ => Ok(RuntimeOrigin::System(
                    runtime.req("version", model::version)?,
                )),
            }
        })?;
        if (mode == crate::recipe::Execution::NativeAot) != (runtime == RuntimeOrigin::None) {
            return Err(inconsistent(
                execution.member_path("runtime"),
                "Native AOT has no runtime; JIT execution records its runtime origin",
            ));
        }
        Ok((mode, runtime))
    })?;
    let installation = host.req("installation", |node| {
        installation(&node.object()?, platform)
    })?;
    let (readiness, checks) = component_checks(&host)?;
    Ok(InstalledHost {
        identity,
        execution,
        installation,
        readiness,
        checks,
    })
}

fn installed_provider(node: Node<'_>, platform: PlatformId) -> Result<InstalledProvider> {
    let provider = node.object()?;
    let identity = provider.req("identity", model::locked_provider)?;
    let built_in = identity.delivery.kind() == DeliveryKind::BuiltIn;
    let installation = match (built_in, provider.has("installation")) {
        (true, true) => {
            return Err(inconsistent(
                provider.member_path("installation"),
                "a built-in provider is part of the host and has no installation of its own",
            ));
        }
        (true, false) => None,
        (false, _) => Some(provider.req("installation", |node| {
            let object = node.object()?;
            let installed = installation(&object, platform)?;
            let claim_check = match object.tag("claimCheck", &["probed", "unchecked"])? {
                "probed" => ClaimCheck::Probed(
                    match object.tag("probeSource", &["describe", "session-fallback"])? {
                        "describe" => ProbeSource::Describe,
                        _ => ProbeSource::SessionFallback,
                    },
                ),
                _ => {
                    if object.has("probeSource") {
                        return Err(inconsistent(
                            object.member_path("probeSource"),
                            "an unchecked claim set has no probe source",
                        ));
                    }
                    ClaimCheck::Unchecked
                }
            };
            Ok((installed, claim_check))
        })?),
    };
    let (readiness, checks) = component_checks(&provider)?;
    Ok(InstalledProvider {
        identity,
        installation,
        readiness,
        checks,
    })
}

fn validate_generation(receipt: &InstallationReceipt) -> Result<()> {
    let workflows = receipt
        .checks
        .iter()
        .filter(|check| check.kind == CheckKind::Workflow)
        .collect::<Vec<_>>();
    if workflows.len() != 1 || receipt.checks.len() != 1 {
        return Err(inconsistent(
            "checks",
            "a generation records exactly one workflow check",
        ));
    }
    let lowest = receipt
        .providers
        .iter()
        .map(|provider| provider.readiness)
        .chain(std::iter::once(receipt.host.readiness))
        .min()
        .expect("the host is always present");
    let derived =
        if lowest == Readiness::CapabilityChecked && workflows[0].status == CheckStatus::Passed {
            Readiness::WorkflowQualified
        } else {
            lowest
        };
    if receipt.readiness != derived {
        return Err(inconsistent(
            "readiness",
            format!(
                "the components and workflow check reach {derived:?}, not {:?}",
                receipt.readiness
            ),
        ));
    }
    Ok(())
}

impl InstallationReceipt {
    /// Refuse the receipt unless it binds exactly these lock bytes and repeats
    /// the locked identities for its platform.
    pub fn check_lock(&self, lock_bytes: &[u8], lock: &ToolchainLock) -> Result<()> {
        let actual = Sha256::of_bytes(lock_bytes);
        if self.lock_sha256 != actual {
            return Err(Diagnostic::new(
                Code::LockChanged,
                "lockSha256",
                format!(
                    "the receipt binds lock {}, but the lock bytes hash to {actual}",
                    self.lock_sha256
                ),
            ));
        }
        let mismatch = |path: &str, what: &str| {
            Diagnostic::new(
                Code::ReceiptLockMismatch,
                path,
                format!("{what} differs from the lock's {} closure", self.platform),
            )
        };
        if self.recipe != lock.recipe {
            return Err(mismatch("recipe", "the recipe"));
        }
        let closure = lock.closure(self.platform)?;
        let host = &self.host.identity;
        if host.implementation != lock.host.implementation
            || host.version != lock.host.version
            || host.deployment != lock.host.deployment
            || host.artifact != closure.host
        {
            return Err(mismatch("host.identity", "the host identity"));
        }
        if self.providers.len() != closure.providers.len() {
            return Err(mismatch("providers", "the provider list"));
        }
        for (position, (installed, locked)) in
            self.providers.iter().zip(&closure.providers).enumerate()
        {
            if &installed.identity != locked {
                return Err(mismatch(
                    &join(&index("providers", position), "identity"),
                    "the provider identity",
                ));
            }
        }
        Ok(())
    }
}
