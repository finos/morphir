//! Engine-retained document DATA. Native joins and physical actions are separate.
#[path = "collection/transcript.rs"]
mod transcript;
use super::super::installed::observation::InstalledObservationFault;
use super::{
    adapter::execution_loans::{
        BrowserExecutionOpening, BrowserLoanStamp, BrowserOpeningPosition, PreparedBrowserClientRun,
    },
    *,
};
use std::{
    alloc::Layout,
    mem::size_of,
    sync::{Arc, Mutex, MutexGuard, atomic::AtomicUsize},
    time::Instant,
};
pub use transcript::*;

/// Explicit dimensions paid from the existing policy owners, never a new grant.
#[derive(Debug, Clone, Copy)]
pub struct BrowserDocumentBounds {
    records: usize,
    journal_bytes: usize,
    frame_bytes: usize,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserCollectionFault {
    Bounds,
    Source,
    Funding,
    Allocation,
    Framing,
    Order,
    End,
    Capacity,
    Decode(BrowserDocumentErrorKind),
    Poisoned,
    ProducerIncomplete,
}
impl BrowserDocumentBounds {
    pub fn new(
        records: usize,
        journal_bytes: usize,
        frame_bytes: usize,
    ) -> Result<Self, BrowserCollectionFault> {
        if records == 0
            || journal_bytes < 16
            || frame_bytes < 16
            || [records, journal_bytes, frame_bytes]
                .iter()
                .any(|n| u64::try_from(*n).map_or(true, |n| n > 9_007_199_254_740_991))
            || u32::try_from(frame_bytes).is_err()
            || u32::try_from(journal_bytes).is_err()
            || records
                .checked_mul(8)
                .is_none_or(|n| u32::try_from(n).is_err())
        {
            return Err(BrowserCollectionFault::Bounds);
        }
        Ok(Self {
            records,
            journal_bytes,
            frame_bytes,
        })
    }
    pub fn records(self) -> usize {
        self.records
    }
    pub fn journal_bytes(self) -> usize {
        self.journal_bytes
    }
    pub fn frame_bytes(self) -> usize {
        self.frame_bytes
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserCollectionTerminal {
    AllDocumentsEnded {
        documents: usize,
        records: usize,
    },
    Incomplete {
        unissued: usize,
        open: usize,
        first: Option<BrowserCollectionFault>,
    },
}
enum Stream {
    Open,
    Ended,
    Faulted(BrowserCollectionFault),
}
struct RetainedRecord {
    data: BrowserDocumentFrameData,
    bytes: std::ops::Range<usize>,
}
struct Journal {
    raw: Vec<u8>,
    records: Vec<RetainedRecord>,
    stream: Stream,
    last_fact: u64,
    host: transcript::HostSlot,
}
enum Slot {
    Unissued(BrowserOpeningPosition),
    Issued {
        position: BrowserOpeningPosition,
        journal: Arc<Mutex<Journal>>,
    },
}
pub struct BrowserRowCollection {
    bounds: BrowserDocumentBounds,
    relation: BrowserLoanStamp,
    slots: Vec<Slot>,
}
pub struct BrowserRowProducer<'a> {
    collection: &'a mut BrowserRowCollection,
}
/// Single moved producer. Its cache is owned independently by the engine row.
/// Literal DATA in this cache does not attest a physical send, ACK or join.
pub struct BrowserDocumentProducer {
    journal: Arc<Mutex<Journal>>,
    decoder: BrowserDocumentDecoder,
    source: BrowserApplicationSource,
    relation: BrowserLoanStamp,
    bounds: BrowserDocumentBounds,
    opening: usize,
}
pub struct BrowserDocumentSnapshot<'a> {
    state: MutexGuard<'a, Journal>,
}
pub struct BrowserDocumentRecord<'a> {
    data: &'a BrowserDocumentFrameData,
    frame: &'a [u8],
}
impl BrowserDocumentRecord<'_> {
    pub fn data(&self) -> &BrowserDocumentFrameData {
        self.data
    }
    pub fn frame(&self) -> &[u8] {
        self.frame
    }
    pub fn payload(&self) -> &[u8] {
        &self.frame[16..]
    }
}
impl BrowserDocumentSnapshot<'_> {
    pub fn record_count(&self) -> usize {
        self.state.records.len()
    }
    pub fn record(&self, index: usize) -> Option<BrowserDocumentRecord<'_>> {
        let record = self.state.records.get(index)?;
        Some(BrowserDocumentRecord {
            data: &record.data,
            frame: self.state.raw.get(record.bytes.clone())?,
        })
    }
}
#[derive(Debug)]
pub struct BrowserRetainedDocumentFrame {
    kind: u8,
    sequence: u64,
}
impl BrowserRetainedDocumentFrame {
    pub fn kind(&self) -> u8 {
        self.kind
    }
    pub fn sequence(&self) -> u64 {
        self.sequence
    }
}
fn refuse(loans: &mut BrowserLoans<'_, '_>, fault: InstalledObservationFault) -> BrowserInputError {
    loans.fail_collection(fault)
}
fn funded_vec<T>(
    loans: &mut BrowserLoans<'_, '_>,
    count: usize,
) -> Result<Vec<T>, BrowserInputError> {
    let requested = count
        .checked_mul(size_of::<T>())
        .ok_or_else(|| refuse(loans, InstalledObservationFault::SizeOverflow))?;
    loans.reserve_controlled_host_storage(requested, count, requested)?;
    let mut result = Vec::new();
    result
        .try_reserve_exact(count)
        .map_err(|_| refuse(loans, InstalledObservationFault::Allocation))?;
    let extra = result
        .capacity()
        .checked_sub(count)
        .and_then(|n| n.checked_mul(size_of::<T>()))
        .ok_or_else(|| refuse(loans, InstalledObservationFault::LayoutMismatch))?;
    loans.reserve_controlled_host_storage(extra, 0, 0)?;
    Ok(result)
}
impl BrowserRowCollection {
    pub(super) fn prepare(
        run: &PreparedBrowserClientRun<'_, '_, '_, '_, '_, '_>,
        loans: &mut BrowserLoans<'_, '_>,
        bounds: BrowserDocumentBounds,
    ) -> Result<Self, BrowserInputError> {
        // Both traversals spend the SAME source input owners. There is no
        // caller-supplied action count, index or replacement collection.
        let count = run.openings(loans)?.count();
        // Prepay the engine's one return-boundary host-state inspection before
        // any callback can issue a host. Later readonly inspection grants no
        // effect and cannot repair this captured attempt classification.
        let terminal_work = count
            .checked_mul(size_of::<Slot>() + size_of::<transcript::HostSlot>())
            .ok_or_else(|| refuse(loans, InstalledObservationFault::SizeOverflow))?;
        loans.reserve_controlled_host_storage(0, 0, terminal_work)?;
        let mut slots = funded_vec(loans, count)?;
        for opening in run.openings(loans)? {
            slots.push(Slot::Unissued(run.validate_opening(&opening, loans)?));
        }
        loans.reserve_controlled_host_storage(size_of::<Self>(), 1, size_of::<Self>())?;
        Ok(Self {
            bounds,
            relation: loans.prepare_relation_stamp()?,
            slots,
        })
    }
    pub(super) fn producer(&mut self) -> BrowserRowProducer<'_> {
        BrowserRowProducer { collection: self }
    }
    pub fn document(&self, index: usize) -> Option<BrowserDocumentSnapshot<'_>> {
        let Slot::Issued { journal, .. } = self.slots.get(index)? else {
            return None;
        };
        Some(BrowserDocumentSnapshot {
            state: match journal.lock() {
                Ok(state) => state,
                Err(poison) => poison.into_inner(),
            },
        })
    }
    pub fn terminal(&self) -> BrowserCollectionTerminal {
        let (mut unissued, mut open, mut records, mut first) = (0, 0, 0, None);
        for slot in &self.slots {
            match slot {
                Slot::Unissued(_) => unissued += 1,
                Slot::Issued { journal, .. } => {
                    let state = match journal.lock() {
                        Ok(state) => state,
                        Err(poison) => {
                            let state = poison.into_inner();
                            first.get_or_insert(match state.stream {
                                Stream::Faulted(first) => first,
                                _ => BrowserCollectionFault::Poisoned,
                            });
                            state
                        }
                    };
                    records += state.records.len();
                    match state.stream {
                        Stream::Open => open += 1,
                        Stream::Ended => (),
                        Stream::Faulted(fault) => {
                            first.get_or_insert(fault);
                        }
                    }
                }
            }
        }
        if unissued == 0 && open == 0 && first.is_none() && !self.slots.is_empty() {
            BrowserCollectionTerminal::AllDocumentsEnded {
                documents: self.slots.len(),
                records,
            }
        } else {
            BrowserCollectionTerminal::Incomplete {
                unissued,
                open,
                first,
            }
        }
    }
}
impl BrowserRowProducer<'_> {
    pub fn issue<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>(
        &mut self,
        run: &PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        opening: &BrowserExecutionOpening<'_, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<BrowserDocumentProducer, BrowserInputError> {
        loans.validate_relation_stamp(&self.collection.relation)?;
        let position = run.validate_opening(opening, loans)?;
        let count = self.collection.slots.len();
        let visits = count
            .checked_mul(size_of::<usize>())
            .ok_or_else(|| refuse(loans, InstalledObservationFault::SizeOverflow))?;
        loans.reserve_controlled_host_storage(0, 0, visits)?;
        let slot = self
            .collection
            .slots
            .iter_mut()
            .find(|slot| match slot {
                Slot::Unissued(p) | Slot::Issued { position: p, .. } => *p == position,
            })
            .ok_or_else(|| inputs::BrowserInputFault::Source(BrowserSourceFault::ForeignSource))?;
        if !matches!(slot, Slot::Unissued(_)) {
            return Err(
                inputs::BrowserInputFault::Source(BrowserSourceFault::ForeignSource).into(),
            );
        }
        let bounds = self.collection.bounds;
        let raw = funded_vec(loans, bounds.journal_bytes)?;
        let records = funded_vec(loans, bounds.records)?;
        // Fund the concrete pinned Arc layout, endpoint and one strong clone.
        let arc = Layout::new::<AtomicUsize>()
            .extend(Layout::new::<AtomicUsize>())
            .and_then(|(header, _)| header.extend(Layout::new::<Mutex<Journal>>()))
            .map_err(|_| refuse(loans, InstalledObservationFault::SizeOverflow))?
            .0
            .pad_to_align()
            .size();
        let metadata = arc
            .checked_add(size_of::<BrowserDocumentProducer>())
            .ok_or_else(|| refuse(loans, InstalledObservationFault::SizeOverflow))?;
        let copies = bounds
            .journal_bytes
            .checked_add(
                bounds
                    .records
                    .checked_mul(size_of::<RetainedRecord>())
                    .ok_or_else(|| refuse(loans, InstalledObservationFault::SizeOverflow))?,
            )
            .and_then(|n| n.checked_add(metadata))
            .and_then(|n| n.checked_add(size_of::<AtomicUsize>()))
            .and_then(|n| n.checked_add(size_of::<Slot>()))
            .and_then(|n| {
                bounds
                    .records
                    .checked_mul(16)
                    .and_then(|header| n.checked_add(header))
            })
            .ok_or_else(|| refuse(loans, InstalledObservationFault::SizeOverflow))?;
        loans.reserve_controlled_host_storage(metadata, 2, copies)?;
        let source = loans.prepare_application_source()?;
        let decoder =
            loans.prepare_document_decoder(&source, bounds.records, bounds.frame_bytes)?;
        let relation = loans.prepare_relation_stamp()?;
        let journal = Arc::new(Mutex::new(Journal {
            raw,
            records,
            stream: Stream::Open,
            last_fact: 0,
            host: transcript::HostSlot::Unissued,
        }));
        let action = position.get();
        // Store the engine's owner before handing the only producer to native.
        *slot = Slot::Issued {
            position,
            journal: Arc::clone(&journal),
        };
        Ok(BrowserDocumentProducer {
            journal,
            decoder,
            source,
            relation,
            bounds,
            opening: action,
        })
    }
}
impl BrowserDocumentProducer {
    pub fn bounds(&self) -> BrowserDocumentBounds {
        self.bounds
    }
    pub fn validate_host(
        &self,
        loans: &BrowserLoans<'_, '_>,
        stimulus: &ControlledHostStimulus,
    ) -> Result<(), BrowserInputError> {
        loans.validate_relation_stamp(&self.relation)?;
        loans.validate_controlled_application(&self.source, stimulus)?;
        if stimulus.opening_action() != self.opening {
            return Err(
                inputs::BrowserInputFault::Source(BrowserSourceFault::ForeignSource).into(),
            );
        }
        Ok(())
    }
    pub fn record_frame(
        &mut self,
        loans: &mut BrowserLoans<'_, '_>,
        frame: &[u8],
        end: Instant,
    ) -> Result<BrowserRetainedDocumentFrame, BrowserCollectionFault> {
        // Foreign/stale callers cannot poison or spend the original collector.
        loans
            .validate_relation_stamp(&self.relation)
            .map_err(|cause| {
                if cause.source_cause().is_some() {
                    BrowserCollectionFault::Source
                } else {
                    BrowserCollectionFault::Funding
                }
            })?;
        {
            let journal = match self.journal.lock() {
                Ok(journal) => journal,
                Err(poison) => {
                    let journal = poison.into_inner();
                    return Err(match journal.stream {
                        Stream::Faulted(first) => first,
                        _ => BrowserCollectionFault::Poisoned,
                    });
                }
            };
            if let Stream::Faulted(first) = journal.stream {
                return Err(first);
            }
        }
        let result = (|| {
            if Instant::now() >= end {
                return Err(BrowserCollectionFault::End);
            }
            if frame.len() < 16
                || frame.len() > self.bounds.frame_bytes
                || frame[0] != 1
                || !matches!(frame[1], 1 | 2)
                || frame[2..4] != [0, 0]
            {
                return Err(BrowserCollectionFault::Framing);
            }
            let kind = frame[1];
            let sequence = u64::from_be_bytes(frame[4..12].try_into().unwrap());
            if u32::from_be_bytes(frame[12..16].try_into().unwrap()) as usize != frame.len() - 16 {
                return Err(BrowserCollectionFault::Framing);
            }
            {
                let journal = self
                    .journal
                    .lock()
                    .map_err(|_| BrowserCollectionFault::Poisoned)?;
                match journal.stream {
                    Stream::Open => (),
                    Stream::Ended => return Err(BrowserCollectionFault::Order),
                    Stream::Faulted(first) => return Err(first),
                }
                if journal.last_fact.checked_add(1) != Some(sequence) {
                    return Err(BrowserCollectionFault::Order);
                }
                if journal.records.len() >= self.bounds.records
                    || journal
                        .raw
                        .len()
                        .checked_add(frame.len())
                        .is_none_or(|n| n > self.bounds.journal_bytes)
                {
                    return Err(BrowserCollectionFault::Capacity);
                }
            }
            let data = loans
                .decode_document_frame_data(
                    &self.source,
                    &mut self.decoder,
                    kind,
                    sequence,
                    &frame[16..],
                    end,
                )
                .map_err(|error| BrowserCollectionFault::Decode(error.kind()))?;
            // No source-sensitive method is called under this gate. Validate
            // loans before entering; acquire source then journal at commit.
            self.relation
                .while_active(|| {
                    if Instant::now() >= end {
                        return Err(BrowserCollectionFault::End);
                    }
                    let mut journal = self
                        .journal
                        .lock()
                        .map_err(|_| BrowserCollectionFault::Poisoned)?;
                    let start = journal.raw.len();
                    let finish = start + frame.len();
                    journal.raw.extend_from_slice(frame);
                    journal.records.push(RetainedRecord {
                        data,
                        bytes: start..finish,
                    });
                    if kind == 1 {
                        journal.last_fact = sequence
                    } else {
                        journal.stream = Stream::Ended
                    }
                    Ok(BrowserRetainedDocumentFrame { kind, sequence })
                })
                .map_err(|_| BrowserCollectionFault::Source)?
        })();
        if let Err(fault) = result {
            self.refuse(fault);
        }
        result
    }
    pub fn refuse(&mut self, fault: BrowserCollectionFault) {
        match self.journal.lock() {
            Ok(mut journal) => {
                if !matches!(journal.stream, Stream::Faulted(_)) {
                    journal.stream = Stream::Faulted(fault)
                }
            }
            Err(poison) => {
                let mut journal = poison.into_inner();
                if !matches!(journal.stream, Stream::Faulted(_)) {
                    journal.stream = Stream::Faulted(BrowserCollectionFault::Poisoned)
                }
            }
        }
    }
}
impl Drop for BrowserDocumentProducer {
    fn drop(&mut self) {
        if let Ok(mut journal) = self.journal.lock() {
            if matches!(journal.stream, Stream::Open) {
                journal.stream = Stream::Faulted(BrowserCollectionFault::ProducerIncomplete)
            }
        }
    }
}
#[cfg(test)]
#[path = "collection/tests.rs"]
mod tests;
