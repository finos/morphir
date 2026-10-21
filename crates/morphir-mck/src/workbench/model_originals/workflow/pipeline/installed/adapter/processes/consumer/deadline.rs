//! Pure qualified-Darwin deadline arithmetic. No clock sampling or authority.
use std::time::Instant;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow) enum DeadlineError {
    InvalidTimebase,
    BracketReversed,
    Expired,
    InsufficientRemaining,
    TickProductOverflow,
    DurationOverflow,
    DeadlineOverflow,
    OutsideQualifiedRange,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) struct Timebase {
    numerator: u32,
    denominator: u32,
}
impl Timebase {
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn new(
        numerator: u32,
        denominator: u32,
    ) -> Result<Self, DeadlineError> {
        if numerator == 0 || denominator == 0 {
            return Err(DeadlineError::InvalidTimebase);
        }
        Ok(Self {
            numerator,
            denominator,
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn numerator(
        &self,
    ) -> u32 {
        self.numerator
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn denominator(
        &self,
    ) -> u32 {
        self.denominator
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn tick_guard_ns(
        &self,
    ) -> u64 {
        // Both nonzero values originate in u32. Integer ceil cannot overflow
        // here and is never zero; no floating conversion or early truncation.
        let numerator = u64::from(self.numerator);
        let denominator = u64::from(self.denominator);
        numerator.div_ceil(denominator)
    }
}

#[derive(Debug, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) struct DarwinContinuousDeadline
{
    calibrated_at_ns: u64,
    end_ns: u64,
    timebase: Timebase,
}
impl DarwinContinuousDeadline {
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn calibrated_at_ns(
        &self,
    ) -> u64 {
        self.calibrated_at_ns
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn end_ns(
        &self,
    ) -> u64 {
        self.end_ns
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn timebase(
        &self,
    ) -> Timebase {
        self.timebase
    }
}

/// Caller supplies the SAME original effective end and a genuine qualified
/// bracket. This pure result cannot prove that those inputs were observed.
pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn export(
    original_end: Instant,
    before: Instant,
    sampled_ticks: u64,
    after: Instant,
    timebase: Timebase,
) -> Result<DarwinContinuousDeadline, DeadlineError> {
    if after < before {
        return Err(DeadlineError::BracketReversed);
    }
    let remaining = original_end
        .checked_duration_since(after)
        .filter(|remaining| !remaining.is_zero())
        .ok_or(DeadlineError::Expired)?;
    let remaining_ns =
        u64::try_from(remaining.as_nanos()).map_err(|_| DeadlineError::DurationOverflow)?;
    let numerator = u64::from(timebase.numerator);
    let denominator = u64::from(timebase.denominator);
    // Match pinned libuv's u64 multiplication BEFORE division. A u128 final
    // quotient fitting u64 cannot repair an overflowing producer expression.
    let calibrated_at_ns = sampled_ticks
        .checked_mul(numerator)
        .ok_or(DeadlineError::TickProductOverflow)?
        / denominator;
    let guard = timebase.tick_guard_ns();
    if remaining_ns <= guard {
        return Err(DeadlineError::InsufficientRemaining);
    }
    let end_ns = calibrated_at_ns
        .checked_add(remaining_ns - guard)
        .ok_or(DeadlineError::DeadlineOverflow)?;
    let last_safe_tick = u64::MAX / numerator;
    let last_qualified_ns = last_safe_tick
        .checked_mul(numerator)
        .ok_or(DeadlineError::TickProductOverflow)?
        / denominator;
    if end_ns > last_qualified_ns {
        return Err(DeadlineError::OutsideQualifiedRange);
    }
    Ok(DarwinContinuousDeadline {
        calibrated_at_ns,
        end_ns,
        timebase,
    })
}
