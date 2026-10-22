//! Source-selected monotone action input. No physical execution or verdict.
use super::*;
use std::sync::{Mutex, MutexGuard};
#[path = "actions/borrowed.rs"]
mod borrowed;
#[path = "actions/business_origin.rs"]
mod business_origin;
#[path = "actions/connected.rs"]
mod connected;
#[path = "actions/inspection.rs"]
mod inspection;
#[path = "actions/operations.rs"]
mod operations;
#[path = "actions/preparation_failure.rs"]
mod preparation_failure;
pub(in crate::workbench::model_originals::workflow::pipeline::browser) use borrowed::business_gate_headers;
pub use borrowed::{
    BrowserConnectedOpening, BrowserControllerDispatch, BrowserControllerStepDispatcher,
    BrowserListenerDispatch, BrowserListenerStartDispatcher, BrowserPreparedControllerStep,
    BrowserPreparedListenerStart,
};
pub(in crate::workbench::model_originals::workflow::pipeline::browser) use business_origin::SourceBusinessOrigin;
pub(in crate::workbench::model_originals::workflow::pipeline::browser) use connected::{
    ConnectedOpeningAction, PreparedConnectedOpening, SourceControllerActivity,
    SourceControllerLifetime, SourceControllerOperationShape,
};
pub use connected::{
    ConnectedOpeningAction as BrowserOwnedConnectedOpening,
    SourceControllerLifetime as BrowserControllerPreparation,
};
pub use inspection::{BrowserInspectionBoundarySource, BrowserOwnedInspectionBoundary};
use operations::SourceOperationIdentity;
pub use operations::{
    BrowserConnectedControlFault, BrowserConnectedJournalFault,
    BrowserConnectedOperationObservation, BrowserConnectedOperationsSnapshot,
    BrowserInspectionPendingReply, BrowserOpeningSelectionReply,
};
pub(in crate::workbench::model_originals::workflow::pipeline::browser) use operations::{
    MeasuredInspectionReply, MeasuredOpeningReply, PendingSourceOperation, SourceOperationJournal,
    SourceOperationKind,
};
pub use preparation_failure::BrowserConnectedPreparationFailure;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserActionCursorFault {
    AlreadyOutstanding,
    OutstandingAbandoned,
    ForeignAction,
    Unsupported(BrowserUnsupportedActionKind),
    Poisoned,
    UnsupportedOperation,
    PreparationRefused,
    OperationRefused,
}
#[derive(Debug)]
pub enum BrowserActionIssueError {
    #[cfg(target_os = "macos")]
    Funding(super::super::super::controller::source_business::SourceBusinessFundingFault),
    Input(BrowserInputError),
    Cursor(BrowserActionCursorFault),
    Host(super::super::super::collection::BrowserHostTranscriptFault),
    Collection(super::super::super::collection::BrowserCollectionFault),
    /// A normal document END is unavailable for new business, not a fault.
    DocumentClosed,
}
impl From<BrowserInputError> for BrowserActionIssueError {
    fn from(error: BrowserInputError) -> Self {
        Self::Input(error)
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserActionCursorTerminal {
    NoneIssued,
    /// Logical source progression only, never a physical execution certificate.
    FullSourceActionsConsumed {
        actions: usize,
    },
    Incomplete {
        consumed: usize,
        pending: Option<usize>,
        remaining: usize,
    },
    Refused {
        position: usize,
        cause: BrowserActionCursorFault,
    },
}
enum Phase {
    Ready,
    Issued(usize),
    Exhausted,
    Refused {
        position: usize,
        cause: BrowserActionCursorFault,
    },
}
pub(super) struct BrowserActionCursor<'case> {
    inputs: inputs::BrowserActionInputs<'case>,
    total: usize,
    phase: Phase,
    operations: SourceOperationJournal,
    first_issue: Option<BrowserActionIssueError>,
}
impl<'case> BrowserActionCursor<'case> {
    pub(super) fn prepare(
        inputs: inputs::BrowserActionInputs<'case>,
        loans: &mut inputs::BrowserOwnerLoans<'_>,
    ) -> Result<Self, BrowserInputError> {
        let total = inputs.len();
        let bytes = total
            .checked_mul(size_of::<BrowserExecutionAction<'_, '_, '_, '_, '_, '_, '_>>())
            .ok_or_else(|| overflow(loans))?;
        let initialized = total
            .checked_mul(size_of::<Self>())
            .and_then(|n| n.checked_add(bytes))
            .ok_or_else(|| overflow(loans))?;
        // The embedding run's actual layout already funds this cursor and Mutex.
        // Pay every possible issued wrapper and monotone state write before issue.
        reserve(loans, bytes, total, initialized)?;
        let operations = SourceOperationJournal::prepare(loans)?;
        Ok(Self {
            inputs,
            total,
            phase: Phase::Ready,
            operations,
            first_issue: None,
        })
    }
    fn position(&self) -> usize {
        match self.phase {
            Phase::Issued(position) | Phase::Refused { position, .. } => position,
            _ => self.total - self.inputs.len(),
        }
    }
    fn refuse(
        &mut self,
        position: usize,
        cause: BrowserActionCursorFault,
    ) -> BrowserActionCursorFault {
        if let Phase::Refused { cause, .. } = self.phase {
            cause
        } else {
            self.phase = Phase::Refused { position, cause };
            cause
        }
    }
    fn terminal(&self) -> BrowserActionCursorTerminal {
        match self.phase {
            Phase::Ready if self.inputs.len() == self.total => {
                BrowserActionCursorTerminal::NoneIssued
            }
            Phase::Ready => BrowserActionCursorTerminal::Incomplete {
                consumed: self.total - self.inputs.len(),
                pending: None,
                remaining: self.inputs.len(),
            },
            Phase::Issued(position) => BrowserActionCursorTerminal::Incomplete {
                consumed: self.total - self.inputs.len() - 1,
                pending: Some(position),
                remaining: self.inputs.len() + 1,
            },
            Phase::Exhausted if self.total > 0 => {
                BrowserActionCursorTerminal::FullSourceActionsConsumed {
                    actions: self.total,
                }
            }
            Phase::Exhausted => BrowserActionCursorTerminal::NoneIssued,
            Phase::Refused { position, cause } => {
                BrowserActionCursorTerminal::Refused { position, cause }
            }
        }
    }
}
fn lock<'a, 'case>(
    mutex: &'a Mutex<BrowserActionCursor<'case>>,
) -> MutexGuard<'a, BrowserActionCursor<'case>> {
    match mutex.lock() {
        Ok(cursor) => cursor,
        Err(poison) => {
            let mut cursor = poison.into_inner();
            let position = cursor.position();
            cursor.refuse(position, BrowserActionCursorFault::Poisoned);
            cursor
        }
    }
}
enum TokenState {
    Outstanding,
    Refused,
    Consumed,
}
/// A single source-issued input. Getters are DATA only; fixed operation factories
/// must validate this exact token, not reconstruct authority from its position.
pub struct BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied> {
    owner: &'a PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    input: inputs::BrowserActionInput<'case>,
    state: TokenState,
}
impl<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn refuse_controller(
        &mut self,
        cause: BrowserActionIssueError,
    ) {
        let mut cursor = lock(&self.owner.actions);
        cursor.first_issue.get_or_insert(cause);
        cursor.refuse(self.position(), BrowserActionCursorFault::OperationRefused);
        self.state = TokenState::Refused;
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn inspect_controller_cause<
        R,
    >(
        &self,
        inspect: impl FnOnce(&BrowserActionIssueError) -> R,
    ) -> R {
        let cursor = lock(&self.owner.actions);
        inspect(
            cursor
                .first_issue
                .as_ref()
                .expect("actual refusal retained before token drop"),
        )
    }
    pub fn position(&self) -> usize {
        self.input.position()
    }
    pub fn kind(&self) -> BrowserActionKind<'case> {
        super::super::project_browser_action(self.input.kind())
    }
    /// Pure source-projection control. Production has no fake completion path;
    /// genuine fixed controller factories will own their actual settlement seam.
    #[cfg(test)]
    fn consume_source_only_for_test(
        mut self,
        run: &PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError> {
        run.validate_action(&self, loans)?;
        let mut cursor = lock(&run.actions);
        cursor.phase = if cursor.inputs.len() == 0 {
            Phase::Exhausted
        } else {
            Phase::Ready
        };
        self.state = TokenState::Consumed;
        Ok(())
    }
}
impl Drop for BrowserExecutionAction<'_, '_, '_, '_, '_, '_, '_> {
    fn drop(&mut self) {
        if matches!(self.state, TokenState::Outstanding) {
            lock(&self.owner.actions).refuse(
                self.input.position(),
                BrowserActionCursorFault::OutstandingAbandoned,
            );
        }
    }
}
impl<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    pub fn next_action<'a>(
        &'a self,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<
        Option<BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>>,
        BrowserActionIssueError,
    > {
        loans.ready_for_run(self.global, self.child)?;
        self.child
            .identity
            .while_active(|| {
                let mut cursor = lock(&self.actions);
                match cursor.phase {
                    Phase::Refused { cause, .. } => {
                        return Err(BrowserActionIssueError::Cursor(cause));
                    }
                    Phase::Issued(position) => {
                        return Err(BrowserActionIssueError::Cursor(
                            cursor.refuse(position, BrowserActionCursorFault::AlreadyOutstanding),
                        ));
                    }
                    Phase::Exhausted => return Ok(None),
                    Phase::Ready => {}
                }
                let Some(input) = cursor.inputs.next() else {
                    cursor.phase = Phase::Exhausted;
                    return Ok(None);
                };
                let position = input.position();
                if let inputs::BrowserActionKind::Unsupported { kind } = input.kind() {
                    return Err(BrowserActionIssueError::Cursor(
                        cursor.refuse(position, BrowserActionCursorFault::Unsupported(kind)),
                    ));
                }
                cursor.phase = Phase::Issued(position);
                Ok(Some(BrowserExecutionAction {
                    owner: self,
                    input,
                    state: TokenState::Outstanding,
                }))
            })
            .map_err(|cause| BrowserActionIssueError::Input(source(cause)))?
    }
    pub fn validate_action(
        &self,
        action: &BrowserExecutionAction<'_, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError> {
        loans.ready_for_run(self.global, self.child)?;
        if !std::ptr::eq(action.owner, self) {
            return Err(BrowserActionIssueError::Input(source(
                BrowserSourceFault::ForeignSource,
            )));
        }
        let cursor = lock(&self.actions);
        match cursor.phase {
            Phase::Issued(position)
                if position == action.input.position()
                    && matches!(action.state, TokenState::Outstanding) =>
            {
                Ok(())
            }
            Phase::Refused { cause, .. } => Err(BrowserActionIssueError::Cursor(cause)),
            _ => Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::ForeignAction,
            )),
        }
    }
    pub fn actions_terminal(&self) -> BrowserActionCursorTerminal {
        lock(&self.actions).terminal()
    }
    /// DATA only; this copy cannot request or settle a source action.
    pub fn connected_operations(&self) -> BrowserConnectedOperationsSnapshot {
        lock(&self.actions).operations.snapshot()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn into_action_capture(
        self,
    ) -> (
        BrowserActionCursorTerminal,
        SourceOperationJournal,
        Option<BrowserActionIssueError>,
    ) {
        let cursor = match self.actions.into_inner() {
            Ok(cursor) => cursor,
            Err(poison) => {
                let mut cursor = poison.into_inner();
                let position = cursor.position();
                cursor.refuse(position, BrowserActionCursorFault::Poisoned);
                cursor
            }
        };
        (cursor.terminal(), cursor.operations, cursor.first_issue)
    }
}
#[cfg(test)]
#[path = "actions/operation_tests.rs"]
mod operation_tests;
#[cfg(test)]
#[path = "actions/tests.rs"]
mod tests;
#[cfg(test)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) use tests::{
    with_foreign_source_controller_lifetime, with_revoked_source_controller_lifetime,
    with_source_controller_artifact_control, with_source_controller_artifact_endpoint,
    with_source_controller_cleanup_control, with_source_controller_end,
    with_source_controller_endpoint, with_source_controller_lifetime,
    with_source_controller_limits,
};
