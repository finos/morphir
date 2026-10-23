//! Funding affinity to the existing run and host journals. No source debt or
//! physical authority is created by this non-Clone bookkeeping value.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::browser::collection::BrowserSourceHostAssociation;

pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceBusinessOrigin {
    journal: SourceOperationIdentity,
    host: BrowserSourceHostAssociation,
}
impl SourceBusinessOrigin {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate_lifetime(
        &self,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError> {
        lifetime.validate(loans)?;
        if !self.journal.same_identity(lifetime.journal_identity()) {
            return Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::ForeignAction,
            ));
        }
        self.validate_host_association(lifetime.association())
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn original_end(
        &self,
    ) -> std::time::Instant {
        self.host.end()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn copy_work_upper()
    -> Option<usize> {
        SourceOperationIdentity::copy_work_upper()?
            .checked_add(size_of::<BrowserSourceHostAssociation>())?
            .checked_add(size_of::<std::sync::atomic::AtomicUsize>().checked_mul(2)?)
    }
    /// The envelope already prepaid this exact wrapper and both Weak counters.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn duplicate_after_funding(
        &self,
    ) -> Self {
        Self {
            journal: self.journal.duplicate_after_funding(),
            host: self.host.duplicate_after_funding(),
        }
    }
    pub(super) fn prepare(
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<Self, BrowserInputError> {
        lifetime.validate(loans)?;
        let work = Self::copy_work_upper().ok_or_else(|| overflow(loans.inner))?;
        loans.reserve_controlled_host_storage(size_of::<Self>(), 1, work)?;
        lifetime.while_business_active(|| Self {
            journal: lifetime.journal_identity().duplicate_after_funding(),
            host: lifetime.association().duplicate_after_funding(),
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate_action(
        &self,
        action: &BrowserExecutionAction<'_, '_, '_, '_, '_, '_, '_>,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError> {
        action.owner.validate_action(action, loans)?;
        action
            .owner
            .child
            .identity
            .while_active(|| {
                self.journal
                    .preflight(&lock(&action.owner.actions).operations)
                    .map_err(BrowserActionIssueError::Cursor)
            })
            .map_err(|cause| BrowserActionIssueError::Input(source(cause)))?
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate_host_association(
        &self,
        actual: &BrowserSourceHostAssociation,
    ) -> Result<(), BrowserActionIssueError> {
        if self.host.same_relation(actual) {
            Ok(())
        } else {
            Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::ForeignAction,
            ))
        }
    }
}
