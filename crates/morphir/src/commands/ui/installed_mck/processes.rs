//! Advance the genuine process owner while servicing the same host mailbox.
use super::super::installed_observation::InstalledHostObservation;
use morphir_mck::{
    transport::process::ProcessProgress,
    workbench::model_originals::installed::{
        FinishedInstalledProcess, InstalledAdapterError, InstalledClientRun,
        InstalledProcessFinish, RunningInstalledProcess,
    },
};
use std::sync::atomic::AtomicBool;
use tokio::time::{Duration, Instant};

pub(super) async fn execute(
    run: &mut InstalledClientRun<'_>,
    events: &mut InstalledHostObservation,
    pending: &mut Option<RunningInstalledProcess>,
    end: Instant,
    interrupted: &AtomicBool,
) -> Result<FinishedInstalledProcess, InstalledAdapterError> {
    loop {
        super::check(end, interrupted)?;
        let process = pending
            .as_mut()
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        match process.advance() {
            ProcessProgress::Faulted(_) | ProcessProgress::ExitObserved(_) => {
                let _ = process.request_termination();
            }
            ProcessProgress::Working | ProcessProgress::Finished(_) => {}
        }
        // Faulted may mask ExitObserved. The owner itself proves whether a
        // consuming wait is allowed; Pending never invents exit evidence.
        process
            .reap_retained()
            .map_err(|_| InstalledAdapterError::ObservationIncomplete)?;
        let process = pending
            .take()
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        match process.try_finish() {
            InstalledProcessFinish::Finished(finished) => return Ok(finished),
            InstalledProcessFinish::Pending(process) => *pending = Some(process),
        }
        // No source, slot, connection or capacity lock survives this await.
        // collect admits the actual retained payload/cache BEFORE ACK.
        tokio::select! {
            event = events.next() => {
                event.ok_or(InstalledAdapterError::ObservationIncomplete)?
                    .collect(run).map_err(|_| InstalledAdapterError::ObservationIncomplete)?;
            }
            _ = tokio::time::sleep_until(end.min(Instant::now() + Duration::from_millis(1))) => {}
        }
    }
}

/// Error cleanup ignores an already observed interruption, but retains the
/// SAME owner on a deadline. Drop remains containment, never joined evidence.
pub(super) async fn terminate(
    pending: &mut Option<RunningInstalledProcess>,
    end: Instant,
) -> Result<(), InstalledAdapterError> {
    if let Some(process) = pending.as_mut() {
        let _ = process.request_termination();
    }
    loop {
        let Some(process) = pending.as_mut() else {
            return Ok(());
        };
        match process.advance() {
            ProcessProgress::Faulted(_) | ProcessProgress::ExitObserved(_) => {
                let _ = process.request_termination();
            }
            ProcessProgress::Working | ProcessProgress::Finished(_) => {}
        }
        process
            .reap_retained()
            .map_err(|_| InstalledAdapterError::ObservationIncomplete)?;
        let process = pending
            .take()
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        match process.try_finish() {
            InstalledProcessFinish::Finished(_) => return Ok(()),
            InstalledProcessFinish::Pending(process) => *pending = Some(process),
        }
        if Instant::now() >= end {
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        tokio::time::sleep_until(end.min(Instant::now() + Duration::from_millis(1))).await;
    }
}
