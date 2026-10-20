//! Cumulative receiving permission only. No event recorder, source grant,
//! process, read, cleanup certificate, successful DATA or selected dispatch.
//! An eventual run coordinator must separately admit real RPC lengths on the
//! SAME CaptureBudget and use native::record_retention for zero-copy adoption.
use crate::transport::Limits;
use crate::workbench::configuration::InstalledObservationLimits;
use crate::workbench::model_originals::workflow::observation_check::CompareOwner;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstalledObservationResource {
    RetainedBytes,
    StdoutPrefixBytes,
    StderrPrefixBytes,
    SnapshotReadBytes,
    ByteVisits,
    Records,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstalledObservationFault {
    Resource {
        kind: InstalledObservationResource,
        limit: u64,
        used: u64,
        requested: u64,
    },
    SizeOverflow,
    LayoutMismatch,
    Allocation,
    Abandoned,
    PriorFault,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ObservationBufferRole {
    RpcRequest,
    RpcReply,
    StdoutPrefix,
    StderrPrefix,
    DestinationContent,
    ScratchContent,
    CensusMetadata,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ObservationRecordRole {
    Mailbox,
    Invocation,
    Process,
    AuthenticatedConnection,
    ReceivedFrame,
    SendAttempt,
    SendOutcome,
    ReadyOpportunity,
    SnapshotEntry,
}

/// Monotone permissions, including abandoned/failed attempts. These values
/// are not currently resident storage or a count of actual business effects.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct InstalledObservationUsage {
    retained_bytes: u64,
    stdout_prefix_bytes: u64,
    stderr_prefix_bytes: u64,
    snapshot_read_bytes: u64,
    byte_visits: u64,
    records: u64,
}
impl InstalledObservationUsage {
    pub fn retained_bytes(self) -> u64 {
        self.retained_bytes
    }
    pub fn stdout_prefix_bytes(self) -> u64 {
        self.stdout_prefix_bytes
    }
    pub fn stderr_prefix_bytes(self) -> u64 {
        self.stderr_prefix_bytes
    }
    pub fn snapshot_read_bytes(self) -> u64 {
        self.snapshot_read_bytes
    }
    pub fn byte_visits(self) -> u64 {
        self.byte_visits
    }
    pub fn records(self) -> u64 {
        self.records
    }
    fn amount(&self, resource: InstalledObservationResource) -> u64 {
        match resource {
            InstalledObservationResource::RetainedBytes => self.retained_bytes,
            InstalledObservationResource::StdoutPrefixBytes => self.stdout_prefix_bytes,
            InstalledObservationResource::StderrPrefixBytes => self.stderr_prefix_bytes,
            InstalledObservationResource::SnapshotReadBytes => self.snapshot_read_bytes,
            InstalledObservationResource::ByteVisits => self.byte_visits,
            InstalledObservationResource::Records => self.records,
        }
    }
    fn amount_mut(&mut self, resource: InstalledObservationResource) -> &mut u64 {
        match resource {
            InstalledObservationResource::RetainedBytes => &mut self.retained_bytes,
            InstalledObservationResource::StdoutPrefixBytes => &mut self.stdout_prefix_bytes,
            InstalledObservationResource::StderrPrefixBytes => &mut self.stderr_prefix_bytes,
            InstalledObservationResource::SnapshotReadBytes => &mut self.snapshot_read_bytes,
            InstalledObservationResource::ByteVisits => &mut self.byte_visits,
            InstalledObservationResource::Records => &mut self.records,
        }
    }
}

/// Construct once outside the selected preparation/case/command loops. No
/// Clone or reset/refund API. Issued tickets borrow this same actual owner.
pub(in crate::workbench::model_originals::workflow::pipeline) struct InstalledObservationOwner {
    limits: InstalledObservationUsage,
    usage: InstalledObservationUsage,
    fault: Option<InstalledObservationFault>,
}
impl InstalledObservationOwner {
    pub(in crate::workbench::model_originals::workflow::pipeline) fn new(
        limits: &InstalledObservationLimits,
    ) -> Self {
        Self {
            limits: InstalledObservationUsage {
                retained_bytes: limits.retained_bytes(),
                stdout_prefix_bytes: limits.stdout_prefix_bytes(),
                stderr_prefix_bytes: limits.stderr_prefix_bytes(),
                snapshot_read_bytes: limits.snapshot_read_bytes(),
                byte_visits: limits.byte_visits(),
                records: limits.records(),
            },
            usage: InstalledObservationUsage::default(),
            fault: None,
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline) fn ready(
        &self,
    ) -> Result<(), &InstalledObservationFault> {
        self.fault.as_ref().map_or(Ok(()), Err)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline) fn usage(
        &self,
    ) -> InstalledObservationUsage {
        self.usage
    }
    pub(super) fn fail(&mut self, fault: InstalledObservationFault) -> &InstalledObservationFault {
        self.fault.get_or_insert(fault)
    }
    pub(super) fn refuse_prior_fault(&mut self) -> &InstalledObservationFault {
        self.fail(InstalledObservationFault::PriorFault)
    }
    fn reserve(
        &mut self,
        kind: InstalledObservationResource,
        requested: u64,
    ) -> Result<(), InstalledObservationFault> {
        if let Some(fault) = self.fault {
            return Err(fault);
        }
        let used = self.usage.amount(kind);
        let limit = self.limits.amount(kind);
        let next = match used.checked_add(requested) {
            Some(next) => next,
            None => return Err(*self.fail(InstalledObservationFault::SizeOverflow)),
        };
        if next > limit {
            return Err(*self.fail(InstalledObservationFault::Resource {
                kind,
                limit,
                used,
                requested,
            }));
        }
        *self.usage.amount_mut(kind) = next;
        Ok(())
    }
    fn reserve_span(
        &mut self,
        kind: InstalledObservationResource,
        requested: usize,
    ) -> Result<(), InstalledObservationFault> {
        // A prior fault wins even over a later size-conversion failure.
        if let Some(fault) = self.fault {
            return Err(fault);
        }
        let requested = match u64::try_from(requested) {
            Ok(requested) => requested,
            Err(_) => return Err(*self.fail(InstalledObservationFault::SizeOverflow)),
        };
        self.reserve(kind, requested)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline) fn reserve_process_prefixes(
        &mut self,
        actual: &Limits,
    ) -> Result<ProcessPrefixReservation<'_>, &InstalledObservationFault> {
        if let Err(fault) = self.reserve_span(
            InstalledObservationResource::StdoutPrefixBytes,
            actual.max_frame,
        ) {
            return Err(self.fail(fault));
        }
        if let Err(fault) = self.reserve_span(
            InstalledObservationResource::StderrPrefixBytes,
            actual.stderr_capture,
        ) {
            return Err(self.fail(fault));
        }
        Ok(ProcessPrefixReservation { owner: Some(self) })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline) fn prepare_snapshot_read(
        &mut self,
        requested: usize,
    ) -> Result<SnapshotReadPermission<'_>, &InstalledObservationFault> {
        if let Err(fault) =
            self.reserve_span(InstalledObservationResource::SnapshotReadBytes, requested)
        {
            return Err(self.fail(fault));
        }
        Ok(SnapshotReadPermission {
            owner: Some(self),
            requested,
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline) fn prepare_record(
        &mut self,
        role: ObservationRecordRole,
    ) -> Result<RecordIssuePermission<'_>, &InstalledObservationFault> {
        if let Err(fault) = self.reserve(InstalledObservationResource::Records, 1) {
            return Err(self.fail(fault));
        }
        Ok(RecordIssuePermission {
            owner: Some(self),
            role,
        })
    }
}

/// This is permission to request the already-reserved prefixes, not evidence
/// of a spawn or any output. The actual process binding remains pending.
pub struct ProcessPrefixReservation<'a> {
    owner: Option<&'a mut InstalledObservationOwner>,
}
impl ProcessPrefixReservation<'_> {
    pub fn commit(mut self) {
        self.owner.take();
    }
}
impl Drop for ProcessPrefixReservation<'_> {
    fn drop(&mut self) {
        if let Some(owner) = self.owner.take() {
            owner.fail(InstalledObservationFault::Abandoned);
        }
    }
}
pub struct SnapshotReadPermission<'a> {
    owner: Option<&'a mut InstalledObservationOwner>,
    requested: usize,
}
impl<'a> SnapshotReadPermission<'a> {
    pub fn finish(mut self, actual_returned: usize) -> Result<(), &'a InstalledObservationFault> {
        let owner = self.owner.take().expect("single-use read permission");
        if let Some(fault) = owner.fault {
            return Err(owner.fail(fault));
        }
        if actual_returned > self.requested {
            return Err(owner.fail(InstalledObservationFault::LayoutMismatch));
        }
        Ok(())
    }
}
impl Drop for SnapshotReadPermission<'_> {
    fn drop(&mut self) {
        if let Some(owner) = self.owner.take() {
            owner.fail(InstalledObservationFault::Abandoned);
        }
    }
}
/// An issued fixed record permission, not a connection/invocation/source ID.
pub(in crate::workbench::model_originals::workflow::pipeline) struct ReservedObservationRecord {
    role: ObservationRecordRole,
}
pub(in crate::workbench::model_originals::workflow::pipeline) struct RecordIssuePermission<'a> {
    owner: Option<&'a mut InstalledObservationOwner>,
    role: ObservationRecordRole,
}
impl RecordIssuePermission<'_> {
    pub(in crate::workbench::model_originals::workflow::pipeline) fn issue(
        mut self,
    ) -> ReservedObservationRecord {
        self.owner.take();
        ReservedObservationRecord { role: self.role }
    }
}
impl Drop for RecordIssuePermission<'_> {
    fn drop(&mut self) {
        if let Some(owner) = self.owner.take() {
            owner.fail(InstalledObservationFault::Abandoned);
        }
    }
}

enum CopySource<'source> {
    Bytes(&'source [u8]),
    Text(&'source str),
}
impl CopySource<'_> {
    fn len(&self) -> usize {
        match self {
            Self::Bytes(bytes) => bytes.len(),
            Self::Text(text) => text.len(),
        }
    }
}
struct CopyReservation<'owner, 'bytes> {
    owner: &'owner mut InstalledObservationOwner,
    comparison: &'owner mut CompareOwner,
    source: CopySource<'bytes>,
    role: ObservationBufferRole,
}
pub(in crate::workbench::model_originals::workflow::pipeline) struct ObservationCopy<'owner, 'bytes>
{
    pending: Option<CopyReservation<'owner, 'bytes>>,
}
pub struct RetainedObservationBytes {
    bytes: Vec<u8>,
    role: ObservationBufferRole,
}
/// A receiver-budgeted copy of already valid text. Borrowing its text performs
/// no decoding and grants no source or host authority.
pub struct RetainedObservationText {
    text: String,
}
impl RetainedObservationText {
    pub fn as_str(&self) -> &str {
        &self.text
    }
}
impl RetainedObservationBytes {
    pub fn as_bytes(&self) -> &[u8] {
        &self.bytes
    }
    pub(in crate::workbench::model_originals::workflow::pipeline) fn capacity(&self) -> usize {
        self.bytes.capacity()
    }
}
/// Receiving storage only. The future coordinator must admit actual RPC
/// request/reply lengths on its SAME CaptureBudget BEFORE calling this for
/// RPC roles; no capture permission or source authority is inferred here.
pub(in crate::workbench::model_originals::workflow::pipeline) fn prepare_copy<'owner, 'bytes>(
    owner: &'owner mut InstalledObservationOwner,
    comparison: &'owner mut CompareOwner,
    role: ObservationBufferRole,
    source: &'bytes [u8],
) -> Result<ObservationCopy<'owner, 'bytes>, &'owner InstalledObservationFault> {
    prepare_source(owner, comparison, role, CopySource::Bytes(source))
}
pub(in crate::workbench::model_originals::workflow::pipeline) fn prepare_text_copy<
    'owner,
    'text,
>(
    owner: &'owner mut InstalledObservationOwner,
    comparison: &'owner mut CompareOwner,
    role: ObservationBufferRole,
    source: &'text str,
) -> Result<ObservationCopy<'owner, 'text>, &'owner InstalledObservationFault> {
    prepare_source(owner, comparison, role, CopySource::Text(source))
}
fn prepare_source<'owner, 'source>(
    owner: &'owner mut InstalledObservationOwner,
    comparison: &'owner mut CompareOwner,
    role: ObservationBufferRole,
    source: CopySource<'source>,
) -> Result<ObservationCopy<'owner, 'source>, &'owner InstalledObservationFault> {
    if let Some(fault) = owner.fault {
        return Err(owner.fail(fault));
    }
    if comparison.ready().is_err() {
        return Err(owner.fail(InstalledObservationFault::PriorFault));
    }
    if let Err(fault) =
        owner.reserve_span(InstalledObservationResource::RetainedBytes, source.len())
    {
        return Err(owner.fail(fault));
    }
    if let Err(fault) = owner.reserve_span(InstalledObservationResource::ByteVisits, source.len()) {
        return Err(owner.fail(fault));
    }
    Ok(ObservationCopy {
        pending: Some(CopyReservation {
            owner,
            comparison,
            source,
            role,
        }),
    })
}
impl<'owner> ObservationCopy<'owner, '_> {
    pub(in crate::workbench::model_originals::workflow::pipeline) fn retain(
        mut self,
    ) -> Result<RetainedObservationBytes, &'owner InstalledObservationFault> {
        // Disarm Drop before any refusal. Successful and failed reservations
        // remain monotone, including actual empty allocation spare capacity.
        let CopyReservation {
            owner,
            comparison,
            source,
            role,
        } = self.pending.take().expect("single-use copy permission");
        if let Some(fault) = owner.fault {
            return Err(owner.fail(fault));
        }
        if comparison.ready().is_err() {
            return Err(owner.fail(InstalledObservationFault::PriorFault));
        }
        let CopySource::Bytes(source) = source else {
            return Err(owner.fail(InstalledObservationFault::LayoutMismatch));
        };
        let mut bytes = Vec::new();
        if bytes.try_reserve_exact(source.len()).is_err() {
            return Err(owner.fail(InstalledObservationFault::Allocation));
        }
        if let Err(fault) = charge_copy_capacity(owner, source.len(), bytes.capacity()) {
            // bytes is still empty. Drop it without performing the copy.
            return Err(owner.fail(fault));
        }
        // Capacity and this exact span's visit permission are already held.
        bytes.extend_from_slice(source);
        Ok(RetainedObservationBytes { bytes, role })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline) fn retain_text(
        mut self,
    ) -> Result<RetainedObservationText, &'owner InstalledObservationFault> {
        let CopyReservation {
            owner,
            comparison,
            source,
            ..
        } = self.pending.take().expect("single-use copy permission");
        if let Some(fault) = owner.fault {
            return Err(owner.fail(fault));
        }
        if comparison.ready().is_err() {
            return Err(owner.fail(InstalledObservationFault::PriorFault));
        }
        let CopySource::Text(source) = source else {
            return Err(owner.fail(InstalledObservationFault::LayoutMismatch));
        };
        let mut text = String::new();
        if text.try_reserve_exact(source.len()).is_err() {
            return Err(owner.fail(InstalledObservationFault::Allocation));
        }
        if let Err(fault) = charge_copy_capacity(owner, source.len(), text.capacity()) {
            return Err(owner.fail(fault));
        }
        // The same copy span and actual capacity are precharged. push_str
        // copies this genuine &str without rescanning UTF8 validity.
        text.push_str(source);
        Ok(RetainedObservationText { text })
    }
}
fn charge_copy_capacity(
    owner: &mut InstalledObservationOwner,
    requested: usize,
    capacity: usize,
) -> Result<(), InstalledObservationFault> {
    let Some(excess) = capacity.checked_sub(requested) else {
        return Err(*owner.fail(InstalledObservationFault::LayoutMismatch));
    };
    owner.reserve_span(InstalledObservationResource::RetainedBytes, excess)
}
impl Drop for ObservationCopy<'_, '_> {
    fn drop(&mut self) {
        if let Some(pending) = self.pending.take() {
            pending.owner.fail(InstalledObservationFault::Abandoned);
        }
    }
}
