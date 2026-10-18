use std::collections::BTreeMap;

use base64::{Engine as _, engine::general_purpose::STANDARD};
use morphir_distribution::{RelativeArtifactPath, Sha256Digest};
use morphir_extension_sdk::Artifact;
use serde::{Deserialize, Deserializer, Serialize};
use unicode_casefold::UnicodeCaseFold;
use unicode_normalization::UnicodeNormalization;

pub const PROFILE: &str = "morphir/workbench/artifacts";
pub const CONTRACT_VERSION: &str = "0.1.0-draft.1";
pub const MAX_FILES: usize = 256;
pub const MAX_FILE_BYTES: usize = 16 * 1024 * 1024;
pub const MAX_SET_BYTES: usize = 64 * 1024 * 1024;
pub const MAX_CHUNK_BYTES: usize = 65_536;
pub const MAX_REPLY_BYTES: usize = 128 * 1024;
pub const MAX_GENERATE_REQUEST_BYTES: usize = 1024 * 1024;
pub const MAX_CONTROL_REQUEST_BYTES: usize = 16 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq, thiserror::Error)]
pub enum ArtifactError {
    #[error("Invalid artifact identity.")]
    InvalidIdentity,
    #[error("Invalid artifact byte offset or chunk limit.")]
    InvalidRange,
    #[error("Invalid portable artifact path.")]
    InvalidPath,
    #[error("Artifact paths collide or have a file/directory prefix conflict.")]
    InvalidPathSet,
    #[error("Binary artifact content is not canonical padded standard base64.")]
    InvalidContent,
    #[error("Artifact count exceeds its limit.")]
    FileCount,
    #[error("Artifact size exceeds its limit.")]
    FileSize,
    #[error("Artifact set size exceeds its limit.")]
    SetSize,
    #[error("Artifact reply exceeds its limit.")]
    ReplyLimit,
    #[error("Artifact host capacity is exhausted.")]
    Capacity,
    #[error("An artifact generation is already active.")]
    ActiveGeneration,
    #[error("The artifact generation or artifact is unavailable on this connection.")]
    UnknownHandle,
    #[error("The artifact profile is unavailable or its exact version does not match.")]
    Unavailable,
    #[error("Invalid artifact request.")]
    InvalidRequest,
}

impl ArtifactError {
    pub fn code(self) -> &'static str {
        match self {
            Self::InvalidIdentity => "artifacts.invalid_identity",
            Self::InvalidRange => "artifacts.invalid_range",
            Self::InvalidPath => "artifacts.invalid_path",
            Self::InvalidPathSet => "artifacts.invalid_path_set",
            Self::InvalidContent => "artifacts.invalid_content",
            Self::FileCount => "artifacts.file_count",
            Self::FileSize => "artifacts.file_size",
            Self::SetSize => "artifacts.set_size",
            Self::ReplyLimit => "artifacts.reply_limit",
            Self::Capacity => "artifacts.capacity",
            Self::ActiveGeneration => "artifacts.active_generation",
            Self::UnknownHandle => "artifacts.unknown_handle",
            Self::Unavailable => "artifacts.unavailable",
            Self::InvalidRequest => "artifacts.invalid_request",
        }
    }
}

macro_rules! identity {
    ($name:ident) => {
        #[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd, Serialize)]
        #[serde(transparent)]
        pub struct $name(String);
        impl $name {
            pub fn parse(value: &str) -> Result<Self, ArtifactError> {
                if value.is_empty() || value.len() > 128 || value.chars().any(char::is_control) {
                    return Err(ArtifactError::InvalidIdentity);
                }
                Ok(Self(value.to_owned()))
            }
            pub fn as_str(&self) -> &str {
                &self.0
            }
        }
        impl<'de> Deserialize<'de> for $name {
            fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
                Self::parse(&String::deserialize(d)?).map_err(serde::de::Error::custom)
            }
        }
    };
}
identity!(GenerationId);
identity!(ArtifactId);
identity!(SessionId);
identity!(ProviderId);
identity!(ProducerId);
identity!(GenerationTarget);
identity!(GenerationIrVersion);

impl GenerationId {
    pub(super) fn fresh() -> Self {
        Self(uuid::Uuid::new_v4().to_string())
    }
}
impl ArtifactId {
    pub(super) fn fresh() -> Self {
        Self(uuid::Uuid::new_v4().to_string())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(transparent)]
pub struct ByteOffset(usize);
impl ByteOffset {
    pub fn new(value: usize) -> Result<Self, ArtifactError> {
        (value <= MAX_FILE_BYTES)
            .then_some(Self(value))
            .ok_or(ArtifactError::InvalidRange)
    }
    pub fn get(self) -> usize {
        self.0
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(transparent)]
pub struct ChunkLimit(usize);
impl ChunkLimit {
    pub fn new(value: usize) -> Result<Self, ArtifactError> {
        (1..=MAX_CHUNK_BYTES)
            .contains(&value)
            .then_some(Self(value))
            .ok_or(ArtifactError::InvalidRange)
    }
    pub fn get(self) -> usize {
        self.0
    }
}

#[derive(Debug, Eq, PartialEq)]
pub(super) enum GeneratedContent {
    // Unique private ownership avoids copying decoded Vecs into an Arc slice.
    // No mutable access or cloning is exposed after complete-set validation.
    Utf8Text(Vec<u8>),
    Binary(Vec<u8>),
}
impl GeneratedContent {
    pub fn bytes(&self) -> &[u8] {
        match self {
            Self::Utf8Text(bytes) | Self::Binary(bytes) => bytes,
        }
    }
    pub fn kind(&self) -> ArtifactKind {
        match self {
            Self::Utf8Text(_) => ArtifactKind::Utf8Text,
            Self::Binary(_) => ArtifactKind::Binary,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ArtifactKind {
    Utf8Text,
    Binary,
}

#[derive(Debug)]
pub(super) struct GeneratedArtifact {
    pub(super) path: RelativeArtifactPath,
    pub(super) content: GeneratedContent,
    pub(super) digest: Sha256Digest,
}
#[derive(Debug)]
pub(super) struct GeneratedArtifactSet {
    pub(super) artifacts: Vec<GeneratedArtifact>,
}

/// Pure preflight owns the SDK response and derives exact decoded capacity
/// without allocating decoded bytes. The shell reserves this capacity first.
#[derive(Debug)]
pub struct PreparedArtifacts {
    artifacts: Vec<(RelativeArtifactPath, Artifact)>,
    decoded_length: usize,
}
impl PreparedArtifacts {
    pub fn inspect(artifacts: Vec<Artifact>) -> Result<Self, ArtifactError> {
        if artifacts.len() > MAX_FILES {
            return Err(ArtifactError::FileCount);
        }
        let mut total = 0_usize;
        let mut paths = BTreeMap::new();
        let mut parents = BTreeMap::new();
        let mut validated = Vec::with_capacity(artifacts.len());
        for mut artifact in artifacts {
            let path = RelativeArtifactPath::parse(std::mem::take(&mut artifact.path))
                .map_err(|_| ArtifactError::InvalidPath)?;
            // The reused path constructor rejects C0; this profile also excludes
            // DEL and C1 control characters as its published portable policy.
            if path.as_str().chars().any(char::is_control) {
                return Err(ArtifactError::InvalidPath);
            }
            let key = portable_path_key(path.as_str());
            if paths.insert(key, path.as_str().to_owned()).is_some() {
                return Err(ArtifactError::InvalidPathSet);
            }
            for (separator, _) in path.as_str().match_indices('/') {
                let parent = &path.as_str()[..separator];
                if let Some(prior) = parents.insert(portable_path_key(parent), parent.to_owned())
                    && prior != parent
                {
                    return Err(ArtifactError::InvalidPathSet);
                }
            }
            let length = if artifact.binary {
                if artifact.content.len() > MAX_FILE_BYTES.div_ceil(3) * 4 {
                    return Err(ArtifactError::FileSize);
                }
                canonical_decoded_length(&artifact.content)?
            } else {
                artifact.content.len()
            };
            if length > MAX_FILE_BYTES {
                return Err(ArtifactError::FileSize);
            }
            total = total.checked_add(length).ok_or(ArtifactError::SetSize)?;
            if total > MAX_SET_BYTES {
                return Err(ArtifactError::SetSize);
            }
            validated.push((path, artifact));
        }
        for key in paths.keys() {
            for (separator, _) in key.match_indices('/') {
                if paths.contains_key(&key[..separator]) {
                    return Err(ArtifactError::InvalidPathSet);
                }
            }
        }
        Ok(Self {
            artifacts: validated,
            decoded_length: total,
        })
    }
    pub fn decoded_length(&self) -> usize {
        self.decoded_length
    }
    pub(super) fn decode(self) -> Result<GeneratedArtifactSet, ArtifactError> {
        let artifacts = self
            .artifacts
            .into_iter()
            .map(|(path, artifact)| {
                let content = if artifact.binary {
                    let bytes = STANDARD
                        .decode(&artifact.content)
                        .map_err(|_| ArtifactError::InvalidContent)?;
                    // Validation above is allocation-free. The SDK's canonical form
                    // is additionally checked against the encoder at this boundary.
                    if STANDARD.encode(&bytes) != artifact.content {
                        return Err(ArtifactError::InvalidContent);
                    }
                    GeneratedContent::Binary(bytes)
                } else {
                    GeneratedContent::Utf8Text(artifact.content.into_bytes())
                };
                let digest = Sha256Digest::of_bytes(content.bytes());
                Ok(GeneratedArtifact {
                    path,
                    content,
                    digest,
                })
            })
            .collect::<Result<Vec<_>, ArtifactError>>()?;
        Ok(GeneratedArtifactSet { artifacts })
    }
}

/// Unicode17 NFKC, Unicode9 default full casefold, then Unicode17 NFC.
/// Keep the two data-table revisions separately published and tested.
pub fn portable_path_key(path: &str) -> String {
    path.nfkc().case_fold().nfc().collect()
}

fn sextet(byte: u8) -> Option<u8> {
    match byte {
        b'A'..=b'Z' => Some(byte - b'A'),
        b'a'..=b'z' => Some(byte - b'a' + 26),
        b'0'..=b'9' => Some(byte - b'0' + 52),
        b'+' => Some(62),
        b'/' => Some(63),
        _ => None,
    }
}
fn canonical_decoded_length(content: &str) -> Result<usize, ArtifactError> {
    let bytes = content.as_bytes();
    if bytes.is_empty() {
        return Ok(0);
    }
    if !bytes.len().is_multiple_of(4) {
        return Err(ArtifactError::InvalidContent);
    }
    let padding = if bytes.ends_with(b"==") {
        2
    } else if bytes.ends_with(b"=") {
        1
    } else {
        0
    };
    if bytes[..bytes.len() - padding]
        .iter()
        .any(|byte| sextet(*byte).is_none())
        || (padding == 2 && sextet(bytes[bytes.len() - 3]).is_none_or(|value| value & 15 != 0))
        || (padding == 1 && sextet(bytes[bytes.len() - 2]).is_none_or(|value| value & 3 != 0))
    {
        return Err(ArtifactError::InvalidContent);
    }
    Ok(bytes.len() / 4 * 3 - padding)
}
