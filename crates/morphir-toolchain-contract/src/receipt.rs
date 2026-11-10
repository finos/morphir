//! The local installation receipt of one toolchain generation, kept under
//! `MORPHIR_HOME/toolchains/generations/<id>/`.
//!
//! A receipt is local data. It binds the SHA-256 of the exact lock bytes, the
//! platform and every installed object identity, and records launch paths,
//! ownership, authentication, claim-check status and readiness evidence.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::envelope;
use crate::ids::{
    AbsolutePath, DeploymentId, GenerationId, ImplementationId, PackageId, PackageManagerId,
    PathStyle, Sha256, TargetDigest, WorkflowId,
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
    /// The bytes matched a digest in the receipt's own authenticated recipe.
    RecipeDigest,
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
    pub program: AbsolutePath,
    /// Fixed leading arguments.
    pub args: Vec<String>,
}

/// Installation facts for a host or an external provider.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Installation {
    /// Owner.
    ownership: Ownership,
    /// Authentication of the installed bytes.
    authentication: Authentication,
    /// Launch command.
    launch: Launch,
}

impl Installation {
    /// The `ownership` member.
    pub fn ownership(&self) -> &Ownership {
        &self.ownership
    }
    /// The `authentication` member.
    pub fn authentication(&self) -> &Authentication {
        &self.authentication
    }
    /// The `launch` member.
    pub fn launch(&self) -> &Launch {
        &self.launch
    }
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
    pub(crate) const CASES: &'static [(&'static str, Self)] = &[
        ("acquired", Self::Acquired),
        ("integrity-verified", Self::IntegrityVerified),
        ("capability-checked", Self::CapabilityChecked),
        ("workflow-qualified", Self::WorkflowQualified),
    ];
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
    pub(crate) const CASES: &'static [(&'static str, Self)] = &[
        ("integrity", Self::Integrity),
        ("capability", Self::Capability),
        ("workflow", Self::Workflow),
    ];

    /// The readiness a passed check of this kind reaches.
    pub fn reaches(&self) -> Readiness {
        match self {
            Self::Integrity => Readiness::IntegrityVerified,
            Self::Capability => Readiness::CapabilityChecked,
            Self::Workflow => Readiness::WorkflowQualified,
        }
    }
}

/// The outcome of a check. Every non-passed outcome states its reason.
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
    kind: CheckKind,
    /// Outcome.
    status: CheckStatus,
    /// The workflow, for a workflow check and only for one.
    workflow: Option<WorkflowId>,
}

impl Check {
    /// The `kind` member.
    pub fn kind(&self) -> CheckKind {
        self.kind
    }
    /// The `status` member.
    pub fn status(&self) -> &CheckStatus {
        &self.status
    }
    /// The `workflow` member.
    pub fn workflow(&self) -> Option<&WorkflowId> {
        self.workflow.as_ref()
    }
}

/// The runtime a managed host runs on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ManagedRuntime {
    /// An application-local runtime shipped with the host.
    Bundled(Version),
    /// A runtime installed on the system.
    System(Version),
}

/// How the installed host executes. Native AOT has no runtime, so a native
/// AOT host with a runtime cannot be represented.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HostExecution {
    /// Native AOT code.
    NativeAot,
    /// Managed code under a JIT.
    Jit(ManagedRuntime),
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
    identity: HostIdentity,
    execution: HostExecution,
    installation: Installation,
    readiness: Readiness,
    checks: Vec<Check>,
}

impl InstalledHost {
    /// The identity.
    pub fn identity(&self) -> &HostIdentity {
        &self.identity
    }
    /// The execution mode and runtime.
    pub fn execution(&self) -> &HostExecution {
        &self.execution
    }
    /// The installation facts.
    pub fn installation(&self) -> &Installation {
        &self.installation
    }
    /// The derived readiness.
    pub fn readiness(&self) -> Readiness {
        self.readiness
    }
    /// The integrity and capability checks.
    pub fn checks(&self) -> &[Check] {
        &self.checks
    }
}

/// An installed provider. A built-in has no installation of its own.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstalledProvider {
    identity: LockedProvider,
    installation: Option<(Installation, ClaimCheck)>,
    readiness: Readiness,
    checks: Vec<Check>,
}

impl InstalledProvider {
    /// The locked identity.
    pub fn identity(&self) -> &LockedProvider {
        &self.identity
    }
    /// Installation facts and claim-check status, absent for a built-in.
    pub fn installation(&self) -> Option<&(Installation, ClaimCheck)> {
        self.installation.as_ref()
    }
    /// The derived readiness.
    pub fn readiness(&self) -> Readiness {
        self.readiness
    }
    /// The integrity and capability checks.
    pub fn checks(&self) -> &[Check] {
        &self.checks
    }
}

/// A parsed receipt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallationReceipt {
    generation_id: GenerationId,
    platform: PlatformId,
    lock_sha256: Sha256,
    recipe: RecipeRef,
    host: InstalledHost,
    providers: Vec<InstalledProvider>,
    readiness: Readiness,
    checks: Vec<Check>,
}

impl InstallationReceipt {
    /// The local opaque generation id.
    pub fn generation_id(&self) -> &GenerationId {
        &self.generation_id
    }
    /// The platform the generation was installed for.
    pub fn platform(&self) -> PlatformId {
        self.platform
    }
    /// SHA-256 of the exact lock bytes.
    pub fn lock_sha256(&self) -> &Sha256 {
        &self.lock_sha256
    }
    /// The recipe the lock used.
    pub fn recipe(&self) -> &RecipeRef {
        &self.recipe
    }
    /// The installed host.
    pub fn host(&self) -> &InstalledHost {
        &self.host
    }
    /// The installed providers, in lock order.
    pub fn providers(&self) -> &[InstalledProvider] {
        &self.providers
    }
    /// The derived generation readiness.
    pub fn readiness(&self) -> Readiness {
        self.readiness
    }
    /// The generation's workflow check.
    pub fn checks(&self) -> &[Check] {
        &self.checks
    }
}

/// Read a receipt from its exact bytes.
pub fn read_receipt(bytes: &[u8]) -> Result<InstallationReceipt> {
    let value: Value = crate::reader::parse_json(bytes)?;
    envelope::check(&value, UNDERSTOOD_PATHS)?;
    let root = Node::root(&value).object()?;
    let platform = root.req("platform", model::platform)?;
    let recipe = root.req("recipe", model::recipe_ref)?;
    let context = Context {
        platform,
        recipe: &recipe,
    };
    let host = root.req("host", |node| installed_host(node, &context))?;
    let receipt = InstallationReceipt {
        generation_id: root.req("generationId", model::token(GenerationId::parse))?,
        platform,
        lock_sha256: root.req("lockSha256", model::sha256)?,
        providers: root.req("providers", |node| {
            node.array(|item| installed_provider(item, &context, &host))
        })?,
        recipe,
        host,
        readiness: root.req("readiness", |node| node.case(Readiness::CASES))?,
        checks: root.req("checks", |node| node.array(check))?,
    };
    validate_generation(&receipt)?;
    Ok(receipt)
}

struct Context<'a> {
    platform: PlatformId,
    recipe: &'a RecipeRef,
}

#[derive(Clone, Copy)]
enum StatusTag {
    Passed,
    Failed,
    Skipped,
    Unsupported,
}

pub(crate) fn check(node: Node<'_>) -> Result<Check> {
    let object = node.object()?;
    let kind = object.case("check", CheckKind::CASES)?;
    let reason = || -> Result<String> {
        if !object.has("reason") {
            return Err(inconsistent(
                object.member_path("reason"),
                "a check that did not pass states its reason",
            ));
        }
        object.req("reason", model::non_empty_string)
    };
    let status = match object.case(
        "status",
        &[
            ("passed", StatusTag::Passed),
            ("failed", StatusTag::Failed),
            ("skipped", StatusTag::Skipped),
            ("unsupported", StatusTag::Unsupported),
        ],
    )? {
        StatusTag::Passed => CheckStatus::Passed,
        StatusTag::Failed => CheckStatus::Failed(reason()?),
        StatusTag::Skipped => CheckStatus::Skipped(reason()?),
        StatusTag::Unsupported => CheckStatus::Unsupported(reason()?),
    };
    // `workflow` is a member of the workflow case: required there, and
    // contradicting any other check.
    let workflow = if kind == CheckKind::Workflow {
        Some(object.req("workflow", model::token(WorkflowId::parse))?)
    } else {
        if object.has("workflow") {
            return Err(inconsistent(
                object.member_path("workflow"),
                "only a workflow check names a workflow",
            ));
        }
        None
    };
    Ok(Check {
        kind,
        status,
        workflow,
    })
}

#[derive(Clone, Copy)]
enum OwnerTag {
    Manager,
    Archive,
    Tool,
    System,
}

#[derive(Clone, Copy)]
enum AuthenticationTag {
    Repository,
    Recipe,
    Developer,
    External,
}

pub(crate) fn ownership(node: Node<'_>) -> Result<Ownership> {
    let owner = node.object()?;
    match owner.case(
        "kind",
        &[
            ("manager-owned", OwnerTag::Manager),
            ("direct-archive", OwnerTag::Archive),
            ("dotnet-tool", OwnerTag::Tool),
            ("system-package", OwnerTag::System),
        ],
    )? {
        OwnerTag::Manager => Ok(Ownership::ManagerOwned),
        OwnerTag::Archive => Ok(Ownership::DirectArchive),
        OwnerTag::Tool => Ok(Ownership::DotnetTool {
            package_id: owner.req("packageId", model::token(PackageId::parse))?,
            scope: owner.case(
                "scope",
                &[
                    ("global", DotnetToolScope::Global),
                    ("tool-path", DotnetToolScope::ToolPath),
                    ("local-manifest", DotnetToolScope::LocalManifest),
                ],
            )?,
        }),
        OwnerTag::System => Ok(Ownership::SystemPackage {
            manager: owner.req("manager", model::token(PackageManagerId::parse))?,
        }),
    }
}

fn installation(object: &Obj<'_>, context: &Context<'_>) -> Result<Installation> {
    let ownership = object.req("ownership", ownership)?;
    let authentication = object.req("authentication", |node| {
        let auth = node.object()?;
        match auth.case(
            "kind",
            &[
                ("repository-target", AuthenticationTag::Repository),
                ("recipe-digest", AuthenticationTag::Recipe),
                ("local-developer", AuthenticationTag::Developer),
                ("external-owner", AuthenticationTag::External),
            ],
        )? {
            AuthenticationTag::Repository => Ok(Authentication::RepositoryTarget {
                repository_id: auth.req("repositoryId", model::sha256)?,
                targets_version: auth.req("targetsVersion", |node| node.u64())?,
            }),
            AuthenticationTag::Recipe => {
                let named = RecipeRef {
                    repository_id: auth.req("repositoryId", model::sha256)?,
                    target: auth.req("recipeTarget", model::target_path)?,
                    sha256: auth.req("recipeSha256", model::sha256)?,
                };
                if &named != context.recipe {
                    return Err(inconsistent(
                        auth.path(),
                        "recipe-digest authentication names the receipt's own recipe",
                    ));
                }
                Ok(Authentication::RecipeDigest)
            }
            // A receipt always binds a lock, and a lock names only artifacts
            // a recipe authenticated, so an unsigned developer artifact is
            // never part of a toolchain generation. It is installed outside
            // generations, under the extension installer's developer policy.
            AuthenticationTag::Developer => Err(inconsistent(
                auth.path(),
                "an unsigned developer artifact is never part of a locked toolchain generation; label the bytes by how the manager authenticated them",
            )),
            AuthenticationTag::External => Ok(Authentication::ExternalOwner),
        }
    })?;
    if authentication == Authentication::ExternalOwner && ownership == Ownership::ManagerOwned {
        return Err(inconsistent(
            object.member_path("authentication"),
            "a manager-owned installation records how the manager authenticated it",
        ));
    }
    let style = if context.platform.is_windows() {
        PathStyle::Windows
    } else {
        PathStyle::Posix
    };
    let launch = object.req("launch", |node| {
        let launch = node.object()?;
        Ok(Launch {
            program: launch.req("program", |node| {
                node.parse(Code::InvalidValue, |text| AbsolutePath::parse(text, style))
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
    let readiness = object.req("readiness", |node| {
        node.case(&Readiness::CASES[..3]).map_err(|refusal| {
            if refusal.code == Code::UnsupportedCase
                && node.str().is_ok_and(|tag| tag == "workflow-qualified")
            {
                inconsistent(
                    node.path(),
                    "workflow-qualified belongs to the whole generation",
                )
            } else {
                refusal
            }
        })
    })?;
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

#[derive(Clone, Copy)]
enum RuntimeTag {
    None,
    Bundled,
    System,
}

fn execution(node: Node<'_>) -> Result<HostExecution> {
    let execution = node.object()?;
    let mode = execution.case("mode", crate::recipe::Execution::CASES)?;
    let runtime_path = execution.member_path("runtime");
    execution.req("runtime", |node| {
        let runtime = node.object()?;
        let tag = runtime.case(
            "kind",
            &[
                ("none", RuntimeTag::None),
                ("bundled", RuntimeTag::Bundled),
                ("system", RuntimeTag::System),
            ],
        )?;
        match (mode, tag) {
            (crate::recipe::Execution::NativeAot, RuntimeTag::None) => Ok(HostExecution::NativeAot),
            (crate::recipe::Execution::Jit, RuntimeTag::Bundled) => Ok(HostExecution::Jit(
                ManagedRuntime::Bundled(runtime.req("version", model::version)?),
            )),
            (crate::recipe::Execution::Jit, RuntimeTag::System) => Ok(HostExecution::Jit(
                ManagedRuntime::System(runtime.req("version", model::version)?),
            )),
            _ => Err(inconsistent(
                &runtime_path,
                "Native AOT has no runtime; JIT execution records its runtime origin",
            )),
        }
    })
}

/// For the `dotnet` implementation the deployment fixes the execution.
fn check_dotnet_execution(
    identity: &HostIdentity,
    execution: &HostExecution,
    path: &str,
) -> Result<()> {
    if identity.implementation.as_str() != "dotnet" {
        return Ok(());
    }
    let agrees = match identity.deployment.as_str() {
        "native-aot" => matches!(execution, HostExecution::NativeAot),
        "self-contained" => matches!(execution, HostExecution::Jit(ManagedRuntime::Bundled(_))),
        "framework-dependent" | "dotnet-tool" => {
            matches!(execution, HostExecution::Jit(ManagedRuntime::System(_)))
        }
        _ => true,
    };
    if agrees {
        Ok(())
    } else {
        Err(inconsistent(
            path,
            format!(
                "a dotnet {} host does not execute this way",
                identity.deployment
            ),
        ))
    }
}

fn installed_host(node: Node<'_>, context: &Context<'_>) -> Result<InstalledHost> {
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
    let execution = host.req("execution", execution)?;
    check_dotnet_execution(&identity, &execution, &host.member_path("execution"))?;
    let installation = host.req("installation", |node| {
        installation(&node.object()?, context)
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

#[derive(Clone, Copy)]
enum ClaimTag {
    Probed,
    Unchecked,
}

fn installed_provider(
    node: Node<'_>,
    context: &Context<'_>,
    host: &InstalledHost,
) -> Result<InstalledProvider> {
    let provider = node.object()?;
    let identity = provider.req("identity", model::locked_provider)?;
    let built_in = identity.delivery().kind() == DeliveryKind::BuiltIn;
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
            let installed = installation(&object, context)?;
            let claim_check = match object.case(
                "claimCheck",
                &[
                    ("probed", ClaimTag::Probed),
                    ("unchecked", ClaimTag::Unchecked),
                ],
            )? {
                ClaimTag::Probed => ClaimCheck::Probed(object.case(
                    "probeSource",
                    &[
                        ("describe", ProbeSource::Describe),
                        ("session-fallback", ProbeSource::SessionFallback),
                    ],
                )?),
                ClaimTag::Unchecked => {
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
    if built_in {
        // A built-in is part of the host's bytes: its integrity is the host's.
        let status = |checks: &[Check]| {
            checks
                .iter()
                .find(|check| check.kind == CheckKind::Integrity)
                .map(|check| check.status == CheckStatus::Passed)
        };
        if status(&checks) != status(&host.checks) {
            return Err(inconsistent(
                provider.member_path("checks"),
                "a built-in's integrity check is the host's integrity check",
            ));
        }
    }
    Ok(InstalledProvider {
        identity,
        installation,
        readiness,
        checks,
    })
}

fn validate_generation(receipt: &InstallationReceipt) -> Result<()> {
    if receipt.checks.len() != 1 || receipt.checks[0].kind != CheckKind::Workflow {
        return Err(inconsistent(
            "checks",
            "a generation records exactly one workflow check",
        ));
    }
    let lowest = receipt
        .providers
        .iter()
        .map(|provider| provider.readiness)
        .fold(receipt.host.readiness, Ord::min);
    let derived = if lowest == Readiness::CapabilityChecked
        && receipt.checks[0].status == CheckStatus::Passed
    {
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
        if &self.recipe != lock.recipe() {
            return Err(mismatch("recipe", "the recipe"));
        }
        // One repository per binding: bytes the receipt says a repository
        // authenticated came from the lock's repository. `recipe-digest`
        // authentication already names the receipt's own recipe.
        let repository = &lock.recipe().repository_id;
        let installations = std::iter::once(("host".to_owned(), Some(&self.host.installation)))
            .chain(
                self.providers
                    .iter()
                    .enumerate()
                    .map(|(position, provider)| {
                        (
                            index("providers", position),
                            provider
                                .installation
                                .as_ref()
                                .map(|(installation, _)| installation),
                        )
                    }),
            );
        for (path, installation) in installations {
            if let Some(Installation {
                authentication: Authentication::RepositoryTarget { repository_id, .. },
                ..
            }) = installation
                && repository_id != repository
            {
                return Err(Diagnostic::new(
                    Code::RepositoryMismatch,
                    join(&path, "installation.authentication.repositoryId"),
                    format!(
                        "the receipt says repository {repository_id} authenticated these bytes, but the lock binds repository {repository}"
                    ),
                ));
            }
        }
        let closure = lock.closure(self.platform)?;
        let host = &self.host.identity;
        let locked = lock.host();
        if host.implementation != locked.implementation
            || host.version != locked.version
            || host.deployment != locked.deployment
            || &host.artifact != closure.host()
        {
            return Err(mismatch("host.identity", "the host identity"));
        }
        if self.providers.len() != closure.providers().len() {
            return Err(mismatch("providers", "the provider list"));
        }
        for (position, (installed, locked)) in
            self.providers.iter().zip(closure.providers()).enumerate()
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
