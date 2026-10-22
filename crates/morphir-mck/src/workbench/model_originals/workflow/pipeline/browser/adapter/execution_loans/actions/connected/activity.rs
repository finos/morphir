//! Prepaid borrowed activity, not a second physical source binding or debt.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::browser::collection::{
    BrowserSourceHostAssociation, BrowserSourceHostAssociationError,
};

pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceControllerActivity
{
    stamp: BrowserLoanStamp,
    association: BrowserSourceHostAssociation,
}
impl SourceControllerActivity {
    /// Per-call logical work upper for either exact lifetime validation or
    /// business gating. The reader must prepay its own source-bounded maximum
    /// call count, including one-byte reads/EOF/descriptor/tail paths. This
    /// pays no fresh mutable quota during reading and grants no effects.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validation_work_upper()
    -> Option<usize> {
        // validate_relation_stamp does two ready() child traversals, one global
        // identity traversal and one retained child traversal. validate() may
        // call it for self, for lifetime, then via lifetime.validate: 3*4,
        // plus the binding business gate. while_business_active needs only
        // one stamp validation plus one gate, which this same upper covers.
        let relation_traversals = 3usize.checked_mul(4)?.checked_add(1)?;
        let scope=crate::workbench::model_originals::workflow::pipeline::browser::source_scope::invocation_gate_work_upper()?.checked_mul(relation_traversals)?;
        let owner_ready=size_of::<crate::workbench::model_originals::workflow::pipeline::policy::Owners>()
            .checked_add(size_of::<crate::workbench::model_originals::workflow::pipeline::installed::observation::InstalledObservationOwner>())?.checked_add(size_of::<inputs::BrowserOwnerLoans<'_>>())?
            .checked_mul(3)?;
        [
            scope,
            owner_ready,
            size_of::<Self>(),
            size_of::<SourceControllerLifetime>(),
            size_of::<BrowserLoanStamp>(),
            BrowserSourceHostAssociation::validation_work_upper()?,
        ]
        .into_iter()
        .try_fold(0usize, usize::checked_add)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn end(
        &self,
    ) -> Instant {
        self.association.end()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate(
        &self,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserInputError> {
        loans.validate_relation_stamp(&self.stamp)?;
        loans.validate_relation_stamp(&lifetime.stamp)?;
        if !self.association.same_relation(&lifetime.association) {
            return Err(source(BrowserSourceFault::ForeignSource));
        }
        lifetime.validate(loans)
    }
    /// Enter SAME child and existing journal once. The closure must not reenter
    /// source or loan gates. No physical binding/debt is cloned by this view.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn while_business_active<
        R,
    >(
        &self,
        loans: &BrowserLoans<'_, '_>,
        operation: impl FnOnce() -> R,
    ) -> Result<R, BrowserInputError> {
        loans.validate_relation_stamp(&self.stamp)?;
        self.stamp
            .while_active(|| self.association.while_current(operation))
            .map_err(source)?
            .map_err(activity_error)
    }
}
impl SourceControllerLifetime {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare_activity(
        &self,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<SourceControllerActivity, BrowserInputError> {
        self.validate(loans)?;
        let stamp = loans.prepare_relation_stamp()?;
        // Stamp backing/counters are paid by its existing constructor. Pay the
        // remaining view, copied Weak association and its retain/drop work here.
        let wrapper = size_of::<SourceControllerActivity>()
            .checked_sub(size_of::<BrowserLoanStamp>())
            .ok_or_else(|| overflow(loans.inner))?;
        let work = wrapper
            .checked_add(2 * size_of::<std::sync::atomic::AtomicUsize>())
            .ok_or_else(|| overflow(loans.inner))?;
        loans.reserve_controlled_host_storage(wrapper, 1, work)?;
        let association =
            self.while_business_active(|| self.association.duplicate_after_funding())?;
        Ok(SourceControllerActivity { stamp, association })
    }
}
pub(super) fn activity_error(error: BrowserSourceHostAssociationError) -> BrowserInputError {
    match error {
        BrowserSourceHostAssociationError::Input(error)=>error,
        BrowserSourceHostAssociationError::Host(crate::workbench::model_originals::workflow::pipeline::browser::BrowserHostTranscriptFault::End)=>inputs::BrowserInputFault::OriginalEnd.into(),
        BrowserSourceHostAssociationError::Host(error)=>inputs::BrowserInputFault::Host(error).into(),
        BrowserSourceHostAssociationError::Collection(error)=>inputs::BrowserInputFault::Collection(error).into(),
        BrowserSourceHostAssociationError::DocumentClosed=>inputs::BrowserInputFault::DocumentClosed.into(),
    }
}
