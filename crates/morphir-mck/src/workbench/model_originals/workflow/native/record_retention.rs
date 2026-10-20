//! Cumulative capacity permission for native private-record ownership transfer.
//! This is not a source grant, live host proof, worker credit or RSS meter.
use super::super::decode::Text;
use super::super::input::Bytes;
use super::super::observation_check::CompareOwner;
use super::RecordRetentionLimits;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PrivateRecordError {
    Capacity {
        limit: u64,
        used: u64,
        requested: u64,
    },
    SizeOverflow,
    LengthMismatch {
        expected: usize,
        actual: usize,
    },
    CapacityMismatch {
        expected: usize,
        actual: usize,
    },
    AllocationMismatch,
    InvalidUtf8,
    UnsupportedRepresentation,
    Abandoned,
    PriorWorkFault,
}

/// Monotone reserved capacities, including failed/abandoned permissions.
/// It is deliberately distinct from currently resident or host-owned bytes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RecordRetentionUsage {
    reserved_bytes: u64,
}
impl RecordRetentionUsage {
    pub fn reserved_bytes(self) -> u64 {
        self.reserved_bytes
    }
}

pub(super) fn checked_reservation(
    used: u64,
    capacity: u64,
    limit: u64,
) -> Result<u64, PrivateRecordError> {
    let next = used
        .checked_add(capacity)
        .ok_or(PrivateRecordError::SizeOverflow)?;
    if next > limit {
        return Err(PrivateRecordError::Capacity {
            limit,
            used,
            requested: capacity,
        });
    }
    Ok(next)
}

pub(in crate::workbench::model_originals::workflow) struct RecordRetentionOwner {
    limit: u64,
    reserved: u64,
    fault: Option<PrivateRecordError>,
}
impl RecordRetentionOwner {
    pub(in crate::workbench::model_originals::workflow) fn new(
        limits: &RecordRetentionLimits,
    ) -> Self {
        Self {
            limit: limits.retained_bytes(),
            reserved: 0,
            fault: None,
        }
    }
    pub(in crate::workbench::model_originals::workflow) fn ready(
        &self,
    ) -> Result<(), &PrivateRecordError> {
        self.fault.as_ref().map_or(Ok(()), Err)
    }
    pub(super) fn usage(&self) -> RecordRetentionUsage {
        RecordRetentionUsage {
            reserved_bytes: self.reserved,
        }
    }
    fn fail(&mut self, error: PrivateRecordError) -> &PrivateRecordError {
        self.fault.get_or_insert(error)
    }
}

#[derive(Clone, Copy)]
struct BufferLayout {
    length: usize,
    capacity: usize,
    address: usize,
}
impl BufferLayout {
    fn inspect(actual: &Vec<u8>) -> Self {
        Self {
            length: actual.len(),
            capacity: actual.capacity(),
            address: actual.as_ptr().addr(),
        }
    }
    fn validate(self, actual: &Vec<u8>) -> Result<(), PrivateRecordError> {
        if actual.len() != self.length {
            return Err(PrivateRecordError::LengthMismatch {
                expected: self.length,
                actual: actual.len(),
            });
        }
        if actual.capacity() != self.capacity {
            return Err(PrivateRecordError::CapacityMismatch {
                expected: self.capacity,
                actual: actual.capacity(),
            });
        }
        if self.capacity != 0 && actual.as_ptr().addr() != self.address {
            return Err(PrivateRecordError::AllocationMismatch);
        }
        Ok(())
    }
}
struct Reservation<'owner> {
    owner: &'owner mut RecordRetentionOwner,
    comparison: &'owner mut CompareOwner,
    layout: BufferLayout,
}
/// Single-use transfer permission. It retains no borrow of the source Vec.
/// Layout/address checks establish permission continuity only while the caller
/// retains the original allocation. They cannot distinguish address reuse/ABA.
/// The genuine parent's opaque lease preserves that lifetime; this ticket
/// supplies neither allocation provenance nor native-host authority by itself.
pub struct PrivateRecordAdoption<'owner> {
    pending: Option<Reservation<'owner>>,
}

pub(super) fn prepare<'owner>(
    owner: &'owner mut RecordRetentionOwner,
    comparison: &'owner mut CompareOwner,
    actual: &Vec<u8>,
) -> Result<PrivateRecordAdoption<'owner>, &'owner PrivateRecordError> {
    if let Some(error) = owner.fault {
        return Err(owner.fail(error));
    }
    if comparison.ready().is_err() {
        return Err(owner.fail(PrivateRecordError::PriorWorkFault));
    }
    let layout = BufferLayout::inspect(actual);
    let capacity = match u64::try_from(layout.capacity) {
        Ok(value) => value,
        Err(_) => return Err(owner.fail(PrivateRecordError::SizeOverflow)),
    };
    let next = match checked_reservation(owner.reserved, capacity, owner.limit) {
        Ok(value) => value,
        Err(error) => return Err(owner.fail(error)),
    };
    // No scan, allocation, callback or source take occurs between permission
    // validation and this monotone reservation. There is never a refund.
    owner.reserved = next;
    Ok(PrivateRecordAdoption {
        pending: Some(Reservation {
            owner,
            comparison,
            layout,
        }),
    })
}
impl<'owner> PrivateRecordAdoption<'owner> {
    pub fn usage(&self) -> RecordRetentionUsage {
        self.pending
            .as_ref()
            .expect("unconsumed ticket owns reservation")
            .owner
            .usage()
    }
    pub fn cancel(self) {
        drop(self)
    }
    pub fn commit(mut self, actual: Vec<u8>) -> Result<Bytes, &'owner PrivateRecordError> {
        // Taking the closed pending state disarms Drop before any error branch.
        // Parent retains its real WorkPermit until this method has returned.
        let Reservation {
            owner,
            comparison,
            layout,
        } = self
            .pending
            .take()
            .expect("single-use ticket owns reservation");
        if let Some(error) = owner.fault {
            drop(actual);
            return Err(owner.fail(error));
        }
        if comparison.ready().is_err() {
            drop(actual);
            return Err(owner.fail(PrivateRecordError::PriorWorkFault));
        }
        if let Err(error) = layout.validate(&actual) {
            drop(actual);
            return Err(owner.fail(error));
        }
        // UTF8 validation and existing character-count validation are separate
        // logical span visits. Charge both on the actual comparison owner
        // before either traversal; this is work, not resident storage credit.
        if comparison.preflight_owned_text(actual.len()).is_err() {
            drop(actual);
            return Err(owner.fail(PrivateRecordError::PriorWorkFault));
        }
        let text = match String::from_utf8(actual) {
            Ok(text) => text,
            Err(error) => {
                drop(error);
                return Err(owner.fail(PrivateRecordError::InvalidUtf8));
            }
        };
        // String::from_utf8 moves the Vec allocation, including spare capacity.
        // The same validator below never reserves, copies or shrinks it.
        let text = match Text::<0, 1_048_576>::from_owned(text) {
            Ok(text) => text,
            Err(_) => return Err(owner.fail(PrivateRecordError::UnsupportedRepresentation)),
        };
        Ok(Bytes::Utf8 { text })
    }
}
impl Drop for PrivateRecordAdoption<'_> {
    fn drop(&mut self) {
        if let Some(reservation) = self.pending.take() {
            reservation.owner.fail(PrivateRecordError::Abandoned);
        }
    }
}
