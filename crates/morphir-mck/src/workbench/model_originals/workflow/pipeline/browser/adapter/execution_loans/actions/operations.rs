//! Factual partial source conversation; not browser acceptance or physical joins.
use super::*;
use std::sync::{Arc, Mutex, MutexGuard, Weak};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserConnectedJournalFault {
    Poisoned,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserOpeningSelectionReply {
    ProjectSelected,
    NotReady,
    Unavailable,
    OtherSelection,
    Retired,
    Replaced,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserInspectionPendingReply {
    InspectionPending,
    OriginalsOnly,
    Retired,
    Failed,
    NoOpening,
    Replaced,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserConnectedControlFault {
    Acquisition,
    Clock,
    Spawn,
    ChromiumExited,
    DriverExited,
    Process,
    Shape,
    Order,
    End,
    Cancelled,
    Input,
    Output,
}
/// Independent factual dimensions: a real retained reply survives a later
/// failure. Conversely, DATA retained after a failure does not erase it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserConnectedOperationObservation<R> {
    NotRequested,
    Requested {
        reply: Option<R>,
        first_control_fault: Option<BrowserConnectedControlFault>,
    },
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BrowserConnectedOperationsSnapshot {
    opening: BrowserConnectedOperationObservation<BrowserOpeningSelectionReply>,
    inspection_boundary: BrowserConnectedOperationObservation<BrowserInspectionPendingReply>,
    journal_fault: Option<BrowserConnectedJournalFault>,
}
impl BrowserConnectedOperationsSnapshot {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) const fn not_requested()
    -> Self {
        Self {
            opening: BrowserConnectedOperationObservation::NotRequested,
            inspection_boundary: BrowserConnectedOperationObservation::NotRequested,
            journal_fault: None,
        }
    }
    pub fn opening(&self) -> BrowserConnectedOperationObservation<BrowserOpeningSelectionReply> {
        self.opening
    }
    pub fn inspection_boundary(
        &self,
    ) -> BrowserConnectedOperationObservation<BrowserInspectionPendingReply> {
        self.inspection_boundary
    }
    pub fn journal_fault(&self) -> Option<BrowserConnectedJournalFault> {
        self.journal_fault
    }
}
fn journal_lock(
    state: &Mutex<BrowserConnectedOperationsSnapshot>,
) -> MutexGuard<'_, BrowserConnectedOperationsSnapshot> {
    match state.lock() {
        Ok(state) => state,
        Err(poison) => {
            let mut state = poison.into_inner();
            state
                .journal_fault
                .get_or_insert(BrowserConnectedJournalFault::Poisoned);
            state
        }
    }
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceOperationJournal
{
    state: Arc<Mutex<BrowserConnectedOperationsSnapshot>>,
}
pub(super) struct SourceOperationIdentity {
    state: Weak<Mutex<BrowserConnectedOperationsSnapshot>>,
}
impl SourceOperationIdentity {
    pub(super) fn same_identity(&self, other: &Self) -> bool {
        self.state.ptr_eq(&other.state)
    }
    pub(super) fn duplicate_after_funding(&self) -> Self {
        Self {
            state: self.state.clone(),
        }
    }
    pub(super) fn copy_work_upper() -> Option<usize> {
        size_of::<Self>().checked_add(size_of::<std::sync::atomic::AtomicUsize>().checked_mul(2)?)
    }
    pub(super) fn preflight(
        &self,
        journal: &SourceOperationJournal,
    ) -> Result<(), BrowserActionCursorFault> {
        // No temporary Weak/Arc or mutable debit is created for foreign DATA.
        // Both are existing nominal allocations, and this retained Weak keeps
        // its allocation identity alive even when the original Arc is gone.
        if self.state.as_ptr() != Arc::as_ptr(&journal.state) {
            return Err(BrowserActionCursorFault::ForeignAction);
        }
        Ok(())
    }
    pub(super) fn fund(loans: &mut inputs::BrowserOwnerLoans<'_>) -> Result<(), BrowserInputError> {
        let bytes = size_of::<Self>();
        let work = bytes
            .checked_add(
                size_of::<std::sync::atomic::AtomicUsize>()
                    .checked_mul(2)
                    .ok_or_else(|| overflow(loans))?,
            )
            .ok_or_else(|| overflow(loans))?;
        reserve(loans, bytes, 1, work)
    }
    pub(super) fn fund_validation(
        &self,
        loans: &mut inputs::BrowserOwnerLoans<'_>,
    ) -> Result<(), BrowserInputError> {
        let work = size_of::<Self>()
            + size_of::<Arc<Mutex<BrowserConnectedOperationsSnapshot>>>()
            + 3 * size_of::<std::sync::atomic::AtomicUsize>();
        reserve(loans, 0, 0, work)
    }
    pub(super) fn matches(
        &self,
        journal: &SourceOperationJournal,
    ) -> Result<(), BrowserActionCursorFault> {
        self.preflight(journal)?;
        let Some(owner) = self.state.upgrade() else {
            return Err(BrowserActionCursorFault::ForeignAction);
        };
        if !Arc::ptr_eq(&owner, &journal.state) {
            return Err(BrowserActionCursorFault::ForeignAction);
        }
        if journal_lock(&owner).journal_fault.is_some() {
            return Err(BrowserActionCursorFault::Poisoned);
        }
        Ok(())
    }
}
impl SourceOperationJournal {
    pub(super) fn identity_after_funding(&self) -> SourceOperationIdentity {
        SourceOperationIdentity {
            state: Arc::downgrade(&self.state),
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare(
        loans: &mut inputs::BrowserOwnerLoans<'_>,
    ) -> Result<Self, BrowserInputError> {
        // One real backing, its counters and two future moved pending writers.
        // No per-poll state allocations or unbounded history are introduced.
        let counters = 2usize
            .checked_mul(size_of::<std::sync::atomic::AtomicUsize>())
            .ok_or_else(|| overflow(loans))?;
        let backing = crate::workbench::model_originals::workflow::pipeline::browser::source_scope::arc_backing_layout::<Mutex<BrowserConnectedOperationsSnapshot>>()
            .ok_or_else(|| overflow(loans))?.size();
        let writers = size_of::<PendingSourceOperation>()
            .checked_mul(2)
            .and_then(|n| n.checked_add(size_of::<MeasuredOpeningReply>()))
            .and_then(|n| n.checked_add(size_of::<MeasuredInspectionReply>()))
            .ok_or_else(|| overflow(loans))?;
        let bytes = backing
            .checked_add(writers)
            .ok_or_else(|| overflow(loans))?;
        // Two requested writes, at most one reply and first fault per operation,
        // two writer clone/drop pairs and a fixed immutable engine capture.
        let writes = size_of::<BrowserConnectedOperationsSnapshot>()
            .checked_mul(8)
            .and_then(|n| n.checked_add(4usize.checked_mul(counters)?))
            .and_then(|n| n.checked_add(bytes))
            .ok_or_else(|| overflow(loans))?;
        reserve(loans, bytes, 3, writes)?;
        Ok(Self {
            state: Arc::new(Mutex::new(
                BrowserConnectedOperationsSnapshot::not_requested(),
            )),
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn snapshot(
        &self,
    ) -> BrowserConnectedOperationsSnapshot {
        *journal_lock(&self.state)
    }
    // Issuance is called ONLY after exact action/currentness validation and the
    // actual raw controller has accepted its fixed matching begin command.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn requested(
        &self,
        operation: SourceOperationKind,
    ) -> Result<PendingSourceOperation, BrowserActionCursorFault> {
        let mut state = journal_lock(&self.state);
        if state.journal_fault.is_some() {
            return Err(BrowserActionCursorFault::Poisoned);
        }
        match operation {
            SourceOperationKind::Opening => request(&mut state.opening)?,
            SourceOperationKind::InspectionBoundary => request(&mut state.inspection_boundary)?,
        }
        Ok(PendingSourceOperation {
            state: Arc::clone(&self.state),
            operation,
        })
    }
}
fn request<R>(
    state: &mut BrowserConnectedOperationObservation<R>,
) -> Result<(), BrowserActionCursorFault> {
    if !matches!(state, BrowserConnectedOperationObservation::NotRequested) {
        return Err(BrowserActionCursorFault::AlreadyOutstanding);
    }
    *state = BrowserConnectedOperationObservation::Requested {
        reply: None,
        first_control_fault: None,
    };
    Ok(())
}
#[derive(Clone, Copy)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum SourceOperationKind {
    Opening,
    InspectionBoundary,
}
// This owner is moved into the SAME raw controller, not returned as a writable
// public port. Only its strict matched receive/failure path may mutate it.
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct PendingSourceOperation
{
    state: Arc<Mutex<BrowserConnectedOperationsSnapshot>>,
    operation: SourceOperationKind,
}
// The actual fixed controller creates these by moving its corresponding
// pending writer after strict decoded conversation matching. Neither receipt
// is Clone or constructible outside this module. The journal association is
// nominal; reply values or action positions alone cannot reconstruct it.
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct MeasuredOpeningReply {
    state: Arc<Mutex<BrowserConnectedOperationsSnapshot>>,
    reply: BrowserOpeningSelectionReply,
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct MeasuredInspectionReply
{
    state: Arc<Mutex<BrowserConnectedOperationsSnapshot>>,
    reply: BrowserInspectionPendingReply,
}
impl PendingSourceOperation {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn fault(
        &mut self,
        cause: BrowserConnectedControlFault,
    ) {
        let mut state = journal_lock(&self.state);
        match self.operation {
            SourceOperationKind::Opening => retain_fault(&mut state.opening, cause),
            SourceOperationKind::InspectionBoundary => {
                retain_fault(&mut state.inspection_boundary, cause)
            }
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn opening(
        self,
        reply: BrowserOpeningSelectionReply,
    ) -> Result<MeasuredOpeningReply, Self> {
        if !matches!(self.operation, SourceOperationKind::Opening) {
            return Err(self);
        }
        {
            let mut state = journal_lock(&self.state);
            let BrowserConnectedOperationObservation::Requested {
                reply: retained, ..
            } = &mut state.opening
            else {
                unreachable!("exclusive controller writer follows requested transition")
            };
            debug_assert!(retained.is_none());
            retained.get_or_insert(reply);
        }
        Ok(MeasuredOpeningReply {
            state: self.state,
            reply,
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn inspection(
        self,
        reply: BrowserInspectionPendingReply,
    ) -> Result<MeasuredInspectionReply, Self> {
        if !matches!(self.operation, SourceOperationKind::InspectionBoundary) {
            return Err(self);
        }
        {
            let mut state = journal_lock(&self.state);
            let BrowserConnectedOperationObservation::Requested {
                reply: retained, ..
            } = &mut state.inspection_boundary
            else {
                unreachable!("exclusive controller writer follows requested transition")
            };
            debug_assert!(retained.is_none());
            retained.get_or_insert(reply);
        }
        Ok(MeasuredInspectionReply {
            state: self.state,
            reply,
        })
    }
}
impl MeasuredOpeningReply {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn accepted_by(
        &self,
        journal: &SourceOperationJournal,
    ) -> bool {
        if !self.matches(journal) || self.reply != BrowserOpeningSelectionReply::ProjectSelected {
            return false;
        }
        let state = journal_lock(&self.state);
        state.journal_fault.is_none()
            && matches!(
                state.opening,
                BrowserConnectedOperationObservation::Requested {
                    reply: Some(BrowserOpeningSelectionReply::ProjectSelected),
                    first_control_fault: None
                }
            )
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn matches(
        &self,
        journal: &SourceOperationJournal,
    ) -> bool {
        Arc::ptr_eq(&self.state, &journal.state)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn reply(
        &self,
    ) -> BrowserOpeningSelectionReply {
        self.reply
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn fault(
        &mut self,
        cause: BrowserConnectedControlFault,
    ) {
        let mut state = journal_lock(&self.state);
        retain_fault(&mut state.opening, cause);
    }
}
impl MeasuredInspectionReply {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn accepted_by(
        &self,
        journal: &SourceOperationJournal,
    ) -> bool {
        if !self.matches(journal) || self.reply != BrowserInspectionPendingReply::InspectionPending
        {
            return false;
        }
        let state = journal_lock(&self.state);
        state.journal_fault.is_none()
            && matches!(
                state.inspection_boundary,
                BrowserConnectedOperationObservation::Requested {
                    reply: Some(BrowserInspectionPendingReply::InspectionPending),
                    first_control_fault: None
                }
            )
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn matches(
        &self,
        journal: &SourceOperationJournal,
    ) -> bool {
        Arc::ptr_eq(&self.state, &journal.state)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn reply(
        &self,
    ) -> BrowserInspectionPendingReply {
        self.reply
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn fault(
        &mut self,
        cause: BrowserConnectedControlFault,
    ) {
        let mut state = journal_lock(&self.state);
        retain_fault(&mut state.inspection_boundary, cause);
    }
}
fn retain_fault<R>(
    state: &mut BrowserConnectedOperationObservation<R>,
    cause: BrowserConnectedControlFault,
) {
    if let BrowserConnectedOperationObservation::Requested {
        first_control_fault,
        ..
    } = state
    {
        first_control_fault.get_or_insert(cause);
    }
}
// Deliberately no Drop-generated reply or source settlement. An unresolved
// Requested field remains factual evidence that the issued operation is pending.

#[cfg(test)]
mod tests {
    use super::super::super::tests::with_compiled;
    use super::*;
    #[test]
    fn browser_source_receipts_03_actual_mutex_poison_retains_data_but_never_healthy_evidence() {
        with_compiled(|_, loans| {
            let journal = SourceOperationJournal::prepare(loans).unwrap();
            let pending = journal.requested(SourceOperationKind::Opening).unwrap();
            // Literal closed DATA only; no source action or controller effect is
            // settled by this private journal transition.
            let _receipt = pending
                .opening(BrowserOpeningSelectionReply::ProjectSelected)
                .unwrap_or_else(|_| panic!("opening writer"));
            let original = journal.snapshot();
            let panic = std::panic::catch_unwind(|| {
                let _held = journal.state.lock().unwrap();
                panic!("literal journal owner unwind");
            });
            assert!(panic.is_err());
            let observed = journal.snapshot();
            assert_eq!(observed.opening(), original.opening());
            assert_eq!(
                observed.journal_fault(),
                Some(BrowserConnectedJournalFault::Poisoned)
            );
            assert!(matches!(
                journal.requested(SourceOperationKind::InspectionBoundary),
                Err(BrowserActionCursorFault::Poisoned)
            ));
        });
    }
}
