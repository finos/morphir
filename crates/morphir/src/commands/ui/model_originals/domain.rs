use std::path::{Component, Path};

use morphir_common::ir_transport::IrVersion;
use morphir_devkit::{IrDescriptor, IrLayout};
use morphir_distribution::{ArtifactFilename, Sha256Digest};
use serde::Serialize;

pub const CONTRACT_VERSION: &str = "0.1.0-draft.1";
pub const MAX_SOURCE_BYTES: usize = 64 * 1024 * 1024;
pub const MAX_RECORD_BYTES: usize = 64 * 1024 * 1024;
pub const MAX_METADATA_BYTES: usize = 64 * 1024 * 1024;
pub const MAX_ROOTS: usize = 64;
pub const MAX_DESCENDANTS: usize = 100_000;
pub const MAX_ENTRIES: usize = MAX_DESCENDANTS + MAX_ROOTS;

#[derive(Debug, Clone, Copy, Eq, PartialEq, thiserror::Error)]
pub enum CaptureError {
    #[error("Invalid model source path.")]
    InvalidPath,
    #[error("Model source paths conflict or alias.")]
    InvalidPathSet,
    #[error("Invalid model ownership declaration.")]
    InvalidDeclaration,
    #[error("Invalid compile record.")]
    InvalidRecord,
    #[error("The recorded model representation is unsupported.")]
    UnsupportedRepresentation,
    #[error("Model originals exceed their source byte limit.")]
    SourceLimit,
    #[error("Compile record exceeds its input byte limit.")]
    RecordLimit,
    #[error("Model original inventory exceeds its limit.")]
    InventoryLimit,
    #[error("Model source capture failed.")]
    CaptureFailed,
    #[error("Model source capture timed out or was cancelled.")]
    Timeout,
    #[error("Model capture capacity is exhausted.")]
    Capacity,
    #[error("A model capture is already active on this connection.")]
    ActiveCapture,
    #[error("The model capture is unavailable on this connection.")]
    UnknownHandle,
    #[error("Invalid model capture identity.")]
    InvalidIdentity,
}

/// A portable source path, deliberately independent of the generated-artifact
/// 1024 UTF-16-unit bound. Component portability comes from the shared domain.
#[derive(Debug, Clone, Eq, PartialEq, Ord, PartialOrd, Serialize)]
#[serde(transparent)]
pub struct SourcePath(String);
impl SourcePath {
    pub fn parse(value: &str) -> Result<Self, CaptureError> {
        if value.is_empty()
            || value.len() > 16_000
            || value.chars().count() > 4000
            || value.encode_utf16().count() > 8000
            || value.chars().any(char::is_control)
            || value
                .split('/')
                .any(|part| ArtifactFilename::parse(part).is_err())
        {
            return Err(CaptureError::InvalidPath);
        }
        Ok(Self(value.to_owned()))
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Module identity resolved by workspace selection, never a client-supplied path.
#[derive(Debug, Clone, Eq, PartialEq)]
pub struct SelectedModule(String);
impl SelectedModule {
    pub fn parse(value: &str) -> Result<Self, CaptureError> {
        if !value.is_empty() {
            SourcePath::parse(value)?;
            if Path::new(value)
                .components()
                .any(|part| !matches!(part, Component::Normal(_)))
            {
                return Err(CaptureError::InvalidPath);
            }
        }
        Ok(Self(value.to_owned()))
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum CaptureScope {
    Primary,
    Complete,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum SourceKind {
    File,
    Directory,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize)]
pub struct SourceRoot {
    pub(super) kind: SourceKind,
    pub(super) path: SourcePath,
}
impl SourceRoot {
    pub(super) fn new(kind: SourceKind, path: SourcePath) -> Result<Self, CaptureError> {
        if path.as_str().split('/').count() > 128 {
            return Err(CaptureError::InvalidPath);
        }
        Ok(Self { kind, path })
    }
    pub fn kind(&self) -> SourceKind {
        self.kind
    }
    pub fn path(&self) -> &SourcePath {
        &self.path
    }
}

/// Private temporary accessor model. Replace with the coordinated devkit type
/// when published, rather than exposing a second declaration API.
#[derive(Debug)]
pub(super) enum Declaration {
    Absent,
    Declared(Vec<SourceRoot>),
    Invalid,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum SourceFormat {
    Json,
    Yaml,
    Ion,
}
impl SourceFormat {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Json => "json",
            Self::Yaml => "yaml",
            Self::Ion => "ion",
        }
    }
}
/// Validated storage selection, separate from an actual original header release
/// and from any eventual semantic projection release.
#[derive(Debug, Clone)]
pub struct CapturedDescriptor {
    path: SourcePath,
    layout: IrLayout,
    format: SourceFormat,
    version: IrVersion,
}
impl CapturedDescriptor {
    pub(super) fn parse(value: IrDescriptor) -> Result<Self, CaptureError> {
        let path = SourcePath::parse(&value.path)?;
        let format = match value.format.as_str() {
            "json" => SourceFormat::Json,
            "yaml" => SourceFormat::Yaml,
            "ion" => SourceFormat::Ion,
            _ => return Err(CaptureError::UnsupportedRepresentation),
        };
        let version = match value.version.as_str() {
            "v3" => IrVersion::V3,
            "v4" => IrVersion::V4,
            _ => return Err(CaptureError::UnsupportedRepresentation),
        };
        let descriptor = Self {
            path,
            layout: value.layout,
            format,
            version,
        };
        descriptor.primary()?;
        Ok(descriptor)
    }
    pub fn path(&self) -> &SourcePath {
        &self.path
    }
    pub fn layout(&self) -> IrLayout {
        self.layout
    }
    pub fn format(&self) -> SourceFormat {
        self.format
    }
    pub fn version(&self) -> IrVersion {
        self.version
    }
    pub fn as_devkit_descriptor(&self) -> IrDescriptor {
        IrDescriptor {
            path: self.path.as_str().to_owned(),
            layout: self.layout,
            format: self.format.as_str().to_owned(),
            version: match self.version {
                IrVersion::V3 => "v3",
                IrVersion::V4 => "v4",
            }
            .to_owned(),
        }
    }
    pub(super) fn primary(&self) -> Result<SourceRoot, CaptureError> {
        SourceRoot::new(
            match self.layout {
                IrLayout::SingleFile => SourceKind::File,
                IrLayout::DocumentTree => SourceKind::Directory,
            },
            self.path.clone(),
        )
    }
}

/// Exact original bytes have unique ownership. Directory entries carry no bytes.
#[derive(Debug)]
pub struct SourceEntry {
    pub(super) id: String,
    pub(super) path: SourcePath,
    pub(super) content: SourceContent,
}
#[derive(Debug)]
pub(super) enum SourceContent {
    Directory,
    File {
        bytes: Vec<u8>,
        digest: Sha256Digest,
    },
}
impl SourceEntry {
    pub fn path(&self) -> &SourcePath {
        &self.path
    }
    pub fn kind(&self) -> SourceKind {
        match self.content {
            SourceContent::Directory => SourceKind::Directory,
            SourceContent::File { .. } => SourceKind::File,
        }
    }
    pub fn entry_id(&self) -> &str {
        &self.id
    }
    pub fn sha256(&self) -> Option<&Sha256Digest> {
        match &self.content {
            SourceContent::File { digest, .. } => Some(digest),
            _ => None,
        }
    }
    pub fn byte_length(&self) -> Option<usize> {
        match &self.content {
            SourceContent::File { bytes, .. } => Some(bytes.len()),
            _ => None,
        }
    }
}

/// Exact raw bookkeeping is hashed privately and dropped before capture returns.
/// Only this bounded summary survives the separate temporary record budget.
#[derive(Debug)]
pub struct CapturedRecord {
    pub(super) byte_length: usize,
    pub(super) digest: Sha256Digest,
    pub(super) module: SelectedModule,
    pub(super) descriptor: CapturedDescriptor,
}
impl CapturedRecord {
    pub fn byte_length(&self) -> usize {
        self.byte_length
    }
    pub fn sha256(&self) -> &Sha256Digest {
        &self.digest
    }
    pub fn module(&self) -> &SelectedModule {
        &self.module
    }
    pub fn descriptor(&self) -> &CapturedDescriptor {
        &self.descriptor
    }
}

#[derive(Debug)]
pub struct CapturedSources {
    pub(super) record: CapturedRecord,
    pub(super) primary: SourceRoot,
    pub(super) companions: Vec<SourceRoot>,
    pub(super) scope: CaptureScope,
    pub(super) entries: Vec<SourceEntry>,
    pub(super) source_bytes: usize,
    pub(super) metadata_bytes: usize,
    pub(super) inventory_digest: Sha256Digest,
}
impl CapturedSources {
    pub fn record(&self) -> &CapturedRecord {
        &self.record
    }
    pub fn primary(&self) -> &SourceRoot {
        &self.primary
    }
    pub fn companions(&self) -> &[SourceRoot] {
        &self.companions
    }
    pub fn coverage(&self) -> CaptureScope {
        self.scope
    }
    pub fn entries(&self) -> &[SourceEntry] {
        &self.entries
    }
    pub fn source_byte_length(&self) -> usize {
        self.source_bytes
    }
    pub fn metadata_byte_length(&self) -> usize {
        self.metadata_bytes
    }
    pub fn inventory_sha256(&self) -> &Sha256Digest {
        &self.inventory_digest
    }
    pub fn file_bytes(&self, path: &SourcePath) -> Option<&[u8]> {
        let entry = self
            .entries
            .binary_search_by(|entry| entry.path.cmp(path))
            .ok()?;
        match &self.entries[entry].content {
            SourceContent::File { bytes, .. } => Some(bytes),
            _ => None,
        }
    }
    /// Both header inspection and semantic conversion must consume this captured
    /// source owner, never reopen live storage or pair it with v1 model.open.
    /// This plan owns no codec output and makes no decode-budget guarantee yet.
    pub fn projection_plan(&self) -> FrozenProjectionPlan<'_> {
        FrozenProjectionPlan { sources: self }
    }
}
pub struct FrozenProjectionPlan<'a> {
    sources: &'a CapturedSources,
}
impl<'a> FrozenProjectionPlan<'a> {
    pub fn descriptor(&self) -> &'a CapturedDescriptor {
        &self.sources.record.descriptor
    }
    pub fn primary(&self) -> &'a SourceRoot {
        &self.sources.primary
    }
    pub fn entries(&self) -> impl Iterator<Item = &'a SourceEntry> {
        self.sources.entries.iter().filter(|entry| {
            entry.path == self.sources.primary.path
                || (self.sources.primary.kind == SourceKind::Directory
                    && entry
                        .path
                        .as_str()
                        .strip_prefix(self.sources.primary.path.as_str())
                        .is_some_and(|suffix| suffix.starts_with('/')))
        })
    }
    pub fn file_bytes(&self, path: &SourcePath) -> Option<&'a [u8]> {
        self.entries()
            .find(|entry| entry.path() == path)
            .and_then(|entry| match &entry.content {
                SourceContent::File { bytes, .. } => Some(bytes.as_slice()),
                _ => None,
            })
    }
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum CaptureUnavailable {
    NotCompiled,
    CompanionsUndeclared,
}
#[derive(Debug)]
pub enum CaptureResult {
    Ready(Box<CapturedSources>),
    Unavailable(CaptureUnavailable),
}
impl CaptureResult {
    pub fn ready(self) -> Option<CapturedSources> {
        match self {
            Self::Ready(value) => Some(*value),
            _ => None,
        }
    }
}
