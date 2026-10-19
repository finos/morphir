//! Join actual capture/page/read evidence to independently authored source
//! facts. A self-consistent descriptor and payload are insufficient. This pure
//! check neither authenticates a host nor creates a usable original/model owner.
use super::inventory::{EntryContent, EntryPath};
use super::{
    CaptureExpectation, CaptureInventory, EntryId, Exchange, InvalidFrame, Inventory, ReadTarget,
    RootKind, SessionId, TransferError,
};
use std::{collections::BTreeMap, fmt};

const MAX_SOURCE_BYTES: usize = 64 * 1024 * 1024;
const MAX_ENTRIES: usize = 100064;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EvidenceError {
    Frame(InvalidFrame),
    Transfer(TransferError),
    EntrySet,
    OriginalSet,
    Bytes,
    SourceBudget,
    MetadataBudget,
}
impl From<InvalidFrame> for EvidenceError {
    fn from(error: InvalidFrame) -> Self {
        Self::Frame(error)
    }
}
impl From<TransferError> for EvidenceError {
    fn from(error: TransferError) -> Self {
        Self::Transfer(error)
    }
}
impl fmt::Display for EvidenceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Frame(_) => "invalid expected source path",
            Self::Transfer(_) => "invalid actual capture or transfer evidence",
            Self::EntrySet => "inventory differs from the independent selected source entries",
            Self::OriginalSet => "original evidence has missing, duplicate or extra streams",
            Self::Bytes => "original bytes differ from the independently authored source",
            Self::SourceBudget => "expected originals exceed their aggregate source budget",
            Self::MetadataBudget => "expected source paths exceed their metadata budget",
        })
    }
}
impl std::error::Error for EvidenceError {}

#[derive(Debug, Clone)]
enum ByteRecipe<'a> {
    Literal(&'a [u8]),
    Repeat(u8),
    Cycle(u8),
    ChunkIndexed(u8),
    PrefixTail { prefix: u8, tail: &'a [u8] },
}
/// Finite byte expectations keep large fixtures compact. Construction validates
/// the original-source limit before recipe expansion; comparison allocates no
/// recipe output. Projection capacity is a separate concern and is not charged.
#[derive(Debug, Clone)]
pub struct ExpectedBytes<'a> {
    recipe: ByteRecipe<'a>,
    length: usize,
}
impl<'a> ExpectedBytes<'a> {
    fn new(recipe: ByteRecipe<'a>, length: usize) -> Result<Self, EvidenceError> {
        if length > MAX_SOURCE_BYTES {
            return Err(EvidenceError::SourceBudget);
        }
        Ok(Self { recipe, length })
    }
    pub fn literal(bytes: &'a [u8]) -> Result<Self, EvidenceError> {
        Self::new(ByteRecipe::Literal(bytes), bytes.len())
    }
    pub fn repeat(byte: u8, length: usize) -> Result<Self, EvidenceError> {
        Self::new(ByteRecipe::Repeat(byte), length)
    }
    pub fn cycle(seed: u8, length: usize) -> Result<Self, EvidenceError> {
        Self::new(ByteRecipe::Cycle(seed), length)
    }
    /// Each 65536-byte chunk starts with the next byte of the wrapping cycle.
    pub fn chunk_indexed(seed: u8, length: usize) -> Result<Self, EvidenceError> {
        Self::new(ByteRecipe::ChunkIndexed(seed), length)
    }
    pub fn prefix_tail(prefix: u8, length: usize, tail: &'a [u8]) -> Result<Self, EvidenceError> {
        if tail.len() > length {
            return Err(EvidenceError::Bytes);
        }
        Self::new(ByteRecipe::PrefixTail { prefix, tail }, length)
    }
    fn matches(&self, bytes: &[u8]) -> bool {
        if bytes.len() != self.length {
            return false;
        }
        match self.recipe {
            ByteRecipe::Literal(expected) => bytes == expected,
            ByteRecipe::Repeat(byte) => bytes.iter().all(|actual| *actual == byte),
            ByteRecipe::Cycle(seed) => bytes
                .iter()
                .enumerate()
                .all(|(i, b)| *b == seed.wrapping_add(i as u8)),
            ByteRecipe::ChunkIndexed(seed) => bytes
                .iter()
                .enumerate()
                .all(|(i, b)| *b == seed.wrapping_add((i / 65536) as u8)),
            ByteRecipe::PrefixTail { prefix, tail } => {
                let split = self.length - tail.len();
                bytes[..split].iter().all(|b| *b == prefix) && &bytes[split..] == tail
            }
        }
    }
}
#[derive(Debug, Clone)]
enum ExpectedContent<'a> {
    Directory,
    File(ExpectedBytes<'a>),
}
#[derive(Debug, Clone)]
pub struct ExpectedOriginalEntry<'a> {
    path: EntryPath,
    content: ExpectedContent<'a>,
}
impl<'a> ExpectedOriginalEntry<'a> {
    pub fn file(path: &str, bytes: ExpectedBytes<'a>) -> Result<Self, EvidenceError> {
        Ok(Self {
            path: EntryPath::parse(&path.into())?,
            content: ExpectedContent::File(bytes),
        })
    }
    pub fn directory(path: &str) -> Result<Self, EvidenceError> {
        Ok(Self {
            path: EntryPath::parse(&path.into())?,
            content: ExpectedContent::Directory,
        })
    }
}

/// Exactly the independently selected file/directory snapshot, including empty
/// directories and selected roots. The fixture adapter supplies this snapshot;
/// the checker never infers it from the observed manifest or reads live paths.
#[derive(Debug, Clone)]
pub struct ExpectedOriginals<'a> {
    entries: Vec<ExpectedOriginalEntry<'a>>,
}
impl<'a> ExpectedOriginals<'a> {
    pub fn new(mut entries: Vec<ExpectedOriginalEntry<'a>>) -> Result<Self, EvidenceError> {
        if entries.is_empty() || entries.len() > MAX_ENTRIES {
            return Err(EvidenceError::EntrySet);
        }
        let mut bytes = 0usize;
        let mut paths = 0usize;
        for entry in &entries {
            paths = paths
                .checked_add(entry.path.as_str().len())
                .filter(|n| *n <= MAX_SOURCE_BYTES)
                .ok_or(EvidenceError::MetadataBudget)?;
            if let ExpectedContent::File(content) = &entry.content {
                bytes = bytes
                    .checked_add(content.length)
                    .filter(|n| *n <= MAX_SOURCE_BYTES)
                    .ok_or(EvidenceError::SourceBudget)?;
            }
        }
        entries.sort_by(|a, b| a.path.as_str().as_bytes().cmp(b.path.as_str().as_bytes()));
        if entries.windows(2).any(|pair| pair[0].path == pair[1].path) {
            return Err(EvidenceError::EntrySet);
        }
        Ok(Self { entries })
    }
    pub fn verify(
        &self,
        session: &SessionId,
        evidence: CaptureEvidence<'_>,
    ) -> Result<CheckedOriginalsEvidence, EvidenceError> {
        let expected = CaptureExpectation::from_exchange(&evidence.capture, session)?;
        let capture = expected.verify_inventory(evidence.pages)?;
        let inventory = capture.inventory();
        if inventory.entries().len() != self.entries.len() {
            return Err(EvidenceError::EntrySet);
        }
        // Establish the complete set before interpreting any potentially large
        // original. Metadata validity alone is never evidence of fixture bytes.
        for (actual, expected) in inventory.entries().iter().zip(&self.entries) {
            let kind = match expected.content {
                ExpectedContent::Directory => RootKind::Directory,
                ExpectedContent::File(_) => RootKind::File,
            };
            if actual.path() != expected.path.as_str() || actual.kind() != kind {
                return Err(EvidenceError::EntrySet);
            }
            if let (EntryContent::File { byte_length, .. }, ExpectedContent::File(bytes)) =
                (actual.content(), &expected.content)
                && *byte_length != bytes.length
            {
                return Err(EvidenceError::Bytes);
            }
        }
        let mut transfers = BTreeMap::new();
        for transfer in evidence.originals {
            if transfers
                .insert(transfer.entry.as_str(), transfer.exchanges)
                .is_some()
            {
                return Err(EvidenceError::OriginalSet);
            }
        }
        let files = inventory
            .entries()
            .iter()
            .filter(|entry| entry.kind() == RootKind::File);
        if transfers.len() != files.clone().count()
            || files
                .into_iter()
                .any(|entry| !transfers.contains_key(entry.id().as_str()))
        {
            return Err(EvidenceError::OriginalSet);
        }
        for (actual, expected) in inventory.entries().iter().zip(&self.entries) {
            if let ExpectedContent::File(bytes) = &expected.content {
                let exchanges = transfers
                    .remove(actual.id().as_str())
                    .ok_or(EvidenceError::OriginalSet)?;
                let target = ReadTarget::Original {
                    entry: actual.id().clone(),
                };
                // Bind each stream to this capture and inventory. Accepting an
                // already checked stream from another capture would lose that
                // provenance. At most one original output is retained here.
                let stream = capture.verify_stream(&target, exchanges)?;
                if !bytes.matches(stream.bytes()) {
                    return Err(EvidenceError::Bytes);
                }
            }
        }
        if !transfers.is_empty() {
            return Err(EvidenceError::OriginalSet);
        }
        Ok(CheckedOriginalsEvidence { capture })
    }
}

pub struct OriginalTransfer<'a> {
    pub entry: &'a EntryId,
    pub exchanges: &'a [Exchange<'a>],
}
pub struct CaptureEvidence<'a> {
    pub capture: Exchange<'a>,
    pub pages: &'a [Exchange<'a>],
    pub originals: &'a [OriginalTransfer<'a>],
}
/// Checked source correspondence, not an execution or filesystem capability.
#[derive(Debug, Clone)]
pub struct CheckedOriginalsEvidence {
    capture: CaptureInventory,
}
impl CheckedOriginalsEvidence {
    pub fn projection_status(&self) -> super::ProjectionStatus {
        self.capture.projection_status()
    }
    pub fn inventory(&self) -> &Inventory {
        self.capture.inventory()
    }
    /// Check projection bytes/semantics against this already verified capture.
    /// The result still grants no current-model or execution authority.
    pub fn verify_projection(
        &self,
        expected: &super::ExpectedProjection<'_>,
        exchanges: &[Exchange<'_>],
    ) -> Result<super::CheckedProjectionEvidence, super::ProjectionError> {
        expected.verify(&self.capture, exchanges)
    }
}

#[cfg(test)]
mod tests {
    use super::ExpectedBytes;

    #[test]
    fn recipe_bytes_wrap_and_distinguish_chunk_boundaries() {
        assert!(
            ExpectedBytes::cycle(254, 4)
                .unwrap()
                .matches(&[254, 255, 0, 1])
        );
        assert!(
            !ExpectedBytes::cycle(254, 4)
                .unwrap()
                .matches(&[254, 255, 0, 2])
        );
        assert!(ExpectedBytes::repeat(7, 3).unwrap().matches(&[7, 7, 7]));
        assert!(!ExpectedBytes::repeat(7, 3).unwrap().matches(&[7, 7]));
        let mut chunks = vec![255; 65538];
        chunks[65536..].fill(0);
        let expected = ExpectedBytes::chunk_indexed(255, 65538).unwrap();
        assert!(expected.matches(&chunks));
        chunks[65535] = 0;
        assert!(!expected.matches(&chunks));
        assert!(
            ExpectedBytes::prefix_tail(b' ', 4, b"{}")
                .unwrap()
                .matches(b"  {}")
        );
        assert!(ExpectedBytes::repeat(0, 0).unwrap().matches(&[]));
    }
}
