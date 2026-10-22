//! Canonical-engine child loans. No public execution constructor or verdict.
use super::super::source_scope::{
    ApplicationSourceIdentity, BrowserInvocationIdentity, BrowserInvocationScope, ScopeIssueFault,
};
pub(in crate::workbench::model_originals::workflow::pipeline::browser) use super::BrowserActivityFault;
use super::*;
use crate::workbench::model_originals::workflow::{
    pipeline::installed::observation::{InstalledObservationFault, InstalledObservationResource},
    source_compile::CompiledSourceCase,
};
use std::mem::size_of;

pub(super) enum LoanRelation<'a> {
    Application(&'a BrowserSourceScope),
    Execution {
        global: &'a BrowserSourceScope,
        child: &'a ExecutionChild,
    },
}
/// Engine-owned lifetime; it is not itself a physical execution grant.
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct ExecutionChild {
    scope: BrowserInvocationScope,
    pub(super) identity: BrowserInvocationIdentity,
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct BrowserLoanStamp {
    relation: OwnedRelation,
}
impl BrowserLoanStamp {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn while_active<R>(
        &self,
        action: impl FnOnce() -> R,
    ) -> Result<R, BrowserSourceFault> {
        match &self.relation {
            OwnedRelation::Application(global) => global.while_active(action),
            OwnedRelation::Execution { child, .. } => child.while_active(action),
        }
    }
}
#[derive(Debug, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct BrowserOpeningPosition(
    usize,
);
impl BrowserOpeningPosition {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn get(&self) -> usize {
        self.0
    }
}
enum OwnedRelation {
    Application(ApplicationSourceIdentity),
    Execution {
        global: ApplicationSourceIdentity,
        child: BrowserInvocationIdentity,
    },
}
fn issue(fault: ScopeIssueFault) -> BrowserInputError {
    match fault {
        ScopeIssueFault::Input(fault) => fault.into(),
        ScopeIssueFault::Scope(fault) => inputs::BrowserInputFault::Source(fault).into(),
    }
}
fn source(fault: BrowserSourceFault) -> BrowserInputError {
    inputs::BrowserInputFault::Source(fault).into()
}
fn reserve(
    loans: &mut inputs::BrowserOwnerLoans<'_>,
    bytes: usize,
    slots: usize,
    initialized: usize,
) -> Result<(), BrowserInputError> {
    let (decode, receiving, _) = loans.physical_owners()?;
    decode
        .slots(slots)
        .map_err(inputs::BrowserInputFault::Decode)?;
    receiving
        .reserve_span(InstalledObservationResource::RetainedBytes, bytes)
        .map_err(inputs::BrowserInputFault::Receiving)?;
    decode
        .bytes(initialized)
        .map_err(inputs::BrowserInputFault::Decode)?;
    receiving
        .reserve_span(InstalledObservationResource::ByteVisits, initialized)
        .map_err(inputs::BrowserInputFault::Receiving)?;
    Ok(())
}
fn overflow(loans: &mut inputs::BrowserOwnerLoans<'_>) -> BrowserInputError {
    match loans.physical_owners() {
        Ok((_, receiving, _)) => inputs::BrowserInputFault::Receiving(
            *receiving.fail(InstalledObservationFault::SizeOverflow),
        )
        .into(),
        Err(fault) => fault.into(),
    }
}
impl ExecutionChild {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare(
        global: &BrowserSourceScope,
        loans: &mut inputs::BrowserOwnerLoans<'_>,
    ) -> Result<Self, BrowserInputError> {
        loans.ready()?;
        global.ready().map_err(source)?;
        // The scope and identity smart constructors fund their embedded fields.
        // Pay any additional wrapper padding before retaining those fields.
        let padding = size_of::<Self>()
            .checked_sub(size_of::<BrowserInvocationScope>())
            .and_then(|n| n.checked_sub(size_of::<BrowserInvocationIdentity>()))
            .ok_or_else(|| overflow(loans))?;
        reserve(loans, padding, 0, padding)?;
        let scope = global.prepare_invocation(loans).map_err(issue)?;
        let identity = scope.identity(loans).map_err(issue)?;
        Ok(Self { scope, identity })
    }
    fn ready(&self, global: &BrowserSourceScope) -> Result<(), BrowserInputError> {
        self.scope.validate_parent(global).map_err(source)?;
        self.identity.validate(&self.scope).map_err(source)
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn revoke(
        &mut self,
    ) -> BrowserSourceTerminal {
        self.scope.revoke()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn terminal(
        &self,
    ) -> BrowserSourceTerminal {
        self.scope.terminal()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn revoke_with_capture<
        R,
    >(
        &mut self,
        capture: impl FnOnce() -> R,
    ) -> (R, BrowserSourceTerminal) {
        self.scope.revoke_with_capture(capture)
    }
}
impl<'a, 'owners> BrowserLoans<'a, 'owners> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn fail_collection(
        &mut self,
        fault: InstalledObservationFault,
    ) -> BrowserInputError {
        match self.inner.physical_owners() {
            Ok((_, receiving, _)) => {
                inputs::BrowserInputFault::Receiving(*receiving.fail(fault)).into()
            }
            Err(cause) => cause.into(),
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn application(
        inner: &'a mut inputs::BrowserOwnerLoans<'owners>,
        global: &'a BrowserSourceScope,
    ) -> Result<Self, BrowserInputError> {
        let result = Self {
            inner,
            relation: LoanRelation::Application(global),
        };
        result.ready()?;
        Ok(result)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn execution(
        inner: &'a mut inputs::BrowserOwnerLoans<'owners>,
        global: &'a BrowserSourceScope,
        child: &'a ExecutionChild,
    ) -> Result<Self, BrowserInputError> {
        let result = Self {
            inner,
            relation: LoanRelation::Execution { global, child },
        };
        result.ready()?;
        Ok(result)
    }
    pub(super) fn global(&self) -> &BrowserSourceScope {
        match self.relation {
            LoanRelation::Application(global) | LoanRelation::Execution { global, .. } => global,
        }
    }
    pub(super) fn ready(&self) -> Result<(), BrowserInputError> {
        self.inner.ready()?;
        match self.relation {
            LoanRelation::Application(global) => global.ready().map_err(source),
            LoanRelation::Execution { global, child } => child.ready(global),
        }
    }
    fn ready_for_run(
        &self,
        global: &BrowserSourceScope,
        child: &ExecutionChild,
    ) -> Result<(), BrowserInputError> {
        self.ready()?;
        match self.relation {
            LoanRelation::Execution {
                global: actual_global,
                child: actual_child,
            } if std::ptr::eq(global, actual_global) && std::ptr::eq(child, actual_child) => Ok(()),
            _ => Err(source(BrowserSourceFault::ForeignSource)),
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare_relation_stamp(
        &mut self,
    ) -> Result<BrowserLoanStamp, BrowserInputError> {
        self.ready()?;
        let child_bytes = match self.relation {
            LoanRelation::Application(_) => 0,
            LoanRelation::Execution { .. } => size_of::<BrowserInvocationIdentity>(),
        };
        let wrapper = size_of::<BrowserLoanStamp>()
            .checked_sub(child_bytes)
            .ok_or_else(|| overflow(self.inner))?;
        let initialized = wrapper
            .checked_add(size_of::<std::sync::atomic::AtomicUsize>())
            .ok_or_else(|| overflow(self.inner))?;
        self.reserve_controlled_host_storage(wrapper, 1, initialized)?;
        // All stamp backing/counter writes are paid before retaining Weak links.
        let relation = match self.relation {
            LoanRelation::Application(global) => {
                OwnedRelation::Application(global.application_identity().map_err(source)?)
            }
            LoanRelation::Execution { global, child } => {
                let identity = child.scope.identity(self.inner).map_err(issue)?;
                OwnedRelation::Execution {
                    global: global.application_identity().map_err(source)?,
                    child: identity,
                }
            }
        };
        Ok(BrowserLoanStamp { relation })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate_relation_stamp(
        &self,
        stamp: &BrowserLoanStamp,
    ) -> Result<(), BrowserInputError> {
        self.ready()?;
        match (&self.relation, &stamp.relation) {
            (LoanRelation::Application(global), OwnedRelation::Application(identity)) => {
                identity.validate(global).map_err(source)
            }
            (
                LoanRelation::Execution { global, child },
                OwnedRelation::Execution {
                    global: identity,
                    child: issued,
                },
            ) => {
                identity.validate(global).map_err(source)?;
                issued.validate(&child.scope).map_err(source)
            }
            _ => Err(source(BrowserSourceFault::ForeignSource)),
        }
    }
}
/// Borrows the actual current compiler row; the engine retains its full inventory
/// and row/report context outside this adapter input view.
pub struct PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied> {
    core: &'compiled CompiledSourceCase<'case, 'sources, 'raw, 'supplied>,
    input: inputs::BrowserExecutionInput<'compiled, 'case, 'sources, 'raw, 'supplied>,
    global: &'run BrowserSourceScope,
    child: &'run ExecutionChild,
    actions: std::sync::Mutex<actions::BrowserActionCursor<'case>>,
}
pub struct BrowserExecutionOpening<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied> {
    owner: &'a PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    action: inputs::BrowserActionInput<'case>,
}
struct BrowserExecutionOpenings<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied, I> {
    owner: &'a PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    actions: I,
}
impl<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied, I>
    BrowserExecutionOpenings<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied, I>
where
    I: ExactSizeIterator<Item = inputs::BrowserActionInput<'case>>,
{
    fn prepare(
        owner: &'a PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        actions: I,
        loans: &mut inputs::BrowserOwnerLoans<'_>,
    ) -> Result<Self, BrowserInputError> {
        // Bound every possible operand before issuing the first. Non-opening
        // actions conservatively retain their prepaid slot; there is no refund.
        let count = actions.len();
        let bytes = size_of::<
            BrowserExecutionOpening<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        >()
        .checked_mul(count)
        .and_then(|bytes| bytes.checked_add(size_of::<Self>()))
        .ok_or_else(|| overflow(loans))?;
        let slots = count.checked_add(1).ok_or_else(|| overflow(loans))?;
        reserve(loans, bytes, slots, bytes)?;
        Ok(Self { owner, actions })
    }
}
impl<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied, I> Iterator
    for BrowserExecutionOpenings<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied, I>
where
    I: Iterator<Item = inputs::BrowserActionInput<'case>>,
{
    type Item = BrowserExecutionOpening<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>;
    fn next(&mut self) -> Option<Self::Item> {
        self.actions
            .find(|action| {
                matches!(
                    action.kind(),
                    inputs::BrowserActionKind::StartConnected { .. }
                        | inputs::BrowserActionKind::BeginConnectedOpening { .. }
                )
            })
            .map(|action| BrowserExecutionOpening {
                owner: self.owner,
                action,
            })
    }
}
impl<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare(
        core: &'compiled CompiledSourceCase<'case, 'sources, 'raw, 'supplied>,
        global: &'run BrowserSourceScope,
        child: &'run ExecutionChild,
        loans: &mut inputs::BrowserOwnerLoans<'_>,
    ) -> Result<Self, BrowserInputError> {
        loans.ready()?;
        child.ready(global)?;
        let input = inputs::BrowserExecutionInput::from_compiled_client(core, loans)?;
        let actions = child
            .identity
            .while_active(|| {
                reserve(loans, size_of::<Self>(), 1, size_of::<Self>())?;
                let actual = input.actions(loans)?;
                actions::BrowserActionCursor::prepare(actual, loans)
            })
            .map_err(source)??;
        Ok(Self {
            core,
            input,
            global,
            child,
            actions: std::sync::Mutex::new(actions),
        })
    }
    pub fn openings<'a>(
        &'a self,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<
        impl Iterator<
            Item = BrowserExecutionOpening<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        > + use<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        BrowserInputError,
    > {
        loans.ready_for_run(self.global, self.child)?;
        self.child
            .identity
            .while_active(|| {
                let actions = self.input.actions(loans.inner)?;
                BrowserExecutionOpenings::prepare(self, actions, loans.inner)
            })
            .map_err(source)?
    }
    pub fn prepare_controlled_host(
        &self,
        opening: &BrowserExecutionOpening<'_, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<ControlledHostStimulus, BrowserInputError> {
        loans.ready_for_run(self.global, self.child)?;
        if !std::ptr::eq(opening.owner, self) {
            return Err(source(BrowserSourceFault::ForeignSource));
        }
        let prepared = self
            .child
            .identity
            .while_active(|| {
                ControlledHostStimulus::prepare_selected(
                    self.input.fixture(),
                    &opening.action,
                    loans.inner,
                )
            })
            .map_err(source)??;
        // Issue debt only after every fallible input copy; no nested source lock.
        let binding = self.child.scope.bind(loans.inner).map_err(issue)?;
        Ok(prepared.finish(binding))
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate_opening(
        &self,
        opening: &BrowserExecutionOpening<'_, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<BrowserOpeningPosition, BrowserInputError> {
        loans.ready_for_run(self.global, self.child)?;
        if !std::ptr::eq(opening.owner, self) {
            return Err(source(BrowserSourceFault::ForeignSource));
        }
        Ok(BrowserOpeningPosition(opening.action.position()))
    }
}
#[path = "execution_loans/actions.rs"]
mod actions;
pub use actions::{
    BrowserActionCursorFault, BrowserActionCursorTerminal, BrowserActionIssueError,
    BrowserConnectedControlFault, BrowserConnectedJournalFault, BrowserConnectedOpening,
    BrowserConnectedOperationObservation, BrowserConnectedOperationsSnapshot,
    BrowserConnectedPreparationFailure, BrowserControllerPreparation, BrowserExecutionAction,
    BrowserInspectionBoundarySource, BrowserOwnedInspectionBoundary, BrowserInspectionPendingReply, BrowserOpeningSelectionReply, BrowserOwnedConnectedOpening,
    BrowserPreparedControllerStep, BrowserPreparedListenerStart,
};
pub(in crate::workbench::model_originals::workflow::pipeline::browser) use actions::{
    ConnectedOpeningAction, PreparedConnectedOpening, SourceControllerActivity,
    SourceControllerLifetime, SourceControllerOperationShape, SourceOperationJournal,
    MeasuredInspectionReply, MeasuredOpeningReply, PendingSourceOperation, SourceOperationKind,
};
#[cfg(test)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) use actions::{
    with_foreign_source_controller_lifetime, with_revoked_source_controller_lifetime,
    with_source_controller_artifact_control, with_source_controller_artifact_endpoint,
    with_source_controller_cleanup_control, with_source_controller_end,
    with_source_controller_endpoint, with_source_controller_lifetime,
    with_source_controller_limits,
};
impl BrowserLoans<'_, '_> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare_controller_buffers(
        &mut self,
        lifetime: &SourceControllerLifetime,
        limits: crate::transport::Limits,
    ) -> Result<super::super::funded_workflow::BrowserPhysicalBuffers, BrowserInputError> {
        lifetime.validate(self)?;
        lifetime
            .while_business_active(|| {
                super::super::funded_workflow::BrowserPhysicalBuffers::prepare_for_controller(
                    self.inner, limits, lifetime,
                )
            })?
            .map_err(BrowserInputError::from)
    }
}
#[cfg(test)]
#[path = "execution_loans/tests.rs"]
mod tests;
#[cfg(test)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) use tests::{controlled_clients, with_compiled_artifact_control};

/// Residual SAME-owner planning quantities, never a reservation or grant.
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct BrowserCleanupRemaining
{
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) retained_bytes: usize,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) receiving_visits: usize,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) decode_visits: usize,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) decode_slots: usize,
}
impl BrowserLoans<'_, '_> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn remaining_cleanup_resources(
        &mut self,
        lifetime: &SourceControllerLifetime,
    ) -> Result<BrowserCleanupRemaining, BrowserInputError> {
        use crate::workbench::model_originals::workflow::decode::OperandResource;
        lifetime.validate(self)?;
        let (decode, receiving, _) = self.inner.physical_owners()?;
        let retained = receiving
            .remaining(InstalledObservationResource::RetainedBytes)
            .map_err(inputs::BrowserInputFault::Receiving)?;
        let visits = receiving
            .remaining(InstalledObservationResource::ByteVisits)
            .map_err(inputs::BrowserInputFault::Receiving)?;
        Ok(BrowserCleanupRemaining {
            retained_bytes: usize::try_from(retained).map_err(|_| {
                inputs::BrowserInputFault::Receiving(InstalledObservationFault::SizeOverflow)
            })?,
            receiving_visits: usize::try_from(visits).map_err(|_| {
                inputs::BrowserInputFault::Receiving(InstalledObservationFault::SizeOverflow)
            })?,
            decode_visits: decode
                .remaining(OperandResource::ByteVisits)
                .map_err(inputs::BrowserInputFault::Decode)?,
            decode_slots: decode
                .remaining(OperandResource::Slots)
                .map_err(inputs::BrowserInputFault::Decode)?,
        })
    }
}
