//! Fixed source-operation preparation and measured reply ownership. This is
//! separate from runtime/image association and never creates an effect grant.
use super::super::{
    adapter::{
        BrowserInputError, BrowserLoans,
        execution_loans::{
            BrowserLoanStamp, SourceControllerLifetime, SourceControllerOperationShape,
        },
    },
    inputs::BrowserInputFault,
};
use super::{ControllerTargetInput, Limits, SOURCE_COMMAND_BYTES, SOURCE_STDOUT_BOUND};
use crate::workbench::model_originals::workflow::pipeline::installed::observation::InstalledObservationFault;
use std::{ffi::OsString, mem::size_of, time::Instant};

/// One prepaid fixed source conversation, retained with the actual acquisition
/// owner. This pays logical allocations/work and is never source authorization,
/// a receipt of execution, or an estimate of browser/stdlib/kernel allocations.
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceOperationPrepayment
{
    stamp: BrowserLoanStamp,
    end: Instant,
    limits: Limits,
    operation: SourceControllerOperationShape,
}
impl SourceOperationPrepayment {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare(
        target: &ControllerTargetInput<'_>,
        limits: Limits,
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<Self, BrowserInputError> {
        // Foreign/prior source faults precede even pure layout arithmetic.
        lifetime.validate(loans)?;
        // This is the cumulative stdout capture, not the unchanged eight-byte
        // command-frame bound. Refuse an impossible fixed conversation before
        // acquisition can touch a path or allocate its physical owners.
        if limits.max_frame < SOURCE_STDOUT_BOUND {
            return Err(
                BrowserInputFault::Receiving(InstalledObservationFault::LayoutMismatch).into(),
            );
        }
        let layout = target.launch_layout().map_err(|_| overflow(loans))?;
        let operation = lifetime.operation_shape();
        let calculated = (|| {
            // The fixed driver grows the eight common Node arguments to thirteen.
            // Charge the complete sixteen-slot requested vector, including the
            // old eight-slot backing during reallocation, rather than only five
            // additional elements. Common argument payloads are paid by layout.
            let argument_slots = 16usize.checked_add(8)?;
            let argument_backing = argument_slots.checked_mul(size_of::<OsString>())?;
            // URI maximum comes from actual native loopback+u16 port and fixed
            // 32-byte base64url token. It is DATA, never a host association proof.
            let launch = "http://127.0.0.1:65535/launch?token="
                .len()
                .checked_add(43)?;
            let variant = "observed-source-opening".len();
            let extra_payload = operation
                .selection_bytes
                .checked_add(launch)?
                .checked_add(variant)?;
            // Source-owned description and actual OS argv copies plus NULs.
            let extra_copies = extra_payload.checked_mul(2)?.checked_add(5)?;
            // SAME actual source-only environment vector, literal payloads and
            // public CommandSpec/OS argument copies. No inherited environment,
            // stdlib-private allocator or VM/kernel accounting is claimed.
            let environment_payload = SOURCE_NODE_ENVIRONMENT
                .iter()
                .try_fold(0usize, |n, (key, value)| {
                    n.checked_add(key.len())?.checked_add(value.len())
                })?;
            let environment_copies = environment_payload
                .checked_mul(2)?
                .checked_add(SOURCE_NODE_ENVIRONMENT.len().checked_mul(2)?)?;
            let environment_backing =
                SOURCE_NODE_ENVIRONMENT
                    .len()
                    .checked_mul(size_of::<(OsString, OsString)>())?;
            let environment_bytes = environment_copies.checked_add(environment_backing)?;
            let environment_slots = SOURCE_NODE_ENVIRONMENT
                .len()
                .checked_mul(3)?
                .checked_add(1)?;
            let environment_work = environment_copies
                .checked_mul(4)?
                .checked_add(environment_backing)?;
            let bytes = layout
                .bytes
                .checked_add(environment_bytes)?
                .checked_add(argument_backing)?
                .checked_add(extra_copies)?
                .checked_add(size_of::<Self>())?;
            let slots = layout
                .slots
                .checked_add(argument_slots)?
                .checked_add(1)?
                .checked_add(environment_slots)?;
            // Each bounded stdout position can be examined once during the fixed
            // protocol and compared against every closed literal. Malformed bytes
            // get the same payment; a successful short reply is not the bound.
            let reply_visits = limits.max_frame.checked_mul(32)?;
            let visits = layout
                .visits
                .checked_add(environment_work)?
                .checked_add(argument_backing)?
                .checked_add(extra_copies)?
                .checked_add(size_of::<Self>())?
                .checked_add(SOURCE_COMMAND_BYTES)?
                .checked_add(SOURCE_STDOUT_BOUND)?
                .checked_add(reply_visits)?
                .checked_add(operation.alias_bytes)?;
            Some((bytes, slots, visits))
        })()
        .ok_or_else(|| overflow(loans))?;
        loans.reserve_controlled_host_storage(calculated.0, calculated.1, calculated.2)?;
        let stamp = loans.prepare_relation_stamp()?;
        Ok(Self {
            stamp,
            end: lifetime.end(),
            limits,
            operation,
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate(
        &self,
        lifetime: &SourceControllerLifetime,
        limits: Limits,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserInputError> {
        lifetime.validate(loans)?;
        loans.validate_relation_stamp(&self.stamp)?;
        if self.end != lifetime.end()
            || self.limits != limits
            || self.operation != lifetime.operation_shape()
        {
            return Err(
                BrowserInputFault::Receiving(InstalledObservationFault::LayoutMismatch).into(),
            );
        }
        Ok(())
    }
}
fn overflow(loans: &mut BrowserLoans<'_, '_>) -> BrowserInputError {
    loans.fail_collection(InstalledObservationFault::SizeOverflow)
}

// Exact maintained ws optional-accelerator branches in the selected package.
// The ordinary process launcher still clears inherited environment first.
const SOURCE_NODE_ENVIRONMENT: [(&str, &str); 2] =
    [("WS_NO_BUFFER_UTIL", "1"), ("WS_NO_UTF_8_VALIDATE", "1")];
pub(super) fn source_driver_environment() -> Vec<(OsString, OsString)> {
    let mut environment = Vec::with_capacity(SOURCE_NODE_ENVIRONMENT.len());
    for (key, value) in SOURCE_NODE_ENVIRONMENT {
        environment.push((key.into(), value.into()));
    }
    environment
}

#[cfg(test)]
#[path = "source_operation/tests.rs"]
mod tests;
