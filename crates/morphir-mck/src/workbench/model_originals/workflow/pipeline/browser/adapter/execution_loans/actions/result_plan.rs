//! Source-paid inactive descriptor snapshot. Direct slice iteration never
//! rescans the action source. No action, invocation or transport grant is issued.
use super::*;
use crate::workbench::model_originals::workflow::{input, pairing::PairedRun};

pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceResultPlan<
    'case,
> {
    productions: Vec<SourceResultDescriptor<'case>>,
    settlements: Vec<SourceResultDescriptor<'case>>,
    stamp: BrowserLoanStamp,
    journal: SourceOperationIdentity,
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceResultDescriptor<
    'case,
> {
    position: usize,
    production: SourceResultOperation,
    effect: &'case input::EffectRef,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) enum SourceResultOperation {
    Execute,
    Prepare,
    /// Describes consuming an existing prepared result. Zero production slots.
    Settle,
}
impl<'case> SourceResultDescriptor<'case> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn action_position(
        &self,
    ) -> usize {
        self.position
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn production(
        &self,
    ) -> SourceResultOperation {
        self.production
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn effect(
        &self,
    ) -> &'case input::EffectRef {
        self.effect
    }
}
impl<'case> SourceResultPlan<'case> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn invocations(
        &self,
    ) -> std::slice::Iter<'_, SourceResultDescriptor<'case>> {
        self.productions.iter()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn settlements(
        &self,
    ) -> std::slice::Iter<'_, SourceResultDescriptor<'case>> {
        self.settlements.iter()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate(
        &self,
        lifetime: &SourceControllerLifetime,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserInputError> {
        loans.validate_relation_stamp(&self.stamp)?;
        if !self.journal.same_identity(lifetime.journal_identity()) {
            return Err(source(BrowserSourceFault::ForeignSource));
        }
        lifetime.validate(loans)
    }
}
impl<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare_result_plan(
        &self,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<SourceResultPlan<'case>, BrowserInputError> {
        loans.ready_for_run(self.global, self.child)?;
        if self.core.source().paired().scenario().current().is_none() {
            return Err(source(BrowserSourceFault::ForeignSource));
        }
        let PairedRun::Client { actions, .. } = self.core.source().paired().run() else {
            return Err(source(BrowserSourceFault::ForeignSource));
        };
        // Count and populate are two real source passes. Debit both before the
        // first scan, independently of the requested descriptor backing.
        let scan = actions
            .len()
            .checked_mul(size_of::<input::ClientAction>())
            .and_then(|n| n.checked_mul(2))
            .and_then(|n| n.checked_add(size_of::<SourceResultPlan<'_>>()))
            .ok_or_else(|| overflow(loans.inner))?;
        // The stamp and journal smart constructors below fund those embedded
        // headers. This wrapper pays only the vectors and remaining padding.
        let wrapper = size_of::<SourceResultPlan<'_>>()
            .checked_sub(size_of::<BrowserLoanStamp>())
            .and_then(|n| n.checked_sub(size_of::<SourceOperationIdentity>()))
            .ok_or_else(|| overflow(loans.inner))?;
        loans.reserve_controlled_host_storage(wrapper, 1, scan)?;
        let (production_count, settlement_count) = self
            .child
            .identity
            .while_active(|| {
                actions
                    .iter()
                    .fold(
                        (0usize, 0usize),
                        |(productions, settlements), action| match action {
                            input::ClientAction::ExecutePendingCore { .. }
                            | input::ClientAction::PreparePendingCore { .. } => {
                                (productions + 1, settlements)
                            }
                            input::ClientAction::SettlePreparedCore { .. } => {
                                (productions, settlements + 1)
                            }
                            _ => (productions, settlements),
                        },
                    )
            })
            .map_err(source)?;
        let count = production_count
            .checked_add(settlement_count)
            .ok_or_else(|| overflow(loans.inner))?;
        let bytes = count
            .checked_mul(size_of::<SourceResultDescriptor<'_>>())
            .ok_or_else(|| overflow(loans.inner))?;
        loans.reserve_controlled_host_storage(bytes, count, bytes)?;
        let (productions, settlements) = self
            .child
            .identity
            .while_active(|| {
                let mut productions = Vec::new();
                let mut settlements = Vec::new();
                productions.try_reserve_exact(production_count)?;
                settlements.try_reserve_exact(settlement_count)?;
                Ok::<_, std::collections::TryReserveError>((productions, settlements))
            })
            .map_err(source)?
            .map_err(|_| loans.fail_collection(InstalledObservationFault::Allocation))?;
        let extra = productions
            .capacity()
            .checked_sub(production_count)
            .and_then(|n| n.checked_add(settlements.capacity().checked_sub(settlement_count)?))
            .ok_or_else(|| overflow(loans.inner))?;
        let extra_bytes = extra
            .checked_mul(size_of::<SourceResultDescriptor<'_>>())
            .ok_or_else(|| overflow(loans.inner))?;
        // Neither backing has been adopted or populated yet. Pay actual excess
        // requested capacity and typed slots before retaining either vector.
        loans.reserve_controlled_host_storage(extra_bytes, extra, 0)?;
        SourceOperationIdentity::fund(loans.inner)?;
        let stamp = loans.prepare_relation_stamp()?;
        self.child
            .identity
            .while_active(|| {
                let mut productions = productions;
                let mut settlements = settlements;
                for (position, action) in actions.iter().enumerate() {
                    let (production, effect) = match action {
                        input::ClientAction::ExecutePendingCore { effect } => {
                            (SourceResultOperation::Execute, effect)
                        }
                        input::ClientAction::PreparePendingCore { effect } => {
                            (SourceResultOperation::Prepare, effect)
                        }
                        input::ClientAction::SettlePreparedCore { effect } => {
                            (SourceResultOperation::Settle, effect)
                        }
                        _ => continue,
                    };
                    let descriptor = SourceResultDescriptor {
                        position,
                        production,
                        effect,
                    };
                    match production {
                        SourceResultOperation::Execute | SourceResultOperation::Prepare => {
                            productions.push(descriptor)
                        }
                        SourceResultOperation::Settle => settlements.push(descriptor),
                    }
                }
                let cursor = lock(&self.actions);
                SourceResultPlan {
                    productions,
                    settlements,
                    stamp,
                    journal: cursor.operations.identity_after_funding(),
                }
            })
            .map_err(source)
    }
}
