//! Prepaid source-business capacity, not source or physical-effect authority.
//! Every real consumer must still validate its actual source, host and end.
use super::super::super::installed::observation::InstalledObservationFault;
use super::super::adapter::execution_loans::{SourceBusinessOrigin, SourceControllerLifetime};
use super::super::adapter::{BrowserInputError, BrowserLoans};
use std::{mem::size_of, num::NonZeroUsize, time::Instant};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceBusinessOperation {
    LaunchValidation,
    ListenerStart,
    OpeningSettlement,
    InspectionPreparation,
    InspectionSource,
    InspectionSettlement,
    ControllerDispatch,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceBusinessResource {
    RetainedBytes,
    Slots,
    Visits,
    ComparisonVisits,
    ComparisonBytes,
    ComparisonChecks,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceBusinessFundingFault {
    WrongOperation {
        expected: SourceBusinessOperation,
        actual: SourceBusinessOperation,
    },
    AlreadyConsumed(SourceBusinessOperation),
    DispatchExhausted,
    Layout {
        operation: SourceBusinessOperation,
        resource: SourceBusinessResource,
        requested: usize,
        remaining: usize,
    },
}
/// Layout DATA supplied only by the maintained concrete operation types.
#[derive(Debug, Clone, Copy, Default)]
pub(super) struct SourceBusinessResources {
    pub(super) retained_bytes: usize,
    pub(super) slots: usize,
    pub(super) visits: usize,
    pub(super) comparison_visits: usize,
    pub(super) comparison_bytes: usize,
    pub(super) comparison_checks: usize,
}
impl SourceBusinessResources {
    fn add(self, other: Self) -> Option<Self> {
        Some(Self {
            retained_bytes: self.retained_bytes.checked_add(other.retained_bytes)?,
            slots: self.slots.checked_add(other.slots)?,
            visits: self.visits.checked_add(other.visits)?,
            comparison_visits: self
                .comparison_visits
                .checked_add(other.comparison_visits)?,
            comparison_bytes: self.comparison_bytes.checked_add(other.comparison_bytes)?,
            comparison_checks: self
                .comparison_checks
                .checked_add(other.comparison_checks)?,
        })
    }
    fn multiply(self, count: usize) -> Option<Self> {
        Some(Self {
            retained_bytes: self.retained_bytes.checked_mul(count)?,
            slots: self.slots.checked_mul(count)?,
            visits: self.visits.checked_mul(count)?,
            comparison_visits: self.comparison_visits.checked_mul(count)?,
            comparison_bytes: self.comparison_bytes.checked_mul(count)?,
            comparison_checks: self.comparison_checks.checked_mul(count)?,
        })
    }
}
pub(super) struct SourceBusinessLayout {
    pub(super) launch_validation: SourceBusinessResources,
    pub(super) listener_start: SourceBusinessResources,
    pub(super) opening_settlement: SourceBusinessResources,
    pub(super) inspection_preparation: SourceBusinessResources,
    pub(super) inspection_source: SourceBusinessResources,
    pub(super) inspection_settlement: SourceBusinessResources,
    pub(super) controller_dispatch: SourceBusinessResources,
}
impl SourceBusinessLayout {
    pub(super) fn resources(&self, operation: SourceBusinessOperation) -> SourceBusinessResources {
        match operation {
            SourceBusinessOperation::LaunchValidation => self.launch_validation,
            SourceBusinessOperation::ListenerStart => self.listener_start,
            SourceBusinessOperation::OpeningSettlement => self.opening_settlement,
            SourceBusinessOperation::InspectionPreparation => self.inspection_preparation,
            SourceBusinessOperation::InspectionSource => self.inspection_source,
            SourceBusinessOperation::InspectionSettlement => self.inspection_settlement,
            SourceBusinessOperation::ControllerDispatch => self.controller_dispatch,
        }
    }
}
enum OnceAllowance {
    Available(SourceBusinessResources),
    Consumed,
}
impl OnceAllowance {
    fn take(
        &mut self,
        operation: SourceBusinessOperation,
    ) -> Result<SourceBusinessResources, SourceBusinessFundingFault> {
        match std::mem::replace(self, Self::Consumed) {
            Self::Available(resources) => Ok(resources),
            Self::Consumed => Err(SourceBusinessFundingFault::AlreadyConsumed(operation)),
        }
    }
}
enum DispatchAllowances {
    Available {
        remaining: NonZeroUsize,
        resources: SourceBusinessResources,
    },
    Exhausted,
}
impl DispatchAllowances {
    fn take(&mut self) -> Result<SourceBusinessResources, SourceBusinessFundingFault> {
        match self {
            Self::Available {
                remaining,
                resources,
            } => {
                let selected = *resources;
                match NonZeroUsize::new(remaining.get() - 1) {
                    Some(next) => *remaining = next,
                    None => *self = Self::Exhausted,
                }
                Ok(selected)
            }
            Self::Exhausted => Err(SourceBusinessFundingFault::DispatchExhausted),
        }
    }
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceBusinessEnvelope
{
    origin: SourceBusinessOrigin,
    launch: OnceAllowance,
    listener: OnceAllowance,
    opening: OnceAllowance,
    inspection_preparation: OnceAllowance,
    inspection_source: OnceAllowance,
    inspection_settlement: OnceAllowance,
    dispatch: DispatchAllowances,
    first: Option<SourceBusinessFundingFault>,
}
/// No constructor or Clone. This is moved precharged capacity only. Its origin
/// is checked separately by the fixed source operation before any mutation.
pub struct SourceBusinessCredit {
    origin: SourceBusinessOrigin,
    operation: SourceBusinessOperation,
    resources: SourceBusinessResources,
    first: Option<SourceBusinessFundingFault>,
}
fn overflow(loans: &mut BrowserLoans<'_, '_>) -> BrowserInputError {
    loans.fail_collection(InstalledObservationFault::SizeOverflow)
}
impl SourceBusinessEnvelope {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare(
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<Self, BrowserInputError> {
        lifetime.validate(loans)?;
        // Count is derived ONCE from the immutable original end. The fixed
        // physical owner enforces at least one millisecond between advances;
        // document notifications may collect DATA without spending a tick.
        let count = usize::try_from(
            lifetime
                .end()
                .saturating_duration_since(Instant::now())
                .as_nanos()
                .div_ceil(1_000_000),
        )
        .ok()
        .and_then(|n| n.checked_add(2))
        .and_then(NonZeroUsize::new)
        .ok_or_else(|| overflow(loans))?;
        let mut layout =
            super::source_progress::business_layout().ok_or_else(|| overflow(loans))?;
        // The actual source shape sums BOTH previously compared alias operands.
        // No caller-authored byte/count bound is accepted here.
        let alias = lifetime.operation_shape().alias_bytes;
        layout.inspection_preparation = layout
            .inspection_preparation
            .add(SourceBusinessResources {
                visits: alias,
                comparison_visits: 2,
                comparison_bytes: alias,
                comparison_checks: 1,
                ..SourceBusinessResources::default()
            })
            .ok_or_else(|| overflow(loans))?;
        // Every moved credit includes its actual wrapper and duplicate/drop
        // work for BOTH existing nominal weak journal links. No new binding,
        // journal, resource policy or physical allocator bound is introduced.
        let credit_work = size_of::<SourceBusinessCredit>()
            .checked_add(SourceBusinessOrigin::copy_work_upper().ok_or_else(|| overflow(loans))?)
            .ok_or_else(|| overflow(loans))?;
        let credit = SourceBusinessResources {
            retained_bytes: size_of::<SourceBusinessCredit>(),
            slots: 1,
            visits: credit_work,
            ..SourceBusinessResources::default()
        };
        let mut total = SourceBusinessResources {
            retained_bytes: size_of::<Self>(),
            slots: 1,
            visits: size_of::<Self>(),
            ..SourceBusinessResources::default()
        };
        for operation in [
            SourceBusinessOperation::LaunchValidation,
            SourceBusinessOperation::ListenerStart,
            SourceBusinessOperation::OpeningSettlement,
            SourceBusinessOperation::InspectionPreparation,
            SourceBusinessOperation::InspectionSource,
            SourceBusinessOperation::InspectionSettlement,
        ] {
            total = total
                .add(
                    layout
                        .resources(operation)
                        .add(credit)
                        .ok_or_else(|| overflow(loans))?,
                )
                .ok_or_else(|| overflow(loans))?;
        }
        total = total
            .add(
                layout
                    .controller_dispatch
                    .add(credit)
                    .ok_or_else(|| overflow(loans))?
                    .multiply(count.get())
                    .ok_or_else(|| overflow(loans))?,
            )
            .ok_or_else(|| overflow(loans))?;
        loans.reserve_controlled_host_storage(total.retained_bytes, total.slots, total.visits)?;
        loans.reserve_source_business_comparison(
            lifetime,
            total.comparison_visits,
            total.comparison_bytes,
            total.comparison_checks,
        )?;
        let origin = lifetime.prepare_business_origin(loans)?;
        Ok(Self {
            origin,
            launch: OnceAllowance::Available(layout.launch_validation),
            listener: OnceAllowance::Available(layout.listener_start),
            opening: OnceAllowance::Available(layout.opening_settlement),
            inspection_preparation: OnceAllowance::Available(layout.inspection_preparation),
            inspection_source: OnceAllowance::Available(layout.inspection_source),
            inspection_settlement: OnceAllowance::Available(layout.inspection_settlement),
            dispatch: DispatchAllowances::Available {
                remaining: count,
                resources: layout.controller_dispatch,
            },
            first: None,
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn take(
        &mut self,
        operation: SourceBusinessOperation,
    ) -> Result<SourceBusinessCredit, SourceBusinessFundingFault> {
        if let Some(first) = self.first {
            return Err(first);
        }
        let resource = match operation {
            SourceBusinessOperation::LaunchValidation => self.launch.take(operation),
            SourceBusinessOperation::ListenerStart => self.listener.take(operation),
            SourceBusinessOperation::OpeningSettlement => self.opening.take(operation),
            SourceBusinessOperation::InspectionPreparation => {
                self.inspection_preparation.take(operation)
            }
            SourceBusinessOperation::InspectionSource => self.inspection_source.take(operation),
            SourceBusinessOperation::InspectionSettlement => {
                self.inspection_settlement.take(operation)
            }
            SourceBusinessOperation::ControllerDispatch => self.dispatch.take(),
        };
        match resource {
            Ok(resources) => Ok(SourceBusinessCredit {
                origin: self.origin.duplicate_after_funding(),
                operation,
                resources,
                first: None,
            }),
            Err(first) => {
                self.first = Some(first);
                Err(first)
            }
        }
    }
}
impl SourceBusinessCredit {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn require_operation(
        &mut self,
        expected: SourceBusinessOperation,
    ) -> Result<(), SourceBusinessFundingFault> {
        if let Some(first) = self.first {
            return Err(first);
        }
        if self.operation != expected {
            let first = SourceBusinessFundingFault::WrongOperation {
                expected,
                actual: self.operation,
            };
            self.first = Some(first);
            return Err(first);
        }
        Ok(())
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn origin(
        &self,
    ) -> &SourceBusinessOrigin {
        &self.origin
    }
    fn checked(
        &mut self,
        resource: SourceBusinessResource,
        requested: usize,
        remaining: usize,
    ) -> Result<usize, SourceBusinessFundingFault> {
        if let Some(first) = self.first {
            return Err(first);
        }
        match remaining.checked_sub(requested) {
            Some(next) => Ok(next),
            None => {
                let first = SourceBusinessFundingFault::Layout {
                    operation: self.operation,
                    resource,
                    requested,
                    remaining,
                };
                self.first = Some(first);
                Err(first)
            }
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn storage(
        &mut self,
        bytes: usize,
        slots: usize,
        visits: usize,
    ) -> Result<(), SourceBusinessFundingFault> {
        let bytes = self.checked(
            SourceBusinessResource::RetainedBytes,
            bytes,
            self.resources.retained_bytes,
        )?;
        let slots = self.checked(SourceBusinessResource::Slots, slots, self.resources.slots)?;
        let visits = self.checked(
            SourceBusinessResource::Visits,
            visits,
            self.resources.visits,
        )?;
        self.resources.retained_bytes = bytes;
        self.resources.slots = slots;
        self.resources.visits = visits;
        Ok(())
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn comparison(
        &mut self,
        visits: usize,
        bytes: usize,
        checks: usize,
    ) -> Result<(), SourceBusinessFundingFault> {
        let visits = self.checked(
            SourceBusinessResource::ComparisonVisits,
            visits,
            self.resources.comparison_visits,
        )?;
        let bytes = self.checked(
            SourceBusinessResource::ComparisonBytes,
            bytes,
            self.resources.comparison_bytes,
        )?;
        let checks = self.checked(
            SourceBusinessResource::ComparisonChecks,
            checks,
            self.resources.comparison_checks,
        )?;
        self.resources.comparison_visits = visits;
        self.resources.comparison_bytes = bytes;
        self.resources.comparison_checks = checks;
        Ok(())
    }
}

#[cfg(test)]
#[path = "source_business_tests.rs"]
mod tests;
