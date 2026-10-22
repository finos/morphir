//! Owned literal DATA. Token spans refer to the original payload, never to a
//! parsed tree. Neither these values nor their ordinals identify physical IO.
use super::{BrowserDocumentError, MAX_SAFE, shape};
use crate::workbench::model_originals::workflow::Natural;
use serde_json::value::RawValue;

#[derive(Debug)]
pub struct BrowserJsonStringSpan {
    start: usize,
    end: usize,
}
impl BrowserJsonStringSpan {
    pub(super) fn from_raw(payload: &[u8], raw: &RawValue) -> Result<Self, BrowserDocumentError> {
        let token = raw.get();
        if !token.starts_with('"') {
            return shape();
        }
        let Some(start) = (token.as_ptr() as usize).checked_sub(payload.as_ptr() as usize) else {
            return shape();
        };
        let Some(end) = start.checked_add(token.len()) else {
            return shape();
        };
        if payload.get(start..end).is_none() {
            return shape();
        }
        Ok(Self { start, end })
    }
    /// Resolve only against the SAME record's original payload. These bounds
    /// do not authenticate arbitrary replacement bytes or another document.
    pub fn range(&self) -> std::ops::Range<usize> {
        self.start..self.end
    }
}

#[derive(Debug)]
pub struct BrowserVisitData {
    pub(super) workspace: BrowserJsonStringSpan,
    pub(super) opening: Natural<0, MAX_SAFE>,
}
impl BrowserVisitData {
    pub fn workspace(&self) -> &BrowserJsonStringSpan {
        &self.workspace
    }
    pub fn opening(&self) -> &Natural<0, MAX_SAFE> {
        &self.opening
    }
}
#[derive(Debug)]
pub struct BrowserOpeningData {
    pub(super) visit: BrowserVisitData,
    pub(super) attempt: BrowserJsonStringSpan,
    pub(super) opening_ordinal: Natural<1, MAX_SAFE>,
}
impl BrowserOpeningData {
    pub fn visit(&self) -> &BrowserVisitData {
        &self.visit
    }
    pub fn attempt(&self) -> &BrowserJsonStringSpan {
        &self.attempt
    }
    pub fn opening_ordinal(&self) -> &Natural<1, MAX_SAFE> {
        &self.opening_ordinal
    }
}
#[derive(Debug)]
pub struct BrowserInventoryData {
    pub(super) opening: BrowserOpeningData,
    pub(super) inventory_revision: BrowserJsonStringSpan,
}
impl BrowserInventoryData {
    pub fn opening(&self) -> &BrowserOpeningData {
        &self.opening
    }
    pub fn inventory_revision(&self) -> &BrowserJsonStringSpan {
        &self.inventory_revision
    }
}
#[derive(Debug)]
pub struct BrowserArchiveData {
    pub(super) inventory: BrowserInventoryData,
    pub(super) operation_ordinal: Natural<1, MAX_SAFE>,
}
impl BrowserArchiveData {
    pub fn inventory(&self) -> &BrowserInventoryData {
        &self.inventory
    }
    pub fn operation_ordinal(&self) -> &Natural<1, MAX_SAFE> {
        &self.operation_ordinal
    }
}
#[derive(Debug)]
pub struct BrowserReadyArchiveData {
    pub(super) archive: BrowserArchiveData,
    pub(super) ready_ordinal: Natural<1, MAX_SAFE>,
}
impl BrowserReadyArchiveData {
    pub fn archive(&self) -> &BrowserArchiveData {
        &self.archive
    }
    pub fn ready_ordinal(&self) -> &Natural<1, MAX_SAFE> {
        &self.ready_ordinal
    }
}
#[derive(Debug)]
pub struct BrowserSourceSelectionData {
    pub(super) session_id: BrowserJsonStringSpan,
    pub(super) provider_id: BrowserJsonStringSpan,
    pub(super) locator: BrowserJsonStringSpan,
}
impl BrowserSourceSelectionData {
    pub fn session_id(&self) -> &BrowserJsonStringSpan {
        &self.session_id
    }
    pub fn provider_id(&self) -> &BrowserJsonStringSpan {
        &self.provider_id
    }
    pub fn locator(&self) -> &BrowserJsonStringSpan {
        &self.locator
    }
}
#[derive(Debug)]
pub struct BrowserProjectSelectionData {
    pub(super) source: BrowserSourceSelectionData,
    pub(super) project_id: BrowserJsonStringSpan,
}
impl BrowserProjectSelectionData {
    pub fn source(&self) -> &BrowserSourceSelectionData {
        &self.source
    }
    pub fn project_id(&self) -> &BrowserJsonStringSpan {
        &self.project_id
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserDownloadResultData {
    DownloadRequested,
    Retired,
    Failed,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserDownloadOutcomeData {
    Raised,
    Returned(BrowserDownloadResultData),
}

#[derive(Debug)]
pub enum BrowserDocumentFactData {
    OpeningStored(BrowserOpeningData),
    SourceSelected {
        actual: BrowserOpeningData,
        selection: BrowserSourceSelectionData,
    },
    ProjectSelected {
        actual: BrowserOpeningData,
        selection: BrowserProjectSelectionData,
    },
    TransferVerified {
        actual: BrowserOpeningData,
        selection: BrowserProjectSelectionData,
    },
    InventoryAdopted(BrowserInventoryData),
    ArchiveStored(BrowserArchiveData),
    ArchiveRetirementRequested(BrowserArchiveData),
    ArchiveSettledRetired(BrowserArchiveData),
    ArchiveReady(BrowserReadyArchiveData),
    DownloadWillRequest(BrowserReadyArchiveData),
    DownloadResult {
        actual: BrowserReadyArchiveData,
        outcome: BrowserDownloadOutcomeData,
    },
    ModelClosed(BrowserVisitData),
    WorkspaceClosed(BrowserVisitData),
}
#[derive(Debug)]
pub enum BrowserDocumentContent {
    Fact(BrowserDocumentFactData),
    End { last_sequence: Natural<0, MAX_SAFE> },
}
#[derive(Debug)]
pub struct BrowserDocumentFrameData {
    pub(super) sequence: Natural<1, MAX_SAFE>,
    pub(super) content: BrowserDocumentContent,
}
impl BrowserDocumentFrameData {
    pub fn sequence(&self) -> &Natural<1, MAX_SAFE> {
        &self.sequence
    }
    pub fn content(&self) -> &BrowserDocumentContent {
        &self.content
    }
    pub fn kind(&self) -> u8 {
        match self.content {
            BrowserDocumentContent::Fact(_) => 1,
            BrowserDocumentContent::End { .. } => 2,
        }
    }
}

/// Parsing discriminant only. It prevents another string-tag comparison pass
/// while the existing exact field/owner checks construct the closed result.
pub(super) enum FactTag {
    OpeningStored,
    SourceSelected,
    ProjectSelected,
    TransferVerified,
    InventoryAdopted,
    ArchiveStored,
    ArchiveRetirementRequested,
    ArchiveSettledRetired,
    ArchiveReady,
    DownloadWillRequest,
    DownloadResult,
    ModelClosed,
    WorkspaceClosed,
}
impl FactTag {
    pub(super) fn parse(tag: &str) -> Result<Self, BrowserDocumentError> {
        Ok(match tag {
            "opening-stored" => Self::OpeningStored,
            "source-selected" => Self::SourceSelected,
            "project-selected" => Self::ProjectSelected,
            "transfer-verified" => Self::TransferVerified,
            "inventory-adopted" => Self::InventoryAdopted,
            "archive-stored" => Self::ArchiveStored,
            "archive-retirement-requested" => Self::ArchiveRetirementRequested,
            "archive-settled-retired" => Self::ArchiveSettledRetired,
            "archive-ready" => Self::ArchiveReady,
            "download-will-request" => Self::DownloadWillRequest,
            "download-result" => Self::DownloadResult,
            "model-closed" => Self::ModelClosed,
            "workspace-closed" => Self::WorkspaceClosed,
            _ => return shape(),
        })
    }
    pub(super) fn fields(&self) -> &'static [&'static str] {
        match self {
            Self::SourceSelected => &[
                "kind",
                "actual",
                "sequence",
                "sessionId",
                "providerId",
                "locator",
            ],
            Self::ProjectSelected | Self::TransferVerified => &[
                "kind",
                "actual",
                "sequence",
                "sessionId",
                "providerId",
                "locator",
                "projectId",
            ],
            Self::DownloadResult => &["kind", "actual", "sequence", "outcome"],
            _ => &["kind", "actual", "sequence"],
        }
    }
    pub(super) fn owner_fields(&self) -> &'static [&'static str] {
        match self {
            Self::ModelClosed | Self::WorkspaceClosed => &["workspace", "opening"],
            Self::OpeningStored
            | Self::SourceSelected
            | Self::ProjectSelected
            | Self::TransferVerified => &["workspace", "opening", "attempt", "openingOrdinal"],
            Self::InventoryAdopted => &[
                "workspace",
                "opening",
                "attempt",
                "openingOrdinal",
                "inventoryRevision",
            ],
            Self::ArchiveStored
            | Self::ArchiveRetirementRequested
            | Self::ArchiveSettledRetired => &[
                "workspace",
                "opening",
                "attempt",
                "openingOrdinal",
                "inventoryRevision",
                "operationOrdinal",
            ],
            Self::ArchiveReady | Self::DownloadWillRequest | Self::DownloadResult => &[
                "workspace",
                "opening",
                "attempt",
                "openingOrdinal",
                "inventoryRevision",
                "operationOrdinal",
                "readyOrdinal",
            ],
        }
    }
}
