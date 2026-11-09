//! Stable diagnostics for reading and binding toolchain documents.

use std::fmt;

/// A stable diagnostic code. The spelling is part of the contract: other
/// implementations report the same code for the same fixture.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Code {
    /// The bytes are not the document's syntax, or a required member is absent
    /// or has the wrong JSON type.
    InvalidDocument,
    /// `schemaVersion` names a version this reader does not list.
    UnsupportedContractVersion,
    /// `critical` names a member path this reader does not understand.
    UnsupportedCriticalMember,
    /// A tagged member carries a case this reader does not know.
    UnsupportedCase,
    /// A scalar fails its validated type (digest, identifier, version, platform).
    InvalidValue,
    /// A portable document carries an absolute, rooted or traversing path.
    NonPortablePath,
    /// A document carries a credential-shaped member or a URL with credentials.
    CredentialInDocument,
    /// Members are individually valid but contradict each other.
    InconsistentDocument,
    /// The lock's request digest differs from the SHA-256 of the request bytes.
    RequestChanged,
    /// Frozen restore asked for a platform the lock does not record.
    PlatformNotLocked,
    /// The receipt's lock digest differs from the SHA-256 of the lock bytes.
    LockChanged,
    /// A receipt identity differs from the locked identity for its platform.
    ReceiptLockMismatch,
    /// No artifact matches the requested implementation, deployment, platform,
    /// ABI or protocol; nothing is substituted.
    UnsupportedArtifact,
}

impl Code {
    /// The stable snake_case spelling.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::InvalidDocument => "invalid_document",
            Self::UnsupportedContractVersion => "unsupported_contract_version",
            Self::UnsupportedCriticalMember => "unsupported_critical_member",
            Self::UnsupportedCase => "unsupported_case",
            Self::InvalidValue => "invalid_value",
            Self::NonPortablePath => "non_portable_path",
            Self::CredentialInDocument => "credential_in_document",
            Self::InconsistentDocument => "inconsistent_document",
            Self::RequestChanged => "request_changed",
            Self::PlatformNotLocked => "platform_not_locked",
            Self::LockChanged => "lock_changed",
            Self::ReceiptLockMismatch => "receipt_lock_mismatch",
            Self::UnsupportedArtifact => "unsupported_artifact",
        }
    }
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
/// the document itself.
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
