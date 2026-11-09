//! The manager JSON result: the one document `morphirup --json` writes to
//! standard output. Progress goes to standard error.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::envelope;
use crate::ids::{DeploymentId, GenerationId, ImplementationId, Sha256, TargetPath};
use crate::lock::{LockedHost, locked_host};
use crate::model::{self, DELIVERY_CASES, DeliveryKind, Operation, Prerequisite, RecipeRef};
use crate::platform::PlatformId;
use crate::reader::{Node, Obj, inconsistent};
use crate::receipt::{CheckKind, Ownership, Readiness, refuse_credentials};
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

/// Tool release metadata v1 stable diagnostic codes a trust failure reports.
pub const TRUST_CODES: &[&str] = &[
    "metadata_signature_invalid",
    "metadata_expired",
    "metadata_rollback",
    "metadata_link_mismatch",
    "metadata_root_rotation_invalid",
    "target_length_mismatch",
    "target_digest_mismatch",
    "release_descriptor_mismatch",
    "release_revoked",
    "no_compatible_release",
    "offline_metadata_unavailable",
];

/// The manager command that produced a result.
pub const COMMANDS: &[&str] = &[
    "setup",
    "restore",
    "update",
    "show",
    "doctor",
    "list",
    "default",
    "rollback",
    "repair",
    "remove",
    "self-update",
    "env",
];

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
        path: String,
    },
    /// The user default.
    UserDefault,
}

/// One result diagnostic. The cases are the failure categories the manager
/// distinguishes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ResultDiagnosticKind {
    /// No artifact matches; alternatives are listed, never substituted.
    UnsupportedArtifact {
        /// Component.
        component: ComponentRef,
        /// Requested platform.
        platform: PlatformId,
    },
    /// A declared runtime, SDK or native prerequisite is absent.
    MissingPrerequisite {
        /// Component.
        component: ComponentRef,
        /// Prerequisite.
        prerequisite: Prerequisite,
    },
    /// Repository authentication failed, with the v1 stable code.
    TrustFailure {
        /// Stable code from tool release metadata v1.
        code: String,
        /// Repository identity.
        repository_id: Sha256,
        /// Mirror, without credentials.
        mirror: Option<String>,
    },
    /// Offline work needs content absent from the verified store.
    OfflineContentUnavailable {
        /// Component.
        component: ComponentRef,
        /// Missing target.
        target: TargetPath,
        /// Its digest.
        sha256: Sha256,
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
        document: String,
        /// Reader code.
        code: String,
        /// Member path.
        path: String,
    },
    /// The selected generation is not installed; nothing falls back.
    SelectionUnavailable {
        /// Selection source.
        source: SelectionSource,
    },
}

/// A result diagnostic.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResultDiagnostic {
    /// Severity.
    pub severity: Severity,
    /// Human-readable message.
    pub message: String,
    /// Category and its members.
    pub kind: ResultDiagnosticKind,
}

/// A parsed manager result.
#[derive(Debug, Clone, PartialEq)]
pub struct ManagerResult {
    /// Command.
    pub command: &'static str,
    /// Outcome.
    pub outcome: Outcome,
    /// A setup or update plan and its digest.
    pub plan: Option<(Value, Sha256)>,
    /// The explained selection, for `show`.
    pub selection: Option<(SelectionSource, GenerationId, PlatformId, LockedHost)>,
    /// Diagnostics.
    pub diagnostics: Vec<ResultDiagnostic>,
}

/// SHA-256 of the TUF canonical JSON of a value: keys sorted, no insignificant
/// whitespace, no floating-point numbers. `planSha256` is this digest of `plan`.
pub fn canonical_sha256(value: &Value) -> std::result::Result<Sha256, String> {
    use serde::Serialize;
    let mut bytes = Vec::new();
    let mut serializer =
        serde_json::Serializer::with_formatter(&mut bytes, olpc_cjson::CanonicalFormatter::new());
    value
        .serialize(&mut serializer)
        .map_err(|error| format!("not canonical JSON: {error}"))?;
    Ok(Sha256::of_bytes(&bytes))
}

/// Read a result from its exact bytes.
pub fn read_result(bytes: &[u8]) -> Result<ManagerResult> {
    let value: Value = serde_json::from_slice(bytes).map_err(|error| {
        Diagnostic::new(Code::InvalidDocument, "", format!("not JSON: {error}"))
    })?;
    envelope::check(&value, UNDERSTOOD_PATHS)?;
    refuse_credentials(&value, "")?;
    let root = Node::root(&value).object()?;
    let command = root.tag("command", COMMANDS)?;
    let outcome = match root.tag("outcome", &["planned", "succeeded", "failed"])? {
        "planned" => Outcome::Planned,
        "succeeded" => Outcome::Succeeded,
        _ => Outcome::Failed,
    };
    let plan = root.opt("plan", |node| {
        plan(node)?;
        let digest = root.req("planSha256", model::sha256)?;
        let actual = canonical_sha256(node.value())
            .map_err(|message| Diagnostic::new(Code::InvalidDocument, node.path(), message))?;
        if digest != actual {
            return Err(inconsistent(
                "planSha256",
                format!("planSha256 is {digest}, but the canonical plan hashes to {actual}"),
            ));
        }
        Ok((node.value().clone(), digest))
    })?;
    let selection = root.opt("selection", |node| {
        let selection = node.object()?;
        Ok((
            selection.req("source", selection_source)?,
            selection.req("generationId", model::token(GenerationId::parse))?,
            selection.req("platform", model::platform)?,
            selection.req("host", locked_host)?,
        ))
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

fn component(node: Node<'_>) -> Result<ComponentRef> {
    let object = node.object()?;
    match object.tag("role", &["host", "provider"])? {
        "host" => Ok(ComponentRef::Host {
            implementation: object.req("implementation", model::token(ImplementationId::parse))?,
            deployment: object.req("deployment", model::token(DeploymentId::parse))?,
        }),
        _ => Ok(ComponentRef::Provider(model::operation(&object)?)),
    }
}

fn ownership(node: Node<'_>) -> Result<Ownership> {
    let object = node.object()?;
    match object.tag(
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
            package_id: object.req("packageId", model::token(crate::ids::PackageId::parse))?,
            scope: match object.tag("scope", &["global", "tool-path", "local-manifest"])? {
                "global" => crate::receipt::DotnetToolScope::Global,
                "tool-path" => crate::receipt::DotnetToolScope::ToolPath,
                _ => crate::receipt::DotnetToolScope::LocalManifest,
            },
        }),
        _ => Ok(Ownership::SystemPackage {
            manager: object.req("manager", model::token(crate::ids::PackageManagerId::parse))?,
        }),
    }
}

fn absolute_path(node: Node<'_>) -> Result<String> {
    node.parse(Code::InvalidValue, |text| {
        let bytes = text.as_bytes();
        let windows = bytes.len() > 3
            && bytes[0].is_ascii_alphabetic()
            && bytes[1] == b':'
            && matches!(bytes[2], b'\\' | b'/');
        if windows || text.starts_with('/') || text.starts_with("\\\\") {
            Ok(text.to_owned())
        } else {
            Err(format!("'{text}' is not an absolute path"))
        }
    })
}

fn selection_source(node: Node<'_>) -> Result<SelectionSource> {
    let object = node.object()?;
    match object.tag("kind", &["cli", "environment", "project", "user-default"])? {
        "cli" => Ok(SelectionSource::Cli),
        "environment" => Ok(SelectionSource::Environment),
        "project" => Ok(SelectionSource::Project {
            path: object.req("path", absolute_path)?,
        }),
        _ => Ok(SelectionSource::UserDefault),
    }
}

/// A mirror is reported only without credentials: no user information, no
/// query and no fragment.
fn mirror(node: Node<'_>) -> Result<String> {
    let text = node.str()?;
    let url = url::Url::parse(text).map_err(|error| {
        Diagnostic::new(
            Code::InvalidValue,
            node.path(),
            format!("not a URL: {error}"),
        )
    })?;
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

fn argv(object: &Obj<'_>) -> Result<()> {
    object.opt("instruction", |node| {
        let words = node.array(|item| item.str().map(str::to_owned))?;
        if words.is_empty() {
            return Err(inconsistent(
                node.path(),
                "an instruction is a non-empty argument vector",
            ));
        }
        Ok(())
    })?;
    Ok(())
}

fn diagnostic(node: Node<'_>) -> Result<ResultDiagnostic> {
    let object = node.object()?;
    let kind_tag = object.tag(
        "kind",
        &[
            "unsupported-artifact",
            "missing-prerequisite",
            "trust-failure",
            "offline-content-unavailable",
            "ownership-conflict",
            "readiness-failed",
            "unsupported-contract",
            "selection-unavailable",
        ],
    )?;
    let severity = match object.tag("severity", &["error", "warning"])? {
        "error" => Severity::Error,
        _ => Severity::Warning,
    };
    let message = object.req("message", model::non_empty_string)?;
    argv(&object)?;
    let alternatives = || -> Result<()> {
        object.opt("alternatives", |node| {
            node.array(|item| {
                let alternative = item.object()?;
                alternative.opt("implementation", model::token(ImplementationId::parse))?;
                alternative.opt("deployment", model::token(DeploymentId::parse))?;
                alternative.opt("platform", model::platform)?;
                Ok(())
            })
        })?;
        Ok(())
    };
    let kind = match kind_tag {
        "unsupported-artifact" => {
            alternatives()?;
            ResultDiagnosticKind::UnsupportedArtifact {
                component: object.req("component", component)?,
                platform: object.req("platform", model::platform)?,
            }
        }
        "missing-prerequisite" => {
            alternatives()?;
            ResultDiagnosticKind::MissingPrerequisite {
                component: object.req("component", component)?,
                prerequisite: object.req("prerequisite", model::prerequisite)?,
            }
        }
        "trust-failure" => {
            let code = object.tag("code", TRUST_CODES)?.to_owned();
            object.opt("role", |node| {
                let role = node.str()?;
                if ["root", "timestamp", "snapshot", "targets"].contains(&role) {
                    Ok(())
                } else {
                    Err(Diagnostic::new(
                        Code::UnsupportedCase,
                        node.path(),
                        format!("'{role}' is not a TUF role"),
                    ))
                }
            })?;
            object.opt("target", model::target_path)?;
            ResultDiagnosticKind::TrustFailure {
                code,
                repository_id: object.req("repositoryId", model::sha256)?,
                mirror: object.opt("mirror", mirror)?,
            }
        }
        "offline-content-unavailable" => ResultDiagnosticKind::OfflineContentUnavailable {
            component: object.req("component", component)?,
            target: object.req("target", model::target_path)?,
            sha256: object.req("sha256", model::sha256)?,
        },
        "ownership-conflict" => ResultDiagnosticKind::OwnershipConflict {
            component: object.req("component", component)?,
            ownership: object.req("ownership", ownership)?,
        },
        "readiness-failed" => {
            let check = CheckKind::from_tag(object.tag("check", CheckKind::CASES)?);
            let readiness_path = object.member_path("readiness");
            let readiness = object.req("readiness", |node| {
                let tag = node.str()?;
                Readiness::CASES
                    .iter()
                    .find(|case| **case == tag)
                    .map(|case| Readiness::from_tag(case))
                    .ok_or_else(|| {
                        Diagnostic::new(
                            Code::UnsupportedCase,
                            node.path(),
                            format!("'{tag}' is not a readiness state"),
                        )
                    })
            })?;
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
        "unsupported-contract" => ResultDiagnosticKind::UnsupportedContract {
            document: object
                .tag(
                    "document",
                    &["request", "lock", "recipe", "receipt", "result"],
                )?
                .to_owned(),
            code: object
                .tag(
                    "code",
                    &[
                        "invalid_document",
                        "unsupported_contract_version",
                        "unsupported_critical_member",
                        "unsupported_case",
                        "invalid_value",
                        "non_portable_path",
                        "credential_in_document",
                        "inconsistent_document",
                    ],
                )?
                .to_owned(),
            path: object.str("path")?.to_owned(),
        },
        _ => ResultDiagnosticKind::SelectionUnavailable {
            source: object.req("source", selection_source)?,
        },
    };
    Ok(ResultDiagnostic {
        severity,
        message,
        kind,
    })
}

fn plan(node: Node<'_>) -> Result<()> {
    let plan = node.object()?;
    plan.req("implementation", model::token(ImplementationId::parse))?;
    plan.req("deployment", model::token(DeploymentId::parse))?;
    plan.req("platform", model::platform)?;
    plan.req("recipe", |node| {
        model::recipe_ref(node).map(|_: RecipeRef| ())
    })?;
    plan.tag("metadataRefresh", &["required", "not-required"])?;
    plan.req("components", |node| {
        node.array(|item| {
            let component_object = item.object()?;
            let target = component_object.req("component", component)?;
            component_object.req("version", model::version)?;
            component_object.opt("extensionId", model::extension_id)?;
            let delivery = component_object
                .opt("delivery", |node| {
                    let tag = node.str()?;
                    DELIVERY_CASES
                        .iter()
                        .find(|case| **case == tag)
                        .map(|case| DeliveryKind::from_tag(case))
                        .ok_or_else(|| {
                            Diagnostic::new(Code::UnsupportedCase, node.path(), format!("'{tag}' is not a delivery"))
                        })
                })?;
            if matches!(target, ComponentRef::Provider(_)) != delivery.is_some() {
                return Err(inconsistent(
                    component_object.member_path("delivery"),
                    "a provider component names its delivery and a host component does not",
                ));
            }
            component_object.req("source", |node| {
                let source = node.object()?;
                match source.tag("kind", &["repository-target", "recipe-digest", "built-in", "external-owner"])? {
                    "repository-target" | "recipe-digest" => {
                        source.req("repositoryId", model::sha256)?;
                        source.req("target", model::target_path)?;
                        source.req("sha256", model::sha256)?;
                    }
                    _ => {}
                }
                Ok(())
            })?;
            component_object.req("downloadBytes", |node| node.u64())?;
            component_object.req("installedBytes", |node| node.u64())?;
            component_object.req("updateOwner", ownership)?;
            model::prerequisites(&component_object)?;
            let probe_path = component_object.member_path("probe");
            let probe = component_object.tag("probe", &["none", "in-host", "process-with-user-rights"])?;
            let runs_a_process = matches!(delivery, Some(DeliveryKind::Process | DeliveryKind::DotnetTool));
            if runs_a_process != (probe == "process-with-user-rights") {
                return Err(inconsistent(
                    probe_path,
                    "a process probe runs acquired code with the user's rights, and the plan says so",
                ));
            }
            Ok(())
        })
    })?;
    Ok(())
}
