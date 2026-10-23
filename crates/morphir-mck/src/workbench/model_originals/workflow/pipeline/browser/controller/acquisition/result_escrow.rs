//! Private opt-in native observation funding, unwired to Page/driver exchange.
//! Cumulative permissions are distinct from performed work and live backing.
//! Literal ReadWork, records/reads and comparison remain separate owners.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::browser::adapter::{
    BrowserActivityFault,
    execution_loans::{BrowserActionIssueError, SourceBusinessOrigin, SourceResultPlan},
};
use std::sync::{Arc, Mutex, MutexGuard};

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceResultResources
{
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) retained_bytes: usize,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) receiving_visits: usize,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) decode_visits: usize,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) decode_slots: usize,
}
impl SourceResultResources {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn checked_add(
        self,
        other: Self,
    ) -> Option<Self> {
        Some(Self {
            retained_bytes: self.retained_bytes.checked_add(other.retained_bytes)?,
            receiving_visits: self.receiving_visits.checked_add(other.receiving_visits)?,
            decode_visits: self.decode_visits.checked_add(other.decode_visits)?,
            decode_slots: self.decode_slots.checked_add(other.decode_slots)?,
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn checked_sub(
        self,
        other: Self,
    ) -> Option<Self> {
        Some(Self {
            retained_bytes: self.retained_bytes.checked_sub(other.retained_bytes)?,
            receiving_visits: self.receiving_visits.checked_sub(other.receiving_visits)?,
            decode_visits: self.decode_visits.checked_sub(other.decode_visits)?,
            decode_slots: self.decode_slots.checked_sub(other.decode_slots)?,
        })
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum SourceResultResource {
    RetainedBytes,
    ReceivingWork,
    DecodeWork,
    DecodeSlots,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum SourceResultUnsupported
{
    ReceivingRecords,
    SnapshotReadBytes,
    Comparison,
    LiteralReadWork,
    FactIngress,
    TransportActivation,
    StartupIssuer,
    CatalogIssuer,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum SourceResultRefusal {
    Insufficient {
        resource: SourceResultResource,
        available: usize,
        requested: usize,
    },
    ControlInsufficient {
        resource: SourceResultResource,
        available: usize,
        requested: usize,
    },
    Activity(BrowserActivityFault),
    Overflow,
    Poisoned,
    Accounting,
    Allocation,
    Unsupported(SourceResultUnsupported),
}
#[derive(Debug)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum SourceResultError {
    Input(BrowserInputError),
    Relation(BrowserActionIssueError),
    Refused(SourceResultRefusal),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceResultPoolSnapshot
{
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) total:
        SourceResultResources,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) available:
        SourceResultResources,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) outstanding:
        SourceResultResources,
    /// Consumed permission, including attempted/failed work. Not performed work.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) spent:
        SourceResultResources,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) control_reserved:
        SourceResultResources,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) live_bytes: usize,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) first:
        Option<SourceResultRefusal>,
}
struct ResultPool {
    total: SourceResultResources,
    available: SourceResultResources,
    outstanding: SourceResultResources,
    spent: SourceResultResources,
    control_reserved: SourceResultResources,
    live_bytes: usize,
    first: Option<SourceResultRefusal>,
    allocation: Option<std::collections::TryReserveError>,
}
fn pool_lock(pool: &Mutex<ResultPool>) -> MutexGuard<'_, ResultPool> {
    match pool.lock() {
        Ok(state) => state,
        Err(poison) => {
            let mut state = poison.into_inner();
            state.first.get_or_insert(SourceResultRefusal::Poisoned);
            state
        }
    }
}
fn shortage(
    available: SourceResultResources,
    requested: SourceResultResources,
) -> Option<(SourceResultResource, usize, usize)> {
    [
        (
            SourceResultResource::RetainedBytes,
            available.retained_bytes,
            requested.retained_bytes,
        ),
        (
            SourceResultResource::ReceivingWork,
            available.receiving_visits,
            requested.receiving_visits,
        ),
        (
            SourceResultResource::DecodeWork,
            available.decode_visits,
            requested.decode_visits,
        ),
        (
            SourceResultResource::DecodeSlots,
            available.decode_slots,
            requested.decode_slots,
        ),
    ]
    .into_iter()
    .find(|(_, available, requested)| requested > available)
}
impl ResultPool {
    fn cached(&self) -> Option<SourceResultError> {
        self.first.map(SourceResultError::Refused)
    }
    fn refuse(&mut self, first: SourceResultRefusal) -> SourceResultError {
        SourceResultError::Refused(*self.first.get_or_insert(first))
    }
    fn consume_terminal(
        &mut self,
        owned: &mut SourceResultResources,
        first: SourceResultRefusal,
    ) -> SourceResultError {
        // This already-paid allowance performs only the bounded terminal path,
        // never source validation, allocation, IO or business permission.
        self.control_reserved = self
            .control_reserved
            .checked_sub(*owned)
            .expect("owned terminal allowance");
        self.spent = self
            .spent
            .checked_add(*owned)
            .expect("prepaid terminal allowance");
        *owned = SourceResultResources::default();
        self.refuse(first)
    }
    fn return_unused(&mut self, remaining: SourceResultResources, terminal: SourceResultResources) {
        match (
            self.outstanding.checked_sub(remaining),
            self.control_reserved.checked_sub(terminal),
            self.available
                .checked_add(remaining)
                .and_then(|n| n.checked_add(terminal)),
        ) {
            (Some(outstanding), Some(reserved), Some(available)) => {
                self.outstanding = outstanding;
                self.control_reserved = reserved;
                self.available = available;
            }
            _ => {
                self.first.get_or_insert(SourceResultRefusal::Accounting);
            }
        }
    }
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum NativeControlOperation {
    Claim,
    Work,
    Allocation,
    Unsupported,
}
/// Funding only. One bounded operation consumes one entry; no Clone, public
/// constructor, source grant or client-reported performed/refund amount.
struct NativeControlEntry {
    pool: Arc<Mutex<ResultPool>>,
    end: Instant,
    operation: NativeControlOperation,
}
fn terminal_cost() -> Option<SourceResultResources> {
    let header = size_of::<SourceResultError>();
    let work = header
        .checked_add(2usize.checked_mul(size_of::<ResultPool>())?)?
        .checked_add(size_of::<MutexGuard<'_, ResultPool>>())?;
    Some(SourceResultResources {
        retained_bytes: header,
        receiving_visits: work,
        decode_visits: work,
        decode_slots: 1,
    })
}
fn control_cost(operation: NativeControlOperation) -> Option<SourceResultResources> {
    // Actual closed paths: Claim has plan+origin+commit gates; Work has
    // origin+payload; Allocation has origin+payload+allocate+optional excess+init.
    // Pool passes include native return/backing retirement already paid here.
    let (source_passes, pool_passes) = match operation {
        NativeControlOperation::Claim => (3usize, 4usize),
        NativeControlOperation::Work => (2, 2),
        NativeControlOperation::Allocation => (5, 6),
        NativeControlOperation::Unsupported => (3, 2),
    };
    let header = size_of::<NativeControlEntry>();
    let work = header
        .checked_add(
            source_passes
                .checked_mul(SourceControllerLifetime::business_validation_work_upper()?)?,
        )?
        .checked_add(pool_passes.checked_mul(2usize.checked_mul(size_of::<ResultPool>())?)?)?
        .checked_add(pool_passes.checked_mul(size_of::<MutexGuard<'_, ResultPool>>())?)?
        .checked_add(2usize.checked_mul(size_of::<std::sync::atomic::AtomicUsize>())?)?;
    Some(SourceResultResources {
        retained_bytes: header,
        receiving_visits: work,
        decode_visits: work,
        decode_slots: 1,
    })
}
impl NativeControlEntry {
    fn lock(&self) -> Result<MutexGuard<'_, ResultPool>, SourceResultError> {
        let mut state = pool_lock(&self.pool);
        if let Some(first) = state.cached() {
            return Err(first);
        }
        // Lock-independent check of the SAME immutable original end after any
        // mutex wait. Never reenter source/loan gates from the pool lock.
        if Instant::now() >= self.end {
            return Err(state.refuse(SourceResultRefusal::Activity(
                BrowserActivityFault::OriginalEnd,
            )));
        }
        Ok(state)
    }
    fn refuse(&self, first: SourceResultRefusal) -> SourceResultError {
        match self.lock() {
            Ok(mut state) => state.refuse(first),
            Err(first) => first,
        }
    }
    // Caller holds the actual source gate. These fixed helpers perform no
    // source/loan reentry while holding the pool lock.
    fn allocate(
        &self,
        allocate: impl FnOnce() -> Result<Vec<u8>, std::collections::TryReserveError>,
    ) -> Result<Vec<u8>, SourceResultError> {
        if self.operation != NativeControlOperation::Allocation {
            return Err(self.refuse(SourceResultRefusal::Accounting));
        }
        let mut state = self.lock()?;
        match allocate() {
            Ok(backing) => Ok(backing),
            Err(error) => {
                state.allocation = Some(error);
                Err(state.refuse(SourceResultRefusal::Allocation))
            }
        }
    }
    fn initialize(
        &self,
        mut backing: Vec<u8>,
        bytes: usize,
    ) -> Result<NativeResultBacking, SourceResultError> {
        if self.operation != NativeControlOperation::Allocation {
            return Err(self.refuse(SourceResultRefusal::Accounting));
        }
        let mut state = self.lock()?;
        if backing.capacity() < bytes || !backing.is_empty() {
            return Err(state.refuse(SourceResultRefusal::Accounting));
        }
        backing.resize(bytes, 0);
        state.live_bytes = state
            .live_bytes
            .checked_add(backing.capacity())
            .expect("prepaid native backing");
        Ok(NativeResultBacking {
            bytes: backing,
            pool: Arc::clone(&self.pool),
        })
    }
}
struct SourceResultEscrow<'case> {
    plan: SourceResultPlan<'case>,
    origin: SourceBusinessOrigin,
    pool: Arc<Mutex<ResultPool>>,
    terminal: SourceResultResources,
}
impl Drop for SourceResultEscrow<'_> {
    fn drop(&mut self) {
        pool_lock(&self.pool).return_unused(SourceResultResources::default(), self.terminal);
        self.terminal = SourceResultResources::default();
    }
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct NativeResultCredit {
    pool: Arc<Mutex<ResultPool>>,
    origin: SourceBusinessOrigin,
    remaining: SourceResultResources,
    terminal: SourceResultResources,
}
impl Drop for NativeResultCredit {
    fn drop(&mut self) {
        pool_lock(&self.pool).return_unused(self.remaining, self.terminal);
        self.remaining = SourceResultResources::default();
        self.terminal = SourceResultResources::default();
    }
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct NativeResultBacking {
    bytes: Vec<u8>,
    pool: Arc<Mutex<ResultPool>>,
}
impl NativeResultBacking {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn bytes(
        &self,
    ) -> &[u8] {
        &self.bytes
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn capacity(
        &self,
    ) -> usize {
        self.bytes.capacity()
    }
}
impl Drop for NativeResultBacking {
    fn drop(&mut self) {
        let capacity = self.bytes.capacity();
        drop(std::mem::take(&mut self.bytes));
        let mut state = pool_lock(&self.pool);
        match state.live_bytes.checked_sub(capacity) {
            Some(live) => state.live_bytes = live,
            None => {
                state.first.get_or_insert(SourceResultRefusal::Accounting);
            }
        }
    }
}
impl NativeResultCredit {
    fn begin(
        &mut self,
        operation: NativeControlOperation,
    ) -> Result<NativeControlEntry, SourceResultError> {
        let mut state = pool_lock(&self.pool);
        if let Some(first) = state.cached() {
            return Err(first);
        }
        let end = self.origin.original_end();
        if Instant::now() >= end {
            return Err(state.consume_terminal(
                &mut self.terminal,
                SourceResultRefusal::Activity(BrowserActivityFault::OriginalEnd),
            ));
        }
        let Some(cost) = control_cost(operation) else {
            return Err(state.consume_terminal(&mut self.terminal, SourceResultRefusal::Overflow));
        };
        if let Some((resource, available, requested)) = shortage(self.remaining, cost) {
            return Err(state.consume_terminal(
                &mut self.terminal,
                SourceResultRefusal::ControlInsufficient {
                    resource,
                    available,
                    requested,
                },
            ));
        }
        if Instant::now() >= end {
            return Err(state.consume_terminal(
                &mut self.terminal,
                SourceResultRefusal::Activity(BrowserActivityFault::OriginalEnd),
            ));
        }
        self.remaining = self
            .remaining
            .checked_sub(cost)
            .expect("checked native control permission");
        state.outstanding = state
            .outstanding
            .checked_sub(cost)
            .expect("owned native control permission");
        state.spent = state
            .spent
            .checked_add(cost)
            .expect("prepaid native control permission");
        Ok(NativeControlEntry {
            pool: Arc::clone(&self.pool),
            end,
            operation,
        })
    }
    fn charge_payload(
        &mut self,
        entry: &NativeControlEntry,
        requested: SourceResultResources,
        lifetime: &SourceControllerLifetime,
    ) -> Result<(), SourceResultError> {
        // The entry was already paid before the caller's relation traversal.
        // Release all pool locks before entering this source gate.
        lifetime
            .while_business_active(|| self.commit_payload(entry, requested))
            .map_err(SourceResultError::Input)?
    }
    fn commit_payload(
        &mut self,
        entry: &NativeControlEntry,
        requested: SourceResultResources,
    ) -> Result<(), SourceResultError> {
        if !Arc::ptr_eq(&self.pool, &entry.pool) {
            return Err(entry.refuse(SourceResultRefusal::Accounting));
        }
        let mut state = entry.lock()?;
        if let Some((resource, available, requested)) = shortage(self.remaining, requested) {
            return Err(state.refuse(SourceResultRefusal::Insufficient {
                resource,
                available,
                requested,
            }));
        }
        self.remaining = self
            .remaining
            .checked_sub(requested)
            .expect("checked native payload");
        state.outstanding = state
            .outstanding
            .checked_sub(requested)
            .expect("owned native payload");
        state.spent = state
            .spent
            .checked_add(requested)
            .expect("prepaid native payload");
        Ok(())
    }
    /// A bounded native work permission, not evidence of counting/serialization.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn spend_native_work(
        &mut self,
        receiving: usize,
        decode: usize,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), SourceResultError> {
        let entry = self.begin(NativeControlOperation::Work)?;
        self.origin
            .validate_lifetime(lifetime, loans)
            .map_err(SourceResultError::Relation)?;
        self.charge_payload(
            &entry,
            SourceResultResources {
                receiving_visits: receiving,
                decode_visits: decode,
                ..SourceResultResources::default()
            },
            lifetime,
        )
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn allocate_native(
        &mut self,
        bytes: usize,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<NativeResultBacking, SourceResultError> {
        self.allocate_with(bytes, lifetime, loans, |bytes| {
            let mut backing = Vec::new();
            backing.try_reserve_exact(bytes)?;
            Ok(backing)
        })
    }
    fn allocate_with(
        &mut self,
        bytes: usize,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
        allocate: impl FnOnce(usize) -> Result<Vec<u8>, std::collections::TryReserveError>,
    ) -> Result<NativeResultBacking, SourceResultError> {
        let entry = self.begin(NativeControlOperation::Allocation)?;
        self.origin
            .validate_lifetime(lifetime, loans)
            .map_err(SourceResultError::Relation)?;
        let payload = Self::allocation_payload_cost(bytes)
            .ok_or_else(|| entry.refuse(SourceResultRefusal::Overflow))?;
        self.charge_payload(&entry, payload, lifetime)?;
        let backing = lifetime
            .while_business_active(|| entry.allocate(|| allocate(bytes)))
            .map_err(SourceResultError::Input)??;
        let extra = backing
            .capacity()
            .checked_sub(bytes)
            .ok_or_else(|| entry.refuse(SourceResultRefusal::Accounting))?;
        if extra != 0 {
            self.charge_payload(
                &entry,
                SourceResultResources {
                    retained_bytes: extra,
                    ..SourceResultResources::default()
                },
                lifetime,
            )?;
        }
        lifetime
            .while_business_active(|| entry.initialize(backing, bytes))
            .map_err(SourceResultError::Input)?
    }
    fn allocation_payload_cost(bytes: usize) -> Option<SourceResultResources> {
        let retained = bytes.checked_add(size_of::<NativeResultBacking>())?;
        let work = retained
            .checked_add(2usize.checked_mul(size_of::<std::sync::atomic::AtomicUsize>())?)?;
        Some(SourceResultResources {
            retained_bytes: retained,
            receiving_visits: work,
            decode_visits: work,
            decode_slots: 1,
        })
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn test_allocate_failure(
        &mut self,
        bytes: usize,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<NativeResultBacking, SourceResultError> {
        self.allocate_with(bytes, lifetime, loans, |_| {
            let mut backing = Vec::new();
            backing.try_reserve_exact(usize::MAX)?;
            Ok(backing)
        })
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn test_allocate_excess(
        &mut self,
        bytes: usize,
        extra: usize,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<NativeResultBacking, SourceResultError> {
        self.allocate_with(bytes, lifetime, loans, |requested| {
            let mut backing = Vec::new();
            backing.try_reserve_exact(requested.checked_add(extra).expect("test dimensions"))?;
            Ok(backing)
        })
    }
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceResultPreparation<
    'case,
> {
    cleanup: CleanupPlan,
    escrow: SourceResultEscrow<'case>,
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceResultPreparationFailure<
    'case,
> {
    first: ControllerAcquisitionFault,
    plan: SourceResultPlan<'case>,
    cleanup: Option<CleanupPlan>,
}
impl SourceResultPreparationFailure<'_> {
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn input_fault(
        &self,
    ) -> Option<&BrowserInputError> {
        match &self.first {
            ControllerAcquisitionFault::Input(error) => Some(error),
            _ => None,
        }
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn has_cleanup(
        &self,
    ) -> bool {
        self.cleanup.is_some()
    }
}
impl<'case> SourceResultPreparation<'case> {
    fn issue_header_cost() -> Option<SourceResultResources> {
        let header = size_of::<NativeResultCredit>();
        let work = header
            .checked_add(SourceBusinessOrigin::copy_work_upper()?)?
            .checked_add(2usize.checked_mul(size_of::<std::sync::atomic::AtomicUsize>())?)?;
        Some(SourceResultResources {
            retained_bytes: header,
            receiving_visits: work,
            decode_visits: work,
            decode_slots: 1,
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn native_issue_cost()
    -> Option<SourceResultResources> {
        control_cost(NativeControlOperation::Claim)?
            .checked_add(Self::issue_header_cost()?)?
            .checked_add(terminal_cost()?)
    }
    fn begin(
        &mut self,
        operation: NativeControlOperation,
    ) -> Result<NativeControlEntry, SourceResultError> {
        let mut state = pool_lock(&self.escrow.pool);
        if let Some(first) = state.cached() {
            return Err(first);
        }
        let end = self.escrow.origin.original_end();
        if Instant::now() >= end {
            return Err(state.consume_terminal(
                &mut self.escrow.terminal,
                SourceResultRefusal::Activity(BrowserActivityFault::OriginalEnd),
            ));
        }
        let Some(cost) = control_cost(operation) else {
            return Err(
                state.consume_terminal(&mut self.escrow.terminal, SourceResultRefusal::Overflow)
            );
        };
        if let Some((resource, available, requested)) = shortage(state.available, cost) {
            return Err(state.consume_terminal(
                &mut self.escrow.terminal,
                SourceResultRefusal::ControlInsufficient {
                    resource,
                    available,
                    requested,
                },
            ));
        }
        if Instant::now() >= end {
            return Err(state.consume_terminal(
                &mut self.escrow.terminal,
                SourceResultRefusal::Activity(BrowserActivityFault::OriginalEnd),
            ));
        }
        state.available = state
            .available
            .checked_sub(cost)
            .expect("checked pool control permission");
        state.spent = state
            .spent
            .checked_add(cost)
            .expect("prepaid pool control permission");
        Ok(NativeControlEntry {
            pool: Arc::clone(&self.escrow.pool),
            end,
            operation,
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn claim_native(
        &mut self,
        requested: SourceResultResources,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<NativeResultCredit, SourceResultError> {
        let entry = self.begin(NativeControlOperation::Claim)?;
        self.escrow
            .plan
            .validate(lifetime, loans)
            .map_err(SourceResultError::Input)?;
        self.escrow
            .origin
            .validate_lifetime(lifetime, loans)
            .map_err(SourceResultError::Relation)?;
        let header =
            Self::issue_header_cost().ok_or_else(|| entry.refuse(SourceResultRefusal::Overflow))?;
        let terminal =
            terminal_cost().ok_or_else(|| entry.refuse(SourceResultRefusal::Overflow))?;
        let total = requested
            .checked_add(header)
            .and_then(|n| n.checked_add(terminal))
            .ok_or_else(|| entry.refuse(SourceResultRefusal::Overflow))?;
        lifetime
            .while_business_active(|| {
                let mut state = entry.lock()?;
                if let Some((resource, available, requested)) = shortage(state.available, total) {
                    return Err(state.refuse(SourceResultRefusal::Insufficient {
                        resource,
                        available,
                        requested,
                    }));
                }
                state.available = state
                    .available
                    .checked_sub(total)
                    .expect("checked native claim");
                state.outstanding = state
                    .outstanding
                    .checked_add(requested)
                    .expect("prepaid native claim");
                state.spent = state
                    .spent
                    .checked_add(header)
                    .expect("prepaid native header");
                state.control_reserved = state
                    .control_reserved
                    .checked_add(terminal)
                    .expect("prepaid native terminal allowance");
                Ok(NativeResultCredit {
                    pool: Arc::clone(&self.escrow.pool),
                    origin: self.escrow.origin.duplicate_after_funding(),
                    remaining: requested,
                    terminal,
                })
            })
            .map_err(SourceResultError::Input)?
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn refuse_unsupported(
        &mut self,
        resource: SourceResultUnsupported,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), SourceResultError> {
        let entry = self.begin(NativeControlOperation::Unsupported)?;
        self.escrow
            .plan
            .validate(lifetime, loans)
            .map_err(SourceResultError::Input)?;
        self.escrow
            .origin
            .validate_lifetime(lifetime, loans)
            .map_err(SourceResultError::Relation)?;
        lifetime
            .while_business_active(|| {
                let mut state = entry.lock()?;
                Err(state.refuse(SourceResultRefusal::Unsupported(resource)))
            })
            .map_err(SourceResultError::Input)?
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare_selected_runtime(
        plan: SourceResultPlan<'case>,
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<Self, SourceResultPreparationFailure<'case>> {
        let mut cleanup = None;
        let mut prepare = || {
            plan.validate(lifetime, loans)
                .map_err(ControllerAcquisitionFault::Input)?;
            cleanup = Some(CleanupPlan::prepare_minimum(
                RuntimePackageDimensions,
                lifetime,
                loans,
            )?);
            let origin = lifetime
                .prepare_business_origin(loans)
                .map_err(ControllerAcquisitionFault::Input)?;
            let wrappers = size_of::<Self>()
                .checked_sub(size_of::<CleanupPlan>())
                .and_then(|n| n.checked_sub(size_of::<SourceResultPlan<'_>>()))
                .and_then(|n| n.checked_sub(size_of::<SourceBusinessOrigin>()))
                .ok_or(ControllerAcquisitionFault::Overflow)?;
            let backing=crate::workbench::model_originals::workflow::pipeline::browser::source_scope::arc_backing_layout::<Mutex<ResultPool>>().ok_or(ControllerAcquisitionFault::Overflow)?.size();
            let bytes = checked_add(wrappers, backing)?;
            loans
                .reserve_controlled_host_storage(bytes, 2, bytes)
                .map_err(ControllerAcquisitionFault::Input)?;
            let terminal = terminal_cost().ok_or(ControllerAcquisitionFault::Overflow)?;
            loans
                .reserve_result_escrow(lifetime, terminal)
                .map_err(ControllerAcquisitionFault::Input)?;
            let remaining = loans
                .remaining_cleanup_resources(lifetime)
                .map_err(ControllerAcquisitionFault::Input)?;
            let available = SourceResultResources {
                retained_bytes: remaining.retained_bytes,
                receiving_visits: remaining.receiving_visits,
                decode_visits: remaining.decode_visits,
                decode_slots: remaining.decode_slots,
            };
            loans
                .reserve_result_escrow(lifetime, available)
                .map_err(ControllerAcquisitionFault::Input)?;
            let total = available
                .checked_add(terminal)
                .ok_or(ControllerAcquisitionFault::Overflow)?;
            let pool = lifetime
                .while_business_active(|| {
                    Arc::new(Mutex::new(ResultPool {
                        total,
                        available,
                        outstanding: SourceResultResources::default(),
                        spent: SourceResultResources::default(),
                        control_reserved: terminal,
                        live_bytes: 0,
                        first: None,
                        allocation: None,
                    }))
                })
                .map_err(ControllerAcquisitionFault::Input)?;
            Ok((origin, pool, terminal))
        };
        match prepare() {
            Ok((origin, pool, terminal)) => Ok(Self {
                cleanup: cleanup.expect("minimum retained before escrow"),
                escrow: SourceResultEscrow {
                    plan,
                    origin,
                    pool,
                    terminal,
                },
            }),
            Err(first) => Err(SourceResultPreparationFailure {
                first,
                plan,
                cleanup,
            }),
        }
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn cleanup_capacity(
        &self,
    ) -> usize {
        self.cleanup.capacity()
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn has_allocation_error(
        &self,
    ) -> bool {
        pool_lock(&self.escrow.pool).allocation.is_some()
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn snapshot(
        &self,
    ) -> SourceResultPoolSnapshot {
        let state = pool_lock(&self.escrow.pool);
        SourceResultPoolSnapshot {
            total: state.total,
            available: state.available,
            outstanding: state.outstanding,
            spent: state.spent,
            control_reserved: state.control_reserved,
            live_bytes: state.live_bytes,
            first: state.first,
        }
    }
}

#[cfg(test)]
#[derive(Debug, Clone, Copy)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum TestNativeEndBoundary {
    Payload,
    Allocation,
    Initialization,
}
#[cfg(test)]
enum TestNativeEndPhase {
    Payload(SourceResultResources),
    Allocation(usize),
    Initialization { bytes: usize, backing: Vec<u8> },
}
#[cfg(test)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct TestPaidNativeEndOperation
{
    entry: NativeControlEntry,
    phase: TestNativeEndPhase,
}
#[cfg(test)]
impl NativeResultCredit {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn test_prepare_end_boundary(
        &mut self,
        boundary: TestNativeEndBoundary,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<TestPaidNativeEndOperation, SourceResultError> {
        let operation = match boundary {
            TestNativeEndBoundary::Payload => NativeControlOperation::Work,
            _ => NativeControlOperation::Allocation,
        };
        let entry = self.begin(operation)?;
        self.origin
            .validate_lifetime(lifetime, loans)
            .map_err(SourceResultError::Relation)?;
        let phase = match boundary {
            TestNativeEndBoundary::Payload => TestNativeEndPhase::Payload(SourceResultResources {
                receiving_visits: 1,
                decode_visits: 1,
                ..SourceResultResources::default()
            }),
            TestNativeEndBoundary::Allocation | TestNativeEndBoundary::Initialization => {
                let bytes = 97;
                self.charge_payload(
                    &entry,
                    Self::allocation_payload_cost(bytes).unwrap(),
                    lifetime,
                )?;
                match boundary {
                    TestNativeEndBoundary::Allocation => TestNativeEndPhase::Allocation(bytes),
                    TestNativeEndBoundary::Initialization => {
                        let backing = lifetime
                            .while_business_active(|| {
                                entry.allocate(|| {
                                    let mut v = Vec::new();
                                    v.try_reserve_exact(bytes)?;
                                    Ok(v)
                                })
                            })
                            .map_err(SourceResultError::Input)??;
                        TestNativeEndPhase::Initialization { bytes, backing }
                    }
                    TestNativeEndBoundary::Payload => {
                        unreachable!("outer closed allocation boundary")
                    }
                }
            }
        };
        Ok(TestPaidNativeEndOperation { entry, phase })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn test_complete_end_boundary(
        &mut self,
        paid: TestPaidNativeEndOperation,
        lifetime: &SourceControllerLifetime,
        entered: std::sync::mpsc::SyncSender<()>,
    ) -> Result<(), SourceResultError> {
        lifetime
            .while_business_active(|| {
                // Test-only handshake after the real source check and before the
                // exact production pool-lock/effect helper. No arbitrary callback.
                entered
                    .send(())
                    .expect("actual lock-boundary test receiver");
                match paid.phase {
                    TestNativeEndPhase::Payload(requested) => {
                        self.commit_payload(&paid.entry, requested)
                    }
                    TestNativeEndPhase::Allocation(bytes) => paid
                        .entry
                        .allocate(|| {
                            let mut v = Vec::new();
                            v.try_reserve_exact(bytes)?;
                            Ok(v)
                        })
                        .map(drop),
                    TestNativeEndPhase::Initialization { bytes, backing } => {
                        paid.entry.initialize(backing, bytes).map(drop)
                    }
                }
            })
            .map_err(SourceResultError::Input)?
    }
}
#[cfg(test)]
impl SourceResultPreparation<'_> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn test_lock_pool(
        &self,
    ) -> impl Drop + '_ {
        pool_lock(&self.escrow.pool)
    }
}
