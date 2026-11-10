//! Stable diagnostic codes and the result diagnostic kind each belongs to.

use std::fmt;

/// The kind of manager result diagnostic that reports a code. Every stable
/// code has exactly one kind, so a result can report any refusal.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DiagnosticKind {
    /// No artifact matches; nothing is substituted.
    UnsupportedArtifact,
    /// A declared runtime, SDK or native prerequisite is absent.
    MissingPrerequisite,
    /// Repository authentication or a binding to authenticated content failed.
    TrustFailure,
    /// Offline work needs content absent from the verified store.
    OfflineContentUnavailable,
    /// Another owner manages the installation.
    OwnershipConflict,
    /// A readiness check failed.
    ReadinessFailed,
    /// A document was refused by its contract reader.
    UnsupportedContract,
    /// The selected generation is not installed.
    SelectionUnavailable,
    /// The request, lock, receipt and recipe do not bind each other.
    LockBinding,
}

impl DiagnosticKind {
    pub(crate) const CASES: &'static [(&'static str, Self)] = &[
        ("unsupported-artifact", Self::UnsupportedArtifact),
        ("missing-prerequisite", Self::MissingPrerequisite),
        ("trust-failure", Self::TrustFailure),
        (
            "offline-content-unavailable",
            Self::OfflineContentUnavailable,
        ),
        ("ownership-conflict", Self::OwnershipConflict),
        ("readiness-failed", Self::ReadinessFailed),
        ("unsupported-contract", Self::UnsupportedContract),
        ("selection-unavailable", Self::SelectionUnavailable),
        ("lock-binding", Self::LockBinding),
    ];

    /// The `kind` spelling.
    pub fn as_str(self) -> &'static str {
        Self::CASES
            .iter()
            .find(|(_, kind)| *kind == self)
            .map(|(name, _)| *name)
            .unwrap_or_default()
    }
}

macro_rules! codes {
    ($( $(#[$meta:meta])* $variant:ident = $spelling:literal => $kind:ident, )*) => {
        /// A stable diagnostic code. The spelling is part of the contract:
        /// every implementation reports the same code for the same fixture.
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
        pub enum Code {
            $( $(#[$meta])* $variant, )*
        }

        impl Code {
            /// Every code, in table order.
            pub const ALL: &'static [Code] = &[ $( Code::$variant, )* ];

            /// The stable snake_case spelling.
            pub fn as_str(self) -> &'static str {
                match self { $( Code::$variant => $spelling, )* }
            }

            /// The result diagnostic kind that reports this code.
            pub fn kind(self) -> DiagnosticKind {
                match self { $( Code::$variant => DiagnosticKind::$kind, )* }
            }

            /// Parse a stable spelling.
            pub fn parse(spelling: &str) -> Option<Code> {
                match spelling { $( $spelling => Some(Code::$variant), )* _ => None }
            }
        }
    };
}

codes! {
    /// Not the document's syntax, or a required member is absent or has the wrong JSON type.
    InvalidDocument = "invalid_document" => UnsupportedContract,
    /// `schemaVersion` names a version this reader does not list.
    UnsupportedContractVersion = "unsupported_contract_version" => UnsupportedContract,
    /// `critical` names a member path this reader does not understand.
    UnsupportedCriticalMember = "unsupported_critical_member" => UnsupportedContract,
    /// A tagged member carries a case this reader does not know.
    UnsupportedCase = "unsupported_case" => UnsupportedContract,
    /// A scalar fails its validated type.
    InvalidValue = "invalid_value" => UnsupportedContract,
    /// A target path is absolute, rooted, traversing or not portable.
    NonPortablePath = "non_portable_path" => UnsupportedContract,
    /// A credential-shaped member or a URL carrying credentials.
    CredentialInDocument = "credential_in_document" => UnsupportedContract,
    /// Members are individually valid but contradict each other.
    InconsistentDocument = "inconsistent_document" => UnsupportedContract,
    /// A document the command needs, such as the project request or lock,
    /// cannot be read: it is absent or unreadable.
    DocumentUnavailable = "document_unavailable" => UnsupportedContract,
    /// The lock's request digest differs from the SHA-256 of the request bytes.
    RequestChanged = "request_changed" => LockBinding,
    /// Frozen restore needs a platform closure the lock does not record.
    PlatformNotLocked = "platform_not_locked" => LockBinding,
    /// The receipt's lock digest differs from the SHA-256 of the lock bytes.
    LockChanged = "lock_changed" => LockBinding,
    /// A receipt identity differs from the lock's closure for its platform.
    ReceiptLockMismatch = "receipt_lock_mismatch" => LockBinding,
    /// A lock closure is not a resolution the recipe allows.
    LockRecipeMismatch = "lock_recipe_mismatch" => LockBinding,
    /// `--expect-plan` named another digest than the plan the command made.
    PlanChanged = "plan_changed" => LockBinding,
    /// No artifact matches the requested implementation, deployment, release,
    /// platform or protocol; nothing is substituted.
    UnsupportedArtifact = "unsupported_artifact" => UnsupportedArtifact,
    /// The preferred provider needs a WASM ABI the host does not support.
    AbiUnavailable = "abi_unavailable" => UnsupportedArtifact,
    /// Tool release metadata v1: no release matches the selection.
    NoCompatibleRelease = "no_compatible_release" => UnsupportedArtifact,
    /// A declared prerequisite is absent.
    MissingPrerequisite = "missing_prerequisite" => MissingPrerequisite,
    /// Locked content is absent from the verified store while offline.
    OfflineContentUnavailable = "offline_content_unavailable" => OfflineContentUnavailable,
    /// Another owner manages the installation.
    OwnershipConflict = "ownership_conflict" => OwnershipConflict,
    /// A readiness check failed.
    ReadinessFailed = "readiness_failed" => ReadinessFailed,
    /// The selected generation is not installed.
    GenerationNotInstalled = "generation_not_installed" => SelectionUnavailable,
    /// A target is not listed by the authenticated targets metadata.
    TargetNotAuthenticated = "target_not_authenticated" => TrustFailure,
    /// Tool release metadata v1: bytes or a bound length disagree with the target length.
    TargetLengthMismatch = "target_length_mismatch" => TrustFailure,
    /// Tool release metadata v1: bytes or a bound digest disagree with the target digest.
    TargetDigestMismatch = "target_digest_mismatch" => TrustFailure,
    /// Tool release metadata v1: a binding disagrees with the authenticated release or target state.
    ReleaseDescriptorMismatch = "release_descriptor_mismatch" => TrustFailure,
    /// A platform is bound to another platform's artifact.
    ArtifactPlatformMismatch = "artifact_platform_mismatch" => TrustFailure,
    /// A document names a repository identity other than the one the check
    /// runs against: one repository per binding check.
    RepositoryMismatch = "repository_mismatch" => TrustFailure,
    /// Tool release metadata v1: the authenticated state is revoked.
    ReleaseRevoked = "release_revoked" => TrustFailure,
    /// Tool release metadata v1: a metadata signature or threshold check failed.
    MetadataSignatureInvalid = "metadata_signature_invalid" => TrustFailure,
    /// Tool release metadata v1: metadata has expired.
    MetadataExpired = "metadata_expired" => TrustFailure,
    /// Tool release metadata v1: a metadata version went backwards.
    MetadataRollback = "metadata_rollback" => TrustFailure,
    /// Tool release metadata v1: metadata bytes disagree with the role that links them.
    MetadataLinkMismatch = "metadata_link_mismatch" => TrustFailure,
    /// Tool release metadata v1: a root rotation was refused.
    MetadataRootRotationInvalid = "metadata_root_rotation_invalid" => TrustFailure,
    /// Tool release metadata v1: required metadata is unavailable offline.
    OfflineMetadataUnavailable = "offline_metadata_unavailable" => TrustFailure,
    /// The repository could not be read for a reason none of the other codes name.
    RepositoryUnavailable = "repository_unavailable" => TrustFailure,
}

impl fmt::Display for Code {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

/// A refusal with its stable code and the member path it concerns.
///
/// Paths use dotted member names with `[index]` for array elements, for
/// example `platforms.win-x64.providers[0].artifactTarget`. The empty path is
/// the document, or the authenticated target, itself.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diagnostic {
    /// Stable code.
    pub code: Code,
    /// Member path.
    pub path: String,
    /// Human-readable detail. Not stable.
    pub message: String,
}

impl Diagnostic {
    pub(crate) fn new(code: Code, path: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code,
            path: path.into(),
            message: message.into(),
        }
    }
}

impl fmt::Display for Diagnostic {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.path.is_empty() {
            write!(formatter, "{}: {}", self.code, self.message)
        } else {
            write!(
                formatter,
                "{} at {}: {}",
                self.code, self.path, self.message
            )
        }
    }
}

impl std::error::Error for Diagnostic {}

/// Result of reading or checking a toolchain document.
pub type Result<T> = std::result::Result<T, Diagnostic>;
