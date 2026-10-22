//! Genuine source1 inspection-boundary input and sealed logical settlement.
//! This owner performs no inspection, controller I/O or physical completion.
use super::borrowed::{OpeningToken, association_error, current_source_gate, with_controller_step};
use super::*;
use crate::workbench::model_originals::workflow::pipeline::browser::{
    BrowserDocumentProducer, BrowserHostTranscript, ControlledHostStimulus,
    collection::BrowserSourceHostAssociation,
};
use std::time::Instant;

pub struct BrowserOwnedInspectionBoundary<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied> {
    action: BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
}

/// Borrows one exact outstanding source1 action. The SAME prepaid weak host
/// association carries no cloned binding debt or independent physical owner.
pub struct BrowserInspectionBoundarySource<'a> {
    action: &'a dyn OpeningToken,
    association: BrowserSourceHostAssociation,
}
impl BrowserInspectionBoundarySource<'_> {
    pub fn validate_host(
        &self,
        producer: &BrowserDocumentProducer,
        transcript: &BrowserHostTranscript,
        stimulus: &ControlledHostStimulus,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<Instant, BrowserActionIssueError> {
        self.action.validate(loans)?;
        self.association
            .validate_host(producer, transcript, stimulus, loans)
            .map_err(association_error)
    }
    /// Only the maintained native shell's fixed controller step belongs in
    /// this scoped gate. Its independent first fault and real owners remain
    /// required. No source/loan API may be re-entered inside the callback.
    pub fn with_prepared_controller_step<R, F>(
        &self,
        loans: &mut BrowserLoans<'_, '_>,
        advance: F,
    ) -> Result<R, BrowserActionIssueError>
    where
        F: for<'gate> FnOnce(BrowserPreparedControllerStep<'gate>) -> R,
    {
        with_controller_step(self.action, &self.association, loans, advance)
    }
}
impl<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    BrowserOwnedInspectionBoundary<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare(
        action: BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<
        Self,
        (
            BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
            BrowserActionIssueError,
        ),
    > {
        let checked = (|| {
            lifetime.validate_action_relation(&action, loans)?;
            let BrowserActionKind::AwaitConnectedBoundary {
                pending,
                boundary: BrowserConnectedBoundary::InspectionPending,
            } = action.kind()
            else {
                return Err(BrowserActionIssueError::Cursor(
                    BrowserActionCursorFault::UnsupportedOperation,
                ));
            };
            if action.position() != lifetime.operation_shape().boundary_position {
                return Err(BrowserActionIssueError::Cursor(
                    BrowserActionCursorFault::UnsupportedOperation,
                ));
            }
            let bytes = size_of::<Self>();
            let work = bytes
                .checked_add(pending.len())
                .and_then(|n| n.checked_add(lifetime.pending_alias().len()))
                .and_then(|n| n.checked_add(2 * size_of::<usize>()))
                .ok_or_else(|| overflow(loans.inner))?;
            loans.reserve_controlled_host_storage(bytes, 1, work)?;
            // This is an actual source-alias comparison, so its exact byte
            // operands and check also debit the SAME comparison owner.
            let comparison_bytes = pending
                .len()
                .checked_add(lifetime.pending_alias().len())
                .ok_or_else(|| overflow(loans.inner))?;
            let (_, _, comparison) = loans
                .inner
                .physical_owners()
                .map_err(BrowserInputError::from)?;
            use crate::workbench::model_originals::workflow::observation_check::CompareResource;
            for (resource, amount) in [
                (CompareResource::StructuralVisits, 2),
                (CompareResource::ComparisonBytes, comparison_bytes),
                (CompareResource::Checks, 1),
            ] {
                comparison
                    .charge(resource, amount)
                    .map_err(inputs::BrowserInputFault::Comparison)
                    .map_err(BrowserInputError::from)?;
            }
            current_source_gate(&action, lifetime.association(), loans, || {
                if pending == lifetime.pending_alias() {
                    Ok(())
                } else {
                    Err(BrowserActionIssueError::Cursor(
                        BrowserActionCursorFault::ForeignAction,
                    ))
                }
            })?
        })();
        match checked {
            Ok(()) => Ok(Self { action }),
            Err(cause) => Err((action, cause)),
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn source<'b>(
        &'b self,
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<BrowserInspectionBoundarySource<'b>, BrowserActionIssueError> {
        lifetime.validate_action_relation(&self.action, loans)?;
        let bytes = size_of::<BrowserInspectionBoundarySource<'_>>();
        let work = bytes
            .checked_add(2 * size_of::<std::sync::atomic::AtomicUsize>())
            .ok_or_else(|| overflow(loans.inner))?;
        loans.reserve_controlled_host_storage(bytes, 1, work)?;
        let association = current_source_gate(&self.action, lifetime.association(), loans, || {
            lifetime.association().duplicate_after_funding()
        })?;
        Ok(BrowserInspectionBoundarySource {
            action: &self.action,
            association,
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn settle_controller_reply(
        &mut self,
        reply: &MeasuredInspectionReply,
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError> {
        lifetime.validate_action_relation(&self.action, loans)?;
        if self.action.position() != lifetime.operation_shape().boundary_position {
            return Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::ForeignAction,
            ));
        }
        lifetime.association().prepare_validation(loans)?;
        let action = &mut self.action;
        let owner = action.owner;
        owner
            .child
            .identity
            .while_active(|| {
                lifetime
                    .association()
                    .while_current(|| {
                        let mut cursor = lock(&owner.actions);
                        match cursor.phase {
                            Phase::Issued(position)
                                if position == action.position()
                                    && matches!(action.state, TokenState::Outstanding) =>
                            {
                                ()
                            }
                            Phase::Refused { cause, .. } => {
                                return Err(BrowserActionIssueError::Cursor(cause));
                            }
                            _ => {
                                return Err(BrowserActionIssueError::Cursor(
                                    BrowserActionCursorFault::ForeignAction,
                                ));
                            }
                        }
                        if !reply.matches(&cursor.operations) {
                            return Err(BrowserActionIssueError::Cursor(
                                BrowserActionCursorFault::ForeignAction,
                            ));
                        }
                        if !reply.accepted_by(&cursor.operations) {
                            return Err(BrowserActionIssueError::Cursor(
                                BrowserActionCursorFault::UnsupportedOperation,
                            ));
                        }
                        cursor.phase = if cursor.inputs.len() == 0 {
                            Phase::Exhausted
                        } else {
                            Phase::Ready
                        };
                        action.state = TokenState::Consumed;
                        Ok(())
                    })
                    .map_err(association_error)?
            })
            .map_err(|cause| BrowserActionIssueError::Input(source(cause)))?
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn refuse_controller(
        &mut self,
        cause: BrowserActionIssueError,
    ) {
        let mut cursor = lock(&self.action.owner.actions);
        cursor.first_issue.get_or_insert(cause);
        cursor.refuse(
            self.action.position(),
            BrowserActionCursorFault::OperationRefused,
        );
        self.action.state = TokenState::Refused;
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn inspect_controller_cause<
        R,
    >(
        &self,
        inspect: impl FnOnce(&BrowserActionIssueError) -> R,
    ) -> R {
        let cursor = lock(&self.action.owner.actions);
        inspect(
            cursor
                .first_issue
                .as_ref()
                .expect("failed controller retained actual cause"),
        )
    }
}

#[cfg(test)]
#[path = "inspection_tests.rs"]
mod tests;
