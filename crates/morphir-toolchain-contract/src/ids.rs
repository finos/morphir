//! Validated scalar types used by the toolchain contracts.
//!
//! Identities, channels, digests and target paths reuse the
//! `morphir-distribution` types already used by tool release metadata v1 and
//! extension acquisition. The types defined here are the ones those contracts
//! do not have.

use crate::diagnostic::Code;
use morphir_distribution::{RelativeArtifactPath, Sha256Digest};
use semver::{Comparator, Version, VersionReq};
use std::fmt;

fn portable_token(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
        && value.as_bytes()[0].is_ascii_lowercase()
        && value.as_bytes()[value.len() - 1].is_ascii_alphanumeric()
}

macro_rules! token_type {
    ($(#[$meta:meta])* $name:ident, $what:literal) => {
        $(#[$meta])*
        #[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
        pub struct $name(String);

        impl $name {
            /// Parse a lowercase portable token.
            pub fn parse(value: &str) -> Result<Self, String> {
                if portable_token(value) {
                    Ok(Self(value.to_owned()))
                } else {
                    Err(format!(
                        concat!("'{}' is not a valid ", $what, "; expected a lowercase portable token"),
                        value
                    ))
                }
            }

            /// Return the token.
            pub fn as_str(&self) -> &str {
                &self.0
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str(&self.0)
            }
        }
    };
}

token_type!(
    /// A host implementation such as `dotnet` or `moonbit`.
    ImplementationId,
    "implementation id"
);
token_type!(
    /// A deployment offering such as `native-aot` or `dotnet-tool`.
    DeploymentId,
    "deployment id"
);
token_type!(
    /// A toolset preset such as `fsharp`.
    PresetId,
    "preset id"
);
token_type!(
    /// A source language or generation target such as `fsharp`.
    LanguageId,
    "language or target id"
);
token_type!(
    /// A named WASM ABI such as `morphir-bytes-v1` or `extism-kernel-v1`.
    WasmAbi,
    "WASM ABI"
);
token_type!(
    /// A model profile or codec token such as `morphir-ir` or `morphir-json`.
    ModelToken,
    "model profile or codec"
);
token_type!(
    /// A command exposed by a .NET tool package, such as `dotnet-morphir`.
    CommandName,
    "command name"
);
token_type!(
    /// A local opaque generation id. It is not a release version.
    GenerationId,
    "generation id"
);
token_type!(
    /// A fixed readiness workflow such as `fsharp-compile-generate`.
    WorkflowId,
    "workflow id"
);
token_type!(
    /// A system package manager such as `winget` or `brew`.
    PackageManagerId,
    "package manager id"
);

/// A provider identity: a portable token (`morphir-fsharp-backend`) or a
/// dotted name of portable tokens (`morphir.fsharp`,
/// `org.finos.morphir.fsharp-frontend`).
///
/// This is the identity the host registry and the MEP handshake use. It is
/// deliberately not `morphir_distribution::ExtensionId`, whose portable-token
/// grammar names store entries and cannot spell the existing dotted ids.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ExtensionIdentity(String);

impl ExtensionIdentity {
    /// Parse a provider identity.
    pub fn parse(value: &str) -> Result<Self, String> {
        if value.len() <= 238 && value.split('.').all(portable_token) {
            Ok(Self(value.to_owned()))
        } else {
            Err(format!(
                "'{value}' is not a provider identity; expected lowercase portable tokens joined by '.'"
            ))
        }
    }

    /// Return the identity.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for ExtensionIdentity {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

/// A NuGet package id such as `Morphir.Tool`.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct PackageId(String);

impl PackageId {
    /// Parse a NuGet package id.
    pub fn parse(value: &str) -> Result<Self, String> {
        let valid = !value.is_empty()
            && value.len() <= 100
            && value.split(['.', '-']).all(|segment| {
                !segment.is_empty()
                    && segment
                        .bytes()
                        .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
            });
        if valid {
            Ok(Self(value.to_owned()))
        } else {
            Err(format!("'{value}' is not a NuGet package id"))
        }
    }

    /// Return the package id.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// A lowercase SHA-256 digest of exact bytes.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Sha256(Sha256Digest);

impl Sha256 {
    /// Parse exactly 64 lowercase hexadecimal digits.
    pub fn parse(value: &str) -> Result<Self, String> {
        let canonical = value.len() == 64
            && value
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte));
        if !canonical {
            return Err(format!(
                "'{value}' is not a SHA-256 digest; expected 64 lowercase hexadecimal digits"
            ));
        }
        Sha256Digest::parse(value)
            .map(Self)
            .map_err(|error| error.to_string())
    }

    /// Hash exact bytes.
    pub fn of_bytes(bytes: &[u8]) -> Self {
        Self(Sha256Digest::of_bytes(bytes))
    }

    pub(crate) fn of_digest(digest: Sha256Digest) -> Self {
        Self(digest)
    }

    /// Return the `morphir-distribution` digest.
    pub fn digest(&self) -> &Sha256Digest {
        &self.0
    }
}

impl fmt::Display for Sha256 {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}

/// A relative TUF target path, validated with the v1 tool profile rules.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TargetPath(RelativeArtifactPath);

impl TargetPath {
    /// Parse a forward-slash relative target path. Absolute, rooted, drive,
    /// backslash and `.`/`..` paths are refused.
    pub fn parse(value: &str) -> Result<Self, String> {
        let bounded = value.len() <= 512
            && value.encode_utf16().count() <= 240
            && !value.contains(['\u{2028}', '\u{2029}']);
        // Target paths are object keys of signed targets metadata, and the
        // canonical encoder normalizes keys to NFC. A path that is not already
        // NFC would therefore be signed under another spelling.
        if !unicode_normalization::is_nfc(value) {
            return Err(format!(
                "'{value}' is not in Unicode Normalization Form C; a target path must be NFC so canonical encoding never changes it"
            ));
        }
        match RelativeArtifactPath::parse(value) {
            Ok(path) if bounded => Ok(Self(path)),
            _ => Err(format!(
                "'{value}' is not a portable target path; expected a relative forward-slash path"
            )),
        }
    }

    /// Return the target path.
    pub fn as_str(&self) -> &str {
        self.0.as_str()
    }

    /// Return the final path segment.
    pub fn file_name(&self) -> &str {
        self.as_str().rsplit('/').next().unwrap_or_default()
    }
}

impl fmt::Display for TargetPath {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

/// An authenticated target path and the SHA-256 of its exact bytes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TargetDigest {
    /// Relative target path.
    pub target: TargetPath,
    /// SHA-256 of the exact target bytes.
    pub sha256: Sha256,
}

/// Parse an exact SemVer version in canonical spelling.
pub fn exact_version(value: &str) -> Result<Version, String> {
    match Version::parse(value) {
        Ok(version) if version.to_string() == value => Ok(version),
        Ok(_) => Err(format!("'{value}' is not in canonical SemVer spelling")),
        Err(error) => Err(format!("'{value}' is not a SemVer version: {error}")),
    }
}

/// Parse one SemVer comparator such as `>=10.0.0`: exactly one of `=`, `>`,
/// `>=`, `<` or `<=`, then a complete version in canonical SemVer spelling,
/// with no space. Ranges that cross languages are lists of single
/// comparators, so `^`, `~`, wildcards, partial versions and combined ranges
/// are refused: Rust, TypeScript and .NET give them different meanings.
pub fn comparator(value: &str) -> Result<Comparator, String> {
    if value.contains(',') {
        return Err(format!(
            "'{value}' is a combined range; write a list of single comparators"
        ));
    }
    let version = [">=", "<=", "=", ">", "<"]
        .iter()
        .find_map(|operator| value.strip_prefix(operator))
        .ok_or_else(|| format!("'{value}' does not start with one of =, >, >=, <, <="))?;
    exact_version(version)
        .map_err(|message| format!("'{value}' does not name a complete version: {message}"))?;
    Comparator::parse(value)
        .map_err(|error| format!("'{value}' is not a SemVer comparator: {error}"))
}

/// A MEP protocol version on the supported 0.2 line: every prerelease of
/// `0.2.0` and every final `0.2.x`, in canonical SemVer spelling and without
/// build metadata. MEP `0.1` is not supported. Admitting every prerelease of
/// `0.2.0` is a maintainer exception, for MEP only, to the rule that a
/// prerelease matches only exactly.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ProtocolVersion(Version);

impl ProtocolVersion {
    /// The supported set as single comparators. They mean that set under the
    /// prerelease rule of the `semver` crate and `@std/semver`: a prerelease
    /// version matches only when a comparator names the same major, minor and
    /// patch with a prerelease. That rule is what keeps `0.2.1-rc.1` out.
    pub const SUPPORTED: [&'static str; 2] = [">=0.2.0-0", "<0.3.0-0"];

    /// Parse a MEP version on the supported 0.2 line. A string that is not a
    /// version in canonical SemVer spelling fails its type and is
    /// `invalid_value`; a version that is not on the line is
    /// `unsupported_case`.
    pub fn parse(value: &str) -> Result<Self, (Code, String)> {
        let version = exact_version(value)
            .map_err(|message| (Code::InvalidValue, format!("MEP version {message}")))?;
        let outside = |detail: String| {
            (
                Code::UnsupportedCase,
                format!(
                    "MEP version '{value}' is not on the supported 0.2 line (every prerelease of 0.2.0 and every final 0.2.x): {detail}"
                ),
            )
        };
        if !version.build.is_empty() {
            return Err(outside("a MEP version carries no build metadata".into()));
        }
        let supported = VersionReq {
            comparators: Self::SUPPORTED
                .iter()
                .map(|text| Comparator::parse(text).expect("the supported comparators parse"))
                .collect(),
        };
        if !supported.matches(&version) {
            return Err(outside(format!(
                "it does not satisfy {}",
                Self::SUPPORTED.join(" and ")
            )));
        }
        Ok(Self(version))
    }

    /// The version.
    pub fn version(&self) -> &Version {
        &self.0
    }
}

impl fmt::Display for ProtocolVersion {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}

/// The path syntax an absolute local path must follow.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PathStyle {
    /// `X:\…`, `X:/…` or a UNC path `\\server\share…`.
    Windows,
    /// `/…`.
    Posix,
    /// Either syntax, for a document that does not name its platform.
    Either,
}

/// An absolute local path, such as a launch program or a project request.
///
/// A Windows path is a drive letter, `:`, a `\` or `/` and at least one more
/// character, or a UNC path `\\` followed by at least one more character. A
/// POSIX path is `/` followed by at least one more character. No segment,
/// split on `\` and `/`, is `.` or `..`, and the path has no NUL.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct AbsolutePath(String);

impl AbsolutePath {
    /// Parse an absolute path in `style`.
    pub fn parse(value: &str, style: PathStyle) -> Result<Self, String> {
        let bytes = value.as_bytes();
        let windows = (bytes.len() > 3
            && bytes[0].is_ascii_alphabetic()
            && bytes[1] == b':'
            && matches!(bytes[2], b'\\' | b'/'))
            || (bytes.len() > 2 && value.starts_with("\\\\"));
        let posix = bytes.len() > 1 && bytes[0] == b'/';
        let rooted = match style {
            PathStyle::Windows => windows,
            PathStyle::Posix => posix,
            PathStyle::Either => windows || posix,
        };
        let traverses = value
            .split(['\\', '/'])
            .any(|segment| segment == "." || segment == "..");
        if rooted && !traverses && !value.contains('\0') {
            Ok(Self(value.to_owned()))
        } else {
            Err(format!(
                "'{value}' is not an absolute {} path without . or .. segments",
                match style {
                    PathStyle::Windows => "Windows",
                    PathStyle::Posix => "POSIX",
                    PathStyle::Either => "local",
                }
            ))
        }
    }

    /// Return the path.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}
