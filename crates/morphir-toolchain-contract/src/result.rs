//! The manager JSON result: the one document `morphirup --json` writes to
//! standard output. Progress goes to standard error.

use crate::diagnostic::{Code, Diagnostic, DiagnosticKind, Result};
use crate::envelope;
use crate::ids::{
    AbsolutePath, DeploymentId, ExtensionIdentity, GenerationId, ImplementationId, PathStyle,
    Sha256, TargetDigest, TargetPath, WasmAbi,
};
use crate::lock::{LockedHost, RequestChangeCause, ToolchainLock, locked_host};
use crate::model::{self, DeliveryKind, LockedDelivery, Operation, Prerequisite, RecipeRef};
use crate::platform::PlatformId;
use crate::reader::{Node, Obj, inconsistent, index, join};
use crate::receipt::{CheckKind, Ownership, Readiness, ownership};
use serde_json::Value;

/// Member paths a `0.1.0-draft.1` result reader understands.
pub const UNDERSTOOD_PATHS: &[&str] = &[
    "schemaVersion",
    "critical",
    "command",
    "outcome",
    "plan",
    "planSha256",
    "selection",
    "diagnostics",
];

/// The manager command that produced a result. `run` passes the selected
/// host's own output through and writes no result.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    /// `setup`.
    Setup,
    /// `restore`.
    Restore,
    /// `update`.
    Update,
    /// `show`.
    Show,
    /// `doctor`.
    Doctor,
    /// `list`.
    List,
    /// `default`.
    Default,
    /// `rollback`.
    Rollback,
    /// `repair`.
    Repair,
    /// `remove`.
    Remove,
    /// `self-update`.
    SelfUpdate,
    /// `env`.
    Env,
}

impl Command {
    /// Every command and its spelling.
    pub const CASES: &'static [(&'static str, Self)] = &[
        ("setup", Self::Setup),
        ("restore", Self::Restore),
        ("update", Self::Update),
        ("show", Self::Show),
        ("doctor", Self::Doctor),
        ("list", Self::List),
        ("default", Self::Default),
        ("rollback", Self::Rollback),
        ("repair", Self::Repair),
        ("remove", Self::Remove),
        ("self-update", Self::SelfUpdate),
        ("env", Self::Env),
    ];
}

/// The overall outcome.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    /// A plan-only run; nothing was installed or activated.
    Planned,
    /// The command completed.
    Succeeded,
    /// At least one error diagnostic.
    Failed,
}

/// A toolchain document kind.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DocumentKind {
    /// The project request.
    Request,
    /// The portable lock.
    Lock,
    /// A toolset recipe.
    Recipe,
    /// An installation receipt.
    Receipt,
    /// A manager result.
    Result,
}

impl DocumentKind {
    pub(crate) const CASES: &'static [(&'static str, Self)] = &[
        ("request", Self::Request),
        ("lock", Self::Lock),
        ("recipe", Self::Recipe),
        ("receipt", Self::Receipt),
        ("result", Self::Result),
    ];
}

/// A TUF metadata role.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TufRole {
    /// `root`.
    Root,
    /// `timestamp`.
    Timestamp,
    /// `snapshot`.
    Snapshot,
    /// `targets`.
    Targets,
}

/// A component a plan or diagnostic concerns.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ComponentRef {
    /// A host offering.
    Host {
        /// Implementation.
        implementation: ImplementationId,
        /// Deployment.
        deployment: DeploymentId,
    },
    /// The provider for an operation.
    Provider(Operation),
}

/// Diagnostic severity.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Severity {
    /// The command failed.
    Error,
    /// Reported without failing the command.
    Warning,
}

/// Where a selection came from, in precedence order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SelectionSource {
    /// An explicit command-line selector.
    Cli,
    /// `MORPHIRUP_TOOLCHAIN`.
    Environment,
    /// The nearest project toolchain file.
    Project {
        /// Absolute path of the project request.
        path: AbsolutePath,
    },
    /// The user default.
    UserDefault,
}

/// An alternative offered instead of an unavailable artifact.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Alternative {
    /// Implementation, when it differs.
    pub implementation: Option<ImplementationId>,
    /// Deployment, when it differs.
    pub deployment: Option<DeploymentId>,
    /// Platform, when it differs.
    pub platform: Option<PlatformId>,
}

/// The kind-specific members of a result diagnostic.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ResultDiagnosticKind {
    /// No artifact matches; alternatives are listed, never substituted.
    UnsupportedArtifact {
        /// Component.
        component: ComponentRef,
        /// Requested platform.
        platform: PlatformId,
        /// The missing ABI, for `abi_unavailable`.
        abi: Option<WasmAbi>,
        /// Alternatives.
        alternatives: Vec<Alternative>,
        /// The document member the refusal concerns, when a check of a
        /// document reported it, such as `request` `toolset.providers[1]`.
        at: Option<(DocumentKind, String)>,
    },
    /// A declared runtime, SDK or native prerequisite is absent.
    MissingPrerequisite {
        /// Component.
        component: ComponentRef,
        /// Prerequisite.
        prerequisite: Prerequisite,
        /// Alternatives.
        alternatives: Vec<Alternative>,
    },
    /// Repository authentication or an authenticated binding failed.
    TrustFailure {
        /// Repository identity.
        repository_id: Sha256,
        /// Metadata role, when one failed.
        role: Option<TufRole>,
        /// Target, when one failed.
        target: Option<TargetPath>,
        /// Mirror, without credentials.
        mirror: Option<String>,
        /// The document member a binding check reported, such as `recipe`
        /// `providers[2].repositoryId`.
        at: Option<(DocumentKind, String)>,
    },
    /// Offline work needs content absent from the verified store.
    OfflineContentUnavailable {
        /// Component.
        component: ComponentRef,
        /// Missing target and its digest.
        target: TargetDigest,
    },
    /// Another owner manages the installation.
    OwnershipConflict {
        /// Component.
        component: ComponentRef,
        /// Owner.
        ownership: Ownership,
    },
    /// A readiness check failed.
    ReadinessFailed {
        /// Component.
        component: ComponentRef,
        /// The failed check.
        check: CheckKind,
        /// The readiness reached.
        readiness: Readiness,
    },
    /// A document was refused by its contract reader.
    UnsupportedContract {
        /// Document kind.
        document: DocumentKind,
        /// Member path the reader reported.
        path: String,
    },
    /// The selected generation is not installed; nothing falls back.
    SelectionUnavailable {
        /// Selection source.
        source: SelectionSource,
    },
    /// The request, lock, receipt and recipe do not bind each other.
    LockBinding {
        /// The document the refusal concerns.
        document: DocumentKind,
        /// Member path the check reported.
        path: String,
        /// The platform, for `platform_not_locked`.
        platform: Option<PlatformId>,
        /// For `request_changed`, the likely cause when the bytes differ only
        /// by line endings or a byte order mark.
        cause: Option<RequestChangeCause>,
    },
}

/// A result diagnostic. Its code always belongs to its kind.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResultDiagnostic {
    /// Stable code.
    code: Code,
    /// Severity.
    severity: Severity,
    /// Human-readable message.
    message: String,
    /// What to run next, as an argument vector.
    instruction: Option<Vec<String>>,
    /// Category and its members.
    kind: ResultDiagnosticKind,
}

impl ResultDiagnostic {
    /// The `code` member.
    pub fn code(&self) -> Code {
        self.code
    }
    /// The `severity` member.
    pub fn severity(&self) -> Severity {
        self.severity
    }
    /// The `message` member.
    pub fn message(&self) -> &str {
        &self.message
    }
    /// The `instruction` member.
    pub fn instruction(&self) -> Option<&[String]> {
        self.instruction.as_deref()
    }
    /// The `kind` member.
    pub fn kind(&self) -> &ResultDiagnosticKind {
        &self.kind
    }
}

/// Whether a plan refreshes repository metadata.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MetadataRefresh {
    /// Metadata is refreshed before acquisition.
    Required,
    /// Cached metadata is fresh enough.
    NotRequired,
}

/// Where a planned component comes from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PlanSource {
    /// A target authenticated by TUF target metadata.
    RepositoryTarget {
        /// Repository identity.
        repository_id: Sha256,
        /// Target and digest.
        target: TargetDigest,
    },
    /// A target bound by a digest in the authenticated recipe.
    RecipeDigest {
        /// Repository identity.
        repository_id: Sha256,
        /// Target and digest.
        target: TargetDigest,
    },
    /// Compiled into the host.
    BuiltIn,
    /// An existing installation owned elsewhere.
    ExternalOwner,
}

/// How readiness will run a component.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Probe {
    /// No probe.
    None,
    /// Checked inside the host.
    InHost,
    /// A process probe runs acquired code with the user's rights.
    ProcessWithUserRights,
}

/// One planned component.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanComponent {
    /// Component.
    component: ComponentRef,
    /// Exact release.
    version: semver::Version,
    /// Provider identity.
    extension_id: Option<ExtensionIdentity>,
    /// Provider delivery; present exactly for providers.
    delivery: Option<DeliveryKind>,
    /// Source.
    source: PlanSource,
    /// Bytes to download.
    download_bytes: u64,
    /// Bytes installed.
    installed_bytes: u64,
    /// Owner of updates.
    update_owner: Ownership,
    /// Prerequisites.
    prerequisites: Vec<Prerequisite>,
    /// Readiness probe.
    probe: Probe,
}

impl PlanComponent {
    /// The `component` member.
    pub fn component(&self) -> &ComponentRef {
        &self.component
    }
    /// The `version` member.
    pub fn version(&self) -> &semver::Version {
        &self.version
    }
    /// The `extension_id` member.
    pub fn extension_id(&self) -> Option<&ExtensionIdentity> {
        self.extension_id.as_ref()
    }
    /// The `delivery` member.
    pub fn delivery(&self) -> Option<DeliveryKind> {
        self.delivery
    }
    /// The `source` member.
    pub fn source(&self) -> &PlanSource {
        &self.source
    }
    /// The `download_bytes` member.
    pub fn download_bytes(&self) -> u64 {
        self.download_bytes
    }
    /// The `installed_bytes` member.
    pub fn installed_bytes(&self) -> u64 {
        self.installed_bytes
    }
    /// The `update_owner` member.
    pub fn update_owner(&self) -> &Ownership {
        &self.update_owner
    }
    /// The `prerequisites` member.
    pub fn prerequisites(&self) -> &[Prerequisite] {
        &self.prerequisites
    }
    /// The `probe` member.
    pub fn probe(&self) -> Probe {
        self.probe
    }
}

/// A setup or update plan.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    /// Implementation.
    implementation: ImplementationId,
    /// Deployment.
    deployment: DeploymentId,
    /// Platform.
    platform: PlatformId,
    /// Recipe.
    recipe: RecipeRef,
    /// Metadata refresh.
    metadata_refresh: MetadataRefresh,
    /// Components.
    components: Vec<PlanComponent>,
    /// The complete lock the command will write, every platform included.
    lock: ToolchainLock,
}

impl Plan {
    /// The `implementation` member.
    pub fn implementation(&self) -> &ImplementationId {
        &self.implementation
    }
    /// The `deployment` member.
    pub fn deployment(&self) -> &DeploymentId {
        &self.deployment
    }
    /// The `platform` member.
    pub fn platform(&self) -> PlatformId {
        self.platform
    }
    /// The `recipe` member.
    pub fn recipe(&self) -> &RecipeRef {
        &self.recipe
    }
    /// The `metadata_refresh` member.
    pub fn metadata_refresh(&self) -> MetadataRefresh {
        self.metadata_refresh
    }
    /// The `components` member.
    pub fn components(&self) -> &[PlanComponent] {
        &self.components
    }
    /// The `lock` member: the lock the command writes on success, so the
    /// plan digest covers every platform's closure.
    pub fn lock(&self) -> &ToolchainLock {
        &self.lock
    }
}

/// The explained selection of a `show` result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Selection {
    /// Where it came from.
    pub source: SelectionSource,
    /// The selected generation.
    pub generation_id: GenerationId,
    /// Its platform.
    pub platform: PlatformId,
    /// Its host.
    pub host: LockedHost,
    /// The lock it was installed from, when it came from a lock.
    pub lock_sha256: Option<Sha256>,
}

/// A parsed manager result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManagerResult {
    command: Command,
    outcome: Outcome,
    plan: Option<(Plan, Sha256)>,
    selection: Option<Selection>,
    diagnostics: Vec<ResultDiagnostic>,
}

impl ManagerResult {
    /// The command.
    pub fn command(&self) -> Command {
        self.command
    }
    /// The outcome.
    pub fn outcome(&self) -> Outcome {
        self.outcome
    }
    /// The plan and its verified digest.
    pub fn plan(&self) -> Option<&(Plan, Sha256)> {
        self.plan.as_ref()
    }
    /// The explained selection.
    pub fn selection(&self) -> Option<&Selection> {
        self.selection.as_ref()
    }
    /// The diagnostics.
    pub fn diagnostics(&self) -> &[ResultDiagnostic] {
        &self.diagnostics
    }
}

/// Encode a value as TUF (OLPC) canonical JSON: object members sorted by the
/// bytes of their encoded keys, no insignificant whitespace, strings in
/// Unicode NFC with only `"` and `\` escaped (as `\"` and `\\`) and every
/// other character written as its UTF-8 bytes, integers only.
pub fn canonical_json(value: &Value) -> std::result::Result<Vec<u8>, String> {
    use serde::Serialize;
    let mut bytes = Vec::new();
    let mut serializer =
        serde_json::Serializer::with_formatter(&mut bytes, olpc_cjson::CanonicalFormatter::new());
    value
        .serialize(&mut serializer)
        .map_err(|error| format!("not canonical JSON: {error}"))?;
    Ok(bytes)
}

/// SHA-256 of [`canonical_json`]. `planSha256` is this digest of `plan`.
pub fn canonical_sha256(value: &Value) -> std::result::Result<Sha256, String> {
    canonical_json(value).map(|bytes| Sha256::of_bytes(&bytes))
}

/// The path of the first object, depth first in member order, two of whose
/// member names have the same NFC form.
fn nfc_key_collision(value: &Value, path: &str) -> Option<String> {
    use unicode_normalization::UnicodeNormalization;
    match value {
        Value::Object(map) => {
            let mut seen = std::collections::BTreeSet::new();
            if map
                .keys()
                .any(|key| !seen.insert(key.nfc().collect::<String>()))
            {
                return Some(path.to_owned());
            }
            map.iter()
                .find_map(|(key, value)| nfc_key_collision(value, &join(path, key)))
        }
        Value::Array(items) => items
            .iter()
            .enumerate()
            .find_map(|(position, item)| nfc_key_collision(item, &index(path, position))),
        _ => None,
    }
}

/// Read a result from its exact bytes.
pub fn read_result(bytes: &[u8]) -> Result<ManagerResult> {
    let value: Value = crate::reader::parse_json(bytes)?;
    envelope::check(&value, UNDERSTOOD_PATHS)?;
    let root = Node::root(&value).object()?;
    let command = root.case("command", Command::CASES)?;
    let outcome = root.case(
        "outcome",
        &[
            ("planned", Outcome::Planned),
            ("succeeded", Outcome::Succeeded),
            ("failed", Outcome::Failed),
        ],
    )?;
    let plan = root.opt("plan", |node| {
        let plan = plan(node)?;
        if let Some(object) = nfc_key_collision(node.value(), node.path()) {
            return Err(Diagnostic::new(
                Code::InvalidDocument,
                object,
                "two member names have the same NFC form, so the canonical form cannot hold both",
            ));
        }
        let digest = root.req("planSha256", model::sha256)?;
        let actual = canonical_sha256(node.value())
            .map_err(|message| Diagnostic::new(Code::InvalidDocument, node.path(), message))?;
        if digest != actual {
            return Err(inconsistent(
                "planSha256",
                format!("planSha256 is {digest}, but the canonical plan hashes to {actual}"),
            ));
        }
        Ok((plan, digest))
    })?;
    if plan.is_none() && root.has("planSha256") {
        return Err(inconsistent(
            "planSha256",
            "a result names a plan digest only together with its plan",
        ));
    }
    let selection = root.opt("selection", |node| {
        let selection = node.object()?;
        Ok(Selection {
            source: selection.req("source", selection_source)?,
            generation_id: selection.req("generationId", model::token(GenerationId::parse))?,
            platform: selection.req("platform", model::platform)?,
            host: selection.req("host", locked_host)?,
            lock_sha256: selection.opt("lockSha256", model::sha256)?,
        })
    })?;
    let diagnostics = root.req("diagnostics", |node| node.array(diagnostic))?;
    let failed = diagnostics
        .iter()
        .any(|diagnostic| diagnostic.severity == Severity::Error);
    let consistent = match outcome {
        Outcome::Failed => failed,
        Outcome::Planned => !failed && plan.is_some(),
        Outcome::Succeeded => !failed,
    };
    if !consistent {
        return Err(inconsistent(
            "outcome",
            "a failed outcome has an error diagnostic, any other outcome has none, and planned carries a plan",
        ));
    }
    Ok(ManagerResult {
        command,
        outcome,
        plan,
        selection,
        diagnostics,
    })
}

#[derive(Clone, Copy)]
enum RoleTag {
    Host,
    Provider,
}

fn component(node: Node<'_>) -> Result<ComponentRef> {
    let object = node.object()?;
    match object.case(
        "role",
        &[("host", RoleTag::Host), ("provider", RoleTag::Provider)],
    )? {
        RoleTag::Host => Ok(ComponentRef::Host {
            implementation: object.req("implementation", model::token(ImplementationId::parse))?,
            deployment: object.req("deployment", model::token(DeploymentId::parse))?,
        }),
        RoleTag::Provider => Ok(ComponentRef::Provider(model::operation(&object)?)),
    }
}

fn absolute_path(node: Node<'_>) -> Result<AbsolutePath> {
    node.parse(Code::InvalidValue, |text| {
        AbsolutePath::parse(text, PathStyle::Either)
    })
}

#[derive(Clone, Copy)]
enum SourceTag {
    Cli,
    Environment,
    Project,
    UserDefault,
}

fn selection_source(node: Node<'_>) -> Result<SelectionSource> {
    let object = node.object()?;
    match object.case(
        "kind",
        &[
            ("cli", SourceTag::Cli),
            ("environment", SourceTag::Environment),
            ("project", SourceTag::Project),
            ("user-default", SourceTag::UserDefault),
        ],
    )? {
        SourceTag::Cli => Ok(SelectionSource::Cli),
        SourceTag::Environment => Ok(SelectionSource::Environment),
        SourceTag::Project => Ok(SelectionSource::Project {
            path: object.req("path", absolute_path)?,
        }),
        SourceTag::UserDefault => Ok(SelectionSource::UserDefault),
    }
}

/// A reported mirror carries no user information, query or fragment.
fn mirror(node: Node<'_>) -> Result<String> {
    let text = node.str()?;
    let url = url::Url::parse(text).map_err(|error| {
        Diagnostic::new(
            Code::InvalidValue,
            node.path(),
            format!("not a URL: {error}"),
        )
    })?;
    // A mirror is an explicit http or https URL with a host, read the same
    // on every operating system: no bare path, no file: URL, no drive letter.
    if !matches!(url.scheme(), "https" | "http") || url.host_str().is_none_or(str::is_empty) {
        return Err(Diagnostic::new(
            Code::InvalidValue,
            node.path(),
            "a mirror is an https or http URL with a host",
        ));
    }
    if !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err(Diagnostic::new(
            Code::CredentialInDocument,
            node.path(),
            "a reported mirror carries no user information, query or fragment",
        ));
    }
    Ok(text.to_owned())
}

/// The optional `document` and `path` of a diagnostic that a check of one
/// document reported. They come together: one without the other is
/// `inconsistent_document` at the member that is present.
fn document_member(object: &Obj<'_>) -> Result<Option<(DocumentKind, String)>> {
    let document = object.opt("document", |node| node.case(DocumentKind::CASES))?;
    let path = object.opt("path", |node| node.str().map(str::to_owned))?;
    match (document, path) {
        (Some(document), Some(path)) => Ok(Some((document, path))),
        (None, None) => Ok(None),
        (Some(_), None) => Err(inconsistent(
            object.member_path("document"),
            "a diagnostic names a document only together with the path in it",
        )),
        (None, Some(_)) => Err(inconsistent(
            object.member_path("path"),
            "a diagnostic names a path only together with its document",
        )),
    }
}

fn alternatives(object: &Obj<'_>) -> Result<Vec<Alternative>> {
    Ok(object
        .opt("alternatives", |node| {
            node.array(|item| {
                let alternative = item.object()?;
                Ok(Alternative {
                    implementation: alternative
                        .opt("implementation", model::token(ImplementationId::parse))?,
                    deployment: alternative.opt("deployment", model::token(DeploymentId::parse))?,
                    platform: alternative.opt("platform", model::platform)?,
                })
            })
        })?
        .unwrap_or_default())
}

fn diagnostic(node: Node<'_>) -> Result<ResultDiagnostic> {
    let object = node.object()?;
    let kind_tag = object.case("kind", DiagnosticKind::CASES)?;
    let code_path = object.member_path("code");
    let code = object.req("code", |node| {
        let spelling = node.str()?;
        Code::parse(spelling).ok_or_else(|| {
            Diagnostic::new(
                Code::UnsupportedCase,
                node.path(),
                format!("'{spelling}' is not a stable code"),
            )
        })
    })?;
    if code.kind() != kind_tag {
        return Err(inconsistent(
            code_path,
            format!(
                "{code} is reported by a {} diagnostic, not {}",
                code.kind().as_str(),
                kind_tag.as_str()
            ),
        ));
    }
    let severity = object.case(
        "severity",
        &[("error", Severity::Error), ("warning", Severity::Warning)],
    )?;
    let message = object.req("message", model::non_empty_string)?;
    let instruction = object.opt("instruction", |node| {
        let words = node.array(|item| item.str().map(str::to_owned))?;
        if words.is_empty() {
            return Err(inconsistent(
                node.path(),
                "an instruction is a non-empty argument vector",
            ));
        }
        Ok(words)
    })?;
    let kind = match kind_tag {
        DiagnosticKind::UnsupportedArtifact => {
            let abi = object.opt("abi", model::token(WasmAbi::parse))?;
            if (code == Code::AbiUnavailable) != abi.is_some() {
                return Err(inconsistent(
                    object.member_path("abi"),
                    "abi_unavailable names the missing ABI, and only it does",
                ));
            }
            ResultDiagnosticKind::UnsupportedArtifact {
                component: object.req("component", component)?,
                platform: object.req("platform", model::platform)?,
                abi,
                alternatives: alternatives(&object)?,
                at: document_member(&object)?,
            }
        }
        DiagnosticKind::MissingPrerequisite => ResultDiagnosticKind::MissingPrerequisite {
            component: object.req("component", component)?,
            prerequisite: object.req("prerequisite", model::prerequisite)?,
            alternatives: alternatives(&object)?,
        },
        DiagnosticKind::TrustFailure => ResultDiagnosticKind::TrustFailure {
            repository_id: object.req("repositoryId", model::sha256)?,
            role: object.opt("role", |node| {
                node.case(&[
                    ("root", TufRole::Root),
                    ("timestamp", TufRole::Timestamp),
                    ("snapshot", TufRole::Snapshot),
                    ("targets", TufRole::Targets),
                ])
            })?,
            target: object.opt("target", model::target_path)?,
            mirror: object.opt("mirror", mirror)?,
            at: document_member(&object)?,
        },
        DiagnosticKind::OfflineContentUnavailable => {
            ResultDiagnosticKind::OfflineContentUnavailable {
                component: object.req("component", component)?,
                target: model::digest_pair(&object, "target", "sha256")?,
            }
        }
        DiagnosticKind::OwnershipConflict => ResultDiagnosticKind::OwnershipConflict {
            component: object.req("component", component)?,
            ownership: object.req("ownership", ownership)?,
        },
        DiagnosticKind::ReadinessFailed => {
            let check = object.case("check", CheckKind::CASES)?;
            let readiness_path = object.member_path("readiness");
            let readiness = object.case("readiness", Readiness::CASES)?;
            if readiness >= check.reaches() {
                return Err(inconsistent(
                    readiness_path,
                    "a failed check leaves readiness below the state that check reaches",
                ));
            }
            ResultDiagnosticKind::ReadinessFailed {
                component: object.req("component", component)?,
                check,
                readiness,
            }
        }
        DiagnosticKind::UnsupportedContract => {
            let document = object.case("document", DocumentKind::CASES)?;
            let path = object.str("path")?.to_owned();
            // An unavailable document was never read, so no member of it
            // can be named.
            if code == Code::DocumentUnavailable && !path.is_empty() {
                return Err(inconsistent(
                    object.member_path("path"),
                    "document_unavailable concerns the whole document, so its path is empty",
                ));
            }
            ResultDiagnosticKind::UnsupportedContract { document, path }
        }
        DiagnosticKind::SelectionUnavailable => ResultDiagnosticKind::SelectionUnavailable {
            source: object.req("source", selection_source)?,
        },
        DiagnosticKind::LockBinding => {
            let platform = object.opt("platform", model::platform)?;
            if (code == Code::PlatformNotLocked) != platform.is_some() {
                return Err(inconsistent(
                    object.member_path("platform"),
                    "platform_not_locked names the platform, and only it does",
                ));
            }
            let cause = object.opt("cause", |node| node.case(RequestChangeCause::CASES))?;
            if cause.is_some() && code != Code::RequestChanged {
                return Err(inconsistent(
                    object.member_path("cause"),
                    "only request_changed names the likely cause of a request change",
                ));
            }
            let document = object.case("document", DocumentKind::CASES)?;
            // Each lock-binding code concerns a member of one fixed document.
            let fixed = match code {
                Code::LockChanged | Code::ReceiptLockMismatch => DocumentKind::Receipt,
                Code::PlanChanged => DocumentKind::Result,
                _ => DocumentKind::Lock,
            };
            if document != fixed {
                return Err(inconsistent(
                    object.member_path("document"),
                    format!("{code} always concerns the same document"),
                ));
            }
            ResultDiagnosticKind::LockBinding {
                document,
                path: object.str("path")?.to_owned(),
                platform,
                cause,
            }
        }
    };
    Ok(ResultDiagnostic {
        code,
        severity,
        message,
        instruction,
        kind,
    })
}

#[derive(Clone, Copy)]
enum PlanSourceTag {
    Repository,
    Recipe,
    BuiltIn,
    External,
}

fn plan(node: Node<'_>) -> Result<Plan> {
    let plan = node.object()?;
    Plan {
        implementation: plan.req("implementation", model::token(ImplementationId::parse))?,
        deployment: plan.req("deployment", model::token(DeploymentId::parse))?,
        platform: plan.req("platform", model::platform)?,
        recipe: plan.req("recipe", model::recipe_ref)?,
        metadata_refresh: plan.case(
            "metadataRefresh",
            &[
                ("required", MetadataRefresh::Required),
                ("not-required", MetadataRefresh::NotRequired),
            ],
        )?,
        components: plan.req("components", |node| node.array(plan_component))?,
        lock: plan.req("lock", |node| {
            crate::lock::read_lock_value(node.value()).map_err(|mut refusal| {
                refusal.path = if refusal.path.is_empty() {
                    node.path().to_owned()
                } else {
                    join(node.path(), &refusal.path)
                };
                refusal
            })
        })?,
    }
    .checked(plan.path())
}

impl Plan {
    /// The plan installs the current platform's closure of `lock`, from the
    /// recipe's one repository, and nothing else.
    fn checked(self, path: &str) -> Result<Self> {
        let at = |member: &str| join(path, member);
        if self.lock.recipe() != &self.recipe {
            return Err(inconsistent(
                at("lock.recipe"),
                "the lock binds the plan's recipe",
            ));
        }
        let host = self.lock.host();
        if host.implementation != self.implementation || host.deployment != self.deployment {
            return Err(inconsistent(
                at("lock.host"),
                "the lock's host is the plan's implementation and deployment",
            ));
        }
        let closure = self.lock.platforms().get(&self.platform).ok_or_else(|| {
            inconsistent(at("lock.platforms"), "the lock records the plan's platform")
        })?;
        let mut hosts = 0;
        let mut providers = 0;
        for (position, component) in self.components.iter().enumerate() {
            let component_path = index(&at("components"), position);
            let source_path = join(&component_path, "source");
            let target = match &component.source {
                PlanSource::RepositoryTarget {
                    repository_id,
                    target,
                }
                | PlanSource::RecipeDigest {
                    repository_id,
                    target,
                } => {
                    // One repository per binding check.
                    if repository_id != &self.recipe.repository_id {
                        return Err(inconsistent(
                            join(&source_path, "repositoryId"),
                            "a plan acquires from the recipe's repository",
                        ));
                    }
                    Some(target)
                }
                PlanSource::BuiltIn | PlanSource::ExternalOwner => None,
            };
            match &component.component {
                ComponentRef::Host {
                    implementation,
                    deployment,
                } => {
                    hosts += 1;
                    if implementation != &host.implementation
                        || deployment != &host.deployment
                        || component.version != host.version
                    {
                        return Err(inconsistent(
                            component_path,
                            "the host component names the lock's host implementation, deployment and release",
                        ));
                    }
                    // A host release is authenticated by its own TUF target,
                    // or installed by an external owner.
                    if !matches!(
                        component.source,
                        PlanSource::RepositoryTarget { .. } | PlanSource::ExternalOwner
                    ) {
                        return Err(inconsistent(
                            source_path,
                            "a host component's source is repository-target or external-owner",
                        ));
                    }
                    if target.is_some_and(|target| target != closure.host()) {
                        return Err(inconsistent(
                            join(&source_path, "target"),
                            "the host component installs the lock's host artifact",
                        ));
                    }
                }
                ComponentRef::Provider(operation) => {
                    providers += 1;
                    let locked = closure
                        .providers()
                        .iter()
                        .find(|provider| provider.operation() == operation)
                        .ok_or_else(|| {
                            inconsistent(
                                join(&component_path, "component"),
                                "the lock's closure has no provider for this operation",
                            )
                        })?;
                    let same = Some(locked.extension_id()) == component.extension_id.as_ref()
                        && locked.version() == &component.version
                        && Some(locked.delivery().kind()) == component.delivery;
                    if !same {
                        return Err(inconsistent(
                            component_path,
                            "a provider component is the lock's provider for its operation",
                        ));
                    }
                    let artifact = match locked.delivery() {
                        LockedDelivery::BuiltIn { .. } => None,
                        LockedDelivery::Process { artifact, .. }
                        | LockedDelivery::Wasm { artifact, .. } => Some(artifact),
                        LockedDelivery::DotnetTool { package, .. } => Some(package),
                    };
                    // A built-in comes with the host; an external provider's
                    // bytes are bound by the recipe digest, or installed by an
                    // external owner.
                    let consistent = match (&component.source, artifact) {
                        (PlanSource::BuiltIn, None) => true,
                        (PlanSource::ExternalOwner, Some(_)) => true,
                        (PlanSource::RecipeDigest { .. }, Some(artifact)) => {
                            target == Some(artifact)
                        }
                        _ => false,
                    };
                    if !consistent {
                        return Err(inconsistent(
                            source_path,
                            "a provider component's source is its locked artifact, or built-in for a built-in",
                        ));
                    }
                }
            }
        }
        if hosts != 1 || providers != closure.providers().len() {
            return Err(inconsistent(
                at("components"),
                "a plan has one host component and one component per locked provider",
            ));
        }
        Ok(self)
    }
}

fn plan_component(node: Node<'_>) -> Result<PlanComponent> {
    let object = node.object()?;
    let component = object.req("component", component)?;
    let delivery = object.opt("delivery", |node| node.case(DeliveryKind::CASES))?;
    if matches!(component, ComponentRef::Provider(_)) != delivery.is_some() {
        return Err(inconsistent(
            object.member_path("delivery"),
            "a provider component names its delivery and a host component does not",
        ));
    }
    let extension_id = object.opt("extensionId", model::extension_id)?;
    if matches!(component, ComponentRef::Provider(_)) != extension_id.is_some() {
        return Err(inconsistent(
            object.member_path("extensionId"),
            "a provider component names its extensionId and a host component does not",
        ));
    }
    let source = object.req("source", |node| {
        let source = node.object()?;
        match source.case(
            "kind",
            &[
                ("repository-target", PlanSourceTag::Repository),
                ("recipe-digest", PlanSourceTag::Recipe),
                ("built-in", PlanSourceTag::BuiltIn),
                ("external-owner", PlanSourceTag::External),
            ],
        )? {
            PlanSourceTag::Repository => Ok(PlanSource::RepositoryTarget {
                repository_id: source.req("repositoryId", model::sha256)?,
                target: model::digest_pair(&source, "target", "sha256")?,
            }),
            PlanSourceTag::Recipe => Ok(PlanSource::RecipeDigest {
                repository_id: source.req("repositoryId", model::sha256)?,
                target: model::digest_pair(&source, "target", "sha256")?,
            }),
            PlanSourceTag::BuiltIn => Ok(PlanSource::BuiltIn),
            PlanSourceTag::External => Ok(PlanSource::ExternalOwner),
        }
    })?;
    let probe_path = object.member_path("probe");
    let probe = object.case(
        "probe",
        &[
            ("none", Probe::None),
            ("in-host", Probe::InHost),
            ("process-with-user-rights", Probe::ProcessWithUserRights),
        ],
    )?;
    // Setup's readiness runs the staged host, and installation and readiness
    // run every process and .NET tool guest, all with the user's rights. A
    // built-in or WASM provider runs inside the host.
    let expected = match (&component, delivery) {
        (ComponentRef::Host { .. }, _)
        | (_, Some(DeliveryKind::Process | DeliveryKind::DotnetTool)) => {
            Probe::ProcessWithUserRights
        }
        _ => Probe::InHost,
    };
    if probe != expected {
        return Err(inconsistent(
            probe_path,
            "the probe says how setup runs this component: the host and process or .NET tool guests with the user's rights, built-in and WASM providers inside the host",
        ));
    }
    let prerequisites_path = object.member_path("prerequisites");
    // Every plan component lists its prerequisites, possibly none, already
    // filtered to the plan's platform: a plan prerequisite names no platforms.
    let prerequisites = object.req("prerequisites", |node| node.array(model::prerequisite))?;
    for (position, prerequisite) in prerequisites.iter().enumerate() {
        if matches!(prerequisite, Prerequisite::Native { platforms, .. } if !platforms.is_empty()) {
            return Err(inconsistent(
                join(&index(&prerequisites_path, position), "platforms"),
                "a plan lists only the prerequisites of its own platform, without platforms",
            ));
        }
    }
    Ok(PlanComponent {
        component,
        version: object.req("version", model::version)?,
        extension_id,
        delivery,
        source,
        download_bytes: object.req("downloadBytes", |node| node.u64())?,
        installed_bytes: object.req("installedBytes", |node| node.u64())?,
        update_owner: object.req("updateOwner", ownership)?,
        prerequisites,
        probe,
    })
}
