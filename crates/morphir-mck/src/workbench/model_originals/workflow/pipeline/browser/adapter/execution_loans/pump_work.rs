//! Derived work DATA for the maintained native pump's repeated guards. It
//! creates no source identity, allowance, budget, effect or physical proof.
/// Public numeric metadata, with no resource-owner or authority state.
pub struct BrowserSourcePumpGuardWork {
    pub collection_step_visits: usize,
    pub controller_probe_visits: usize,
    pub wait_source_poll_visits: usize,
}
#[cfg(target_os = "macos")]
impl super::BrowserLoans<'_, '_> {
    pub fn source_pump_guard_work_upper() -> Option<BrowserSourcePumpGuardWork> {
        use super::SourceControllerActivity;
        use crate::workbench::model_originals::workflow::pipeline::browser::{
            BrowserDocumentProducer, ControlledHostStimulus, controller::BrowserFixedController,
            source_scope,
        };
        use std::{mem::size_of, time::Instant};
        // This existing derived upper contains 13 actual parent/child
        // traversals, three ready-owner reads and the real relation/journal
        // layouts. One controlled-application validation needs <=6 traversals
        // and two ready reads. Producer.validate_host additionally validates
        // its relation stamp: <=10 traversals and three ready reads in total.
        let application = SourceControllerActivity::validation_work_upper()?;
        let producer = application
            .checked_add(size_of::<BrowserDocumentProducer>())?
            .checked_add(size_of::<usize>().checked_mul(2)?)?;
        // One source_polled poll enters exactly one actual binding gate, then
        // reads the original end and obtains its current Instant. Future/timer
        // and native-state headers are separately derived by the native owner.
        let source_poll = source_scope::invocation_gate_work_upper()?
            .checked_add(size_of::<Instant>().checked_mul(2)?)?
            .checked_add(size_of::<&ControlledHostStimulus>())?;
        // One collect step validates the application and producer, then enters
        // the take-frame gate and (when a frame exists) the retain gate. These
        // empty-tick guards are separate from prepaid payload/parser work.
        let collection = application
            .checked_add(producer)?
            .checked_add(source_poll.checked_mul(2)?)?;
        Some(BrowserSourcePumpGuardWork {
            collection_step_visits: collection,
            controller_probe_visits: BrowserFixedController::dispatch_probe_work_upper()?,
            wait_source_poll_visits: source_poll,
        })
    }
}
