//! Caller-funded archive DATA only. No browser execution or action/source grant.
//! The eventual adapter must separately fund chunks and report real artifact EOF.
use crate::workbench::model_originals::workflow::{
    decode::{DecodeError, Decoder},
    observation_check::{
        CompareOwner, ObservationError,
        archive::{EntrySlot, ZipStoreFault},
    },
    pipeline::installed::observation::{
        InstalledObservationFault, InstalledObservationOwner, InstalledObservationResource,
        ObservationBufferRole,
    },
};
use std::alloc::Layout;

#[derive(Debug, Clone, PartialEq, Eq)]
enum ArchiveCollectionFault {
    Decode(DecodeError),
    Receiving(InstalledObservationFault),
    Comparison(ObservationError),
    SizeOverflow,
    Allocation,
    Overrun {
        limit: usize,
        retained: usize,
        incoming: usize,
    },
    Incomplete,
    Reader(ZipStoreFault),
}
enum ArchiveStreamEnd {
    Eof,
    Incomplete,
}
/// Validated preparation dimensions. Counters are not retained after allocation.
struct Dimensions {
    raw: usize,
    entries: usize,
    entry_bytes: usize,
    slots: usize,
}
impl Dimensions {
    fn checked(raw: usize, entries: usize) -> Result<Self, ArchiveCollectionFault> {
        let entry_bytes = entries
            .checked_mul(std::mem::size_of::<EntrySlot<'static>>())
            .ok_or(ArchiveCollectionFault::SizeOverflow)?;
        let slots = entries
            .checked_add(2)
            .ok_or(ArchiveCollectionFault::SizeOverflow)?;
        Layout::array::<u8>(raw).map_err(|_| ArchiveCollectionFault::SizeOverflow)?;
        Layout::array::<EntrySlot<'static>>(entries)
            .map_err(|_| ArchiveCollectionFault::SizeOverflow)?;
        Ok(Self {
            raw,
            entries,
            entry_bytes,
            slots,
        })
    }
}
/// These are loans of existing cumulative domains, not fresh permissions.
struct Owners<'a> {
    decode: &'a mut Decoder,
    receiving: &'a mut InstalledObservationOwner,
    comparison: &'a mut CompareOwner,
}
impl Owners<'_> {
    fn ready(&self) -> Result<(), ArchiveCollectionFault> {
        self.decode
            .ready()
            .map_err(ArchiveCollectionFault::Decode)?;
        self.receiving
            .ready()
            .map_err(|f| ArchiveCollectionFault::Receiving(*f))?;
        self.comparison
            .ready()
            .map_err(ArchiveCollectionFault::Comparison)
    }
    #[cfg(test)]
    fn usage(&self) -> Usage {
        (
            self.decode.usage(),
            self.receiving.usage(),
            self.comparison.usage(),
        )
    }
    fn latch(&mut self, fault: &ArchiveCollectionFault) {
        let cause = match fault {
            ArchiveCollectionFault::Receiving(fault) => *fault,
            ArchiveCollectionFault::SizeOverflow => InstalledObservationFault::SizeOverflow,
            ArchiveCollectionFault::Allocation => InstalledObservationFault::Allocation,
            ArchiveCollectionFault::Incomplete => InstalledObservationFault::Abandoned,
            ArchiveCollectionFault::Overrun { .. } | ArchiveCollectionFault::Reader(_) => {
                InstalledObservationFault::LayoutMismatch
            }
            ArchiveCollectionFault::Decode(_) | ArchiveCollectionFault::Comparison(_) => {
                InstalledObservationFault::PriorFault
            }
        };
        self.receiving.fail(cause);
    }
    fn reserve(
        &mut self,
        kind: InstalledObservationResource,
        bytes: usize,
    ) -> Result<(), ArchiveCollectionFault> {
        self.receiving
            .reserve_span(kind, bytes)
            .map_err(ArchiveCollectionFault::Receiving)
    }
    fn backing(
        &mut self,
        role: ObservationBufferRole,
        bytes: usize,
    ) -> Result<(), ArchiveCollectionFault> {
        match role {
            ObservationBufferRole::ArchiveContent | ObservationBufferRole::ArchiveEntryMetadata => {
                self.reserve(InstalledObservationResource::RetainedBytes, bytes)
            }
            _ => Err(ArchiveCollectionFault::Receiving(
                InstalledObservationFault::LayoutMismatch,
            )),
        }
    }
    fn copy_work(&mut self, bytes: usize) -> Result<(), ArchiveCollectionFault> {
        self.reserve(InstalledObservationResource::ByteVisits, bytes)?;
        self.decode
            .bytes(bytes)
            .map_err(ArchiveCollectionFault::Decode)
    }
}
// Scratch is vacant until the consuming callback; no self-reference is stored.
struct Buffers {
    // Length is the immutable requested entry bound; callers only get a slice.
    scratch: Vec<EntrySlot<'static>>,
    raw: Vec<u8>,
    raw_limit: usize,
}
struct Parts<'a> {
    buffers: Buffers,
    owners: Owners<'a>,
}
enum CollectionState<'a> {
    Collecting(Parts<'a>),
    Refused {
        parts: Parts<'a>,
        fault: ArchiveCollectionFault,
    },
    Transferred,
}
struct ArchiveByteCollection<'a> {
    state: CollectionState<'a>,
}
struct CollectedArchiveBytes<'a> {
    parts: Parts<'a>,
}
struct RejectedArchiveBytes<'a> {
    parts: Parts<'a>,
    fault: ArchiveCollectionFault,
}
struct RetainedArchiveBytes<'a> {
    raw: Vec<u8>,
    owners: Owners<'a>,
}
enum ArchiveFormatOutcome<'a, R> {
    Parsed {
        raw: RetainedArchiveBytes<'a>,
        value: R,
    },
    Refused {
        raw: RetainedArchiveBytes<'a>,
        fault: ArchiveCollectionFault,
    },
}

impl<'a> ArchiveByteCollection<'a> {
    fn prepare(
        decode: &'a mut Decoder,
        receiving: &'a mut InstalledObservationOwner,
        comparison: &'a mut CompareOwner,
        raw_capacity: usize,
        entry_capacity: usize,
    ) -> Result<Self, ArchiveCollectionFault> {
        let mut owners = Owners {
            decode,
            receiving,
            comparison,
        };
        let allocation = (|| {
            owners.ready()?;
            let dimensions = Dimensions::checked(raw_capacity, entry_capacity)?;
            owners
                .decode
                .slots(dimensions.slots)
                .map_err(ArchiveCollectionFault::Decode)?;
            owners.backing(ObservationBufferRole::ArchiveContent, dimensions.raw)?;
            owners.backing(
                ObservationBufferRole::ArchiveEntryMetadata,
                dimensions.entry_bytes,
            )?;
            owners.copy_work(dimensions.entry_bytes)?;
            let mut raw = Vec::new();
            raw.try_reserve_exact(dimensions.raw)
                .map_err(|_| ArchiveCollectionFault::Allocation)?;
            let raw_excess = raw.capacity().checked_sub(dimensions.raw).ok_or(
                ArchiveCollectionFault::Receiving(InstalledObservationFault::LayoutMismatch),
            )?;
            owners.backing(ObservationBufferRole::ArchiveContent, raw_excess)?;
            let mut scratch = Vec::new();
            scratch
                .try_reserve_exact(dimensions.entries)
                .map_err(|_| ArchiveCollectionFault::Allocation)?;
            let extra_entries = scratch.capacity().checked_sub(dimensions.entries).ok_or(
                ArchiveCollectionFault::Receiving(InstalledObservationFault::LayoutMismatch),
            )?;
            let extra_bytes = extra_entries
                .checked_mul(std::mem::size_of::<EntrySlot<'static>>())
                .ok_or(ArchiveCollectionFault::SizeOverflow)?;
            owners.backing(ObservationBufferRole::ArchiveEntryMetadata, extra_bytes)?;
            // Both requested allocations and actual spare are now paid. Only
            // requested logical entries are initialized; no spare becomes usable.
            for _ in 0..dimensions.entries {
                scratch.push(EntrySlot::vacant());
            }
            Ok(Buffers {
                raw,
                scratch,
                raw_limit: dimensions.raw,
            })
        })();
        match allocation {
            Ok(buffers) => Ok(Self {
                state: CollectionState::Collecting(Parts { buffers, owners }),
            }),
            Err(fault) => {
                owners.latch(&fault);
                Err(fault)
            }
        }
    }
    fn append(&mut self, actual: &[u8]) -> Result<(), ArchiveCollectionFault> {
        let result = match &mut self.state {
            CollectionState::Refused { fault, .. } => return Err(fault.clone()),
            CollectionState::Transferred => unreachable!("private consumed collection"),
            CollectionState::Collecting(parts) => (|| {
                parts.owners.ready()?;
                let retained = parts.buffers.raw.len();
                let next = retained
                    .checked_add(actual.len())
                    .ok_or(ArchiveCollectionFault::SizeOverflow)?;
                let limit = parts.buffers.raw_limit;
                if next > limit {
                    return Err(ArchiveCollectionFault::Overrun {
                        limit,
                        retained,
                        incoming: actual.len(),
                    });
                }
                parts.owners.copy_work(actual.len())?;
                parts.buffers.raw.extend_from_slice(actual);
                Ok(())
            })(),
        };
        if let Err(fault) = &result {
            let CollectionState::Collecting(mut parts) =
                std::mem::replace(&mut self.state, CollectionState::Transferred)
            else {
                unreachable!()
            };
            parts.owners.latch(fault);
            self.state = CollectionState::Refused {
                parts,
                fault: fault.clone(),
            };
        }
        result
    }
    fn end(
        mut self,
        end: ArchiveStreamEnd,
    ) -> Result<CollectedArchiveBytes<'a>, RejectedArchiveBytes<'a>> {
        match std::mem::replace(&mut self.state, CollectionState::Transferred) {
            CollectionState::Refused { parts, fault } => Err(RejectedArchiveBytes { parts, fault }),
            CollectionState::Collecting(mut parts) => {
                let fault = match parts.owners.ready() {
                    Err(fault) => Some(fault),
                    Ok(()) => match end {
                        ArchiveStreamEnd::Eof => None,
                        ArchiveStreamEnd::Incomplete => Some(ArchiveCollectionFault::Incomplete),
                    },
                };
                match fault {
                    Some(fault) => {
                        parts.owners.latch(&fault);
                        Err(RejectedArchiveBytes { parts, fault })
                    }
                    None => Ok(CollectedArchiveBytes { parts }),
                }
            }
            CollectionState::Transferred => unreachable!("private consumed collection"),
        }
    }
    #[cfg(test)]
    fn test_storage(&self) -> ArchiveStorageSnapshot {
        match &self.state {
            CollectionState::Collecting(parts) | CollectionState::Refused { parts, .. } => {
                parts.buffers.snapshot()
            }
            CollectionState::Transferred => unreachable!(),
        }
    }
    #[cfg(test)]
    fn test_usage(&self) -> Usage {
        match &self.state {
            CollectionState::Collecting(parts) | CollectionState::Refused { parts, .. } => {
                parts.owners.usage()
            }
            CollectionState::Transferred => unreachable!(),
        }
    }
}
impl Drop for ArchiveByteCollection<'_> {
    fn drop(&mut self) {
        if let CollectionState::Collecting(parts) = &mut self.state {
            parts
                .owners
                .receiving
                .fail(InstalledObservationFault::Abandoned);
        }
    }
}
impl<'a> CollectedArchiveBytes<'a> {
    fn with_format<R>(
        self,
        f: impl for<'bytes, 'scratch> FnOnce(
            &'bytes [u8],
            &'scratch mut [EntrySlot<'bytes>],
            &mut CompareOwner,
        ) -> Result<R, ZipStoreFault>,
    ) -> ArchiveFormatOutcome<'a, R> {
        let Parts {
            buffers,
            mut owners,
        } = self.parts;
        let Buffers { raw, scratch, .. } = buffers;
        let result = match owners.ready() {
            Err(fault) => {
                drop(scratch);
                Err(fault)
            }
            Ok(()) => {
                fn shorten<'bytes>(
                    _: &'bytes [u8],
                    slots: Vec<EntrySlot<'static>>,
                ) -> Vec<EntrySlot<'bytes>> {
                    slots
                }
                let result = {
                    let mut scratch = shorten(&raw, scratch);
                    let result = f(&raw, &mut scratch, owners.comparison);
                    drop(scratch);
                    result
                };
                result.map_err(ArchiveCollectionFault::Reader)
            }
        };
        match result {
            Ok(value) => ArchiveFormatOutcome::Parsed {
                raw: RetainedArchiveBytes { raw, owners },
                value,
            },
            Err(fault) => {
                owners.latch(&fault);
                ArchiveFormatOutcome::Refused {
                    raw: RetainedArchiveBytes { raw, owners },
                    fault,
                }
            }
        }
    }
    fn dispose(self) {
        drop(self);
    }
}
impl RejectedArchiveBytes<'_> {
    fn fault(&self) -> &ArchiveCollectionFault {
        &self.fault
    }
    fn dispose(self) {
        drop(self);
    }
    #[cfg(test)]
    fn test_storage(&self) -> ArchiveStorageSnapshot {
        self.parts.buffers.snapshot()
    }
    #[cfg(test)]
    fn test_usage(&self) -> Usage {
        self.parts.owners.usage()
    }
}
impl RetainedArchiveBytes<'_> {
    fn as_bytes(&self) -> &[u8] {
        &self.raw
    }
    fn dispose(self) {
        drop(self);
    }
    #[cfg(test)]
    fn test_raw_capacity(&self) -> usize {
        self.raw.capacity()
    }
    #[cfg(test)]
    fn test_usage(&self) -> Usage {
        self.owners.usage()
    }
}

#[cfg(test)]
type Usage = (
    crate::workbench::model_originals::workflow::decode::DecodeUsage,
    crate::workbench::model_originals::workflow::pipeline::installed::observation::InstalledObservationUsage,
    crate::workbench::model_originals::workflow::observation_check::CompareUsage,
);
#[cfg(test)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ArchiveStorageSnapshot {
    raw_length: usize,
    raw_capacity: usize,
    entry_length: usize,
    entry_capacity: usize,
}
#[cfg(test)]
impl Buffers {
    fn snapshot(&self) -> ArchiveStorageSnapshot {
        ArchiveStorageSnapshot {
            raw_length: self.raw.len(),
            raw_capacity: self.raw.capacity(),
            entry_length: self.scratch.len(),
            entry_capacity: self.scratch.capacity(),
        }
    }
}
#[cfg(test)]
mod tests;
