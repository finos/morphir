//! Advance the genuine process owner while servicing the same host mailbox.
use super::super::installed_observation::InstalledHostObservation;
use morphir_mck::{
    transport::process::ProcessProgress,
    workbench::model_originals::installed::{
        ConsumerAckProgress, ConsumerDrainProgress, ConsumerPendingAck, ConsumerProducerRole,
        ConsumerReceiveProgress, ConsumerTransportState, FinishedInstalledProcess,
        InstalledAdapterError, InstalledClientRun, InstalledConsumerPorts, InstalledProcessFinish,
        RunningInstalledProcess,
    },
};
use std::sync::atomic::AtomicBool;
use tokio::time::{Duration, Instant};

#[expect(
    clippy::large_enum_variant,
    reason = "One active non-cloned command retains SAME process, ports and two ACK tickets inline (272/776-byte variants); boxing adds a funded heap allocation and Drop indirection"
)]
pub(super) enum Command {
    Ordinary(Option<RunningInstalledProcess>),
    OrdinaryFinished(FinishedInstalledProcess),
    Operation(Operation),
}
enum OperationProcess {
    Running(RunningInstalledProcess),
    Finished(FinishedInstalledProcess),
}
pub(super) struct Operation {
    // Taken only during a synchronous state transition, restored before await.
    process: Option<OperationProcess>,
    ports: InstalledConsumerPorts,
    acknowledgements: [Option<ConsumerPendingAck>; 2],
    failure: Option<InstalledAdapterError>,
    #[cfg(test)]
    cutoff: Option<morphir_mck::workbench::model_originals::installed::ConsumerTestFact>,
    #[cfg(test)]
    cuts: usize,
}
impl Command {
    pub(super) fn operation(
        process: RunningInstalledProcess,
        ports: InstalledConsumerPorts,
    ) -> Self {
        Self::Operation(Operation {
            process: Some(OperationProcess::Running(process)),
            ports,
            acknowledgements: [None, None],
            failure: None,
            #[cfg(test)]
            cutoff: None,
            #[cfg(test)]
            cuts: 0,
        })
    }
    #[cfg(test)]
    pub(super) fn configure_test_cutoff(&mut self, cutoff: Option<super::TestConsumerAckCutoff>) {
        if let Self::Operation(operation) = self {
            operation.cutoff = cutoff.map(|value| match value {
                super::TestConsumerAckCutoff::Release => {
                    morphir_mck::workbench::model_originals::installed::ConsumerTestFact::Release
                }
                super::TestConsumerAckCutoff::Commit => {
                    morphir_mck::workbench::model_originals::installed::ConsumerTestFact::Commit
                }
            });
        }
    }
    #[cfg(test)]
    pub(super) fn test_cut_count(&self) -> usize {
        match self {
            Self::Operation(operation) => operation.cuts,
            _ => 0,
        }
    }
    pub(super) async fn execute(
        &mut self,
        run: &mut InstalledClientRun<'_>,
        events: &mut InstalledHostObservation,
        end: Instant,
        interrupted: &AtomicBool,
    ) -> Result<(), InstalledAdapterError> {
        match self {
            Self::Ordinary(pending) => {
                let finished = execute(run, events, pending, end, interrupted).await?;
                *self = Self::OrdinaryFinished(finished);
                Ok(())
            }
            Self::OrdinaryFinished(_) => Err(InstalledAdapterError::ObservationIncomplete),
            Self::Operation(operation) => operation.execute(run, events, end, interrupted).await,
        }
    }
    /// Synchronous consuming transfer after the awaited owner has settled.
    /// Rejected operation owners return together, before any further await.
    pub(super) fn record_terminal(self, run: &mut InstalledClientRun<'_>) -> Result<(), Self> {
        match self {
            Self::OrdinaryFinished(finished) => run
                .record_finished_process(finished)
                .map_err(|_| Self::Ordinary(None)),
            Self::Operation(mut operation) => {
                let finished = match operation.process.take() {
                    Some(OperationProcess::Finished(finished)) => finished,
                    same => {
                        operation.process = same;
                        return Err(Self::Operation(operation));
                    }
                };
                let Operation {
                    ports,
                    acknowledgements,
                    failure,
                    #[cfg(test)]
                    cutoff,
                    #[cfg(test)]
                    cuts,
                    ..
                } = operation;
                match run.record_consumer_process(ports, finished) {
                    Ok(()) => Ok(()),
                    Err(rejected) => {
                        let (ports, finished) = rejected.into_parts();
                        Err(Self::Operation(Operation {
                            process: Some(OperationProcess::Finished(finished)),
                            ports,
                            acknowledgements,
                            failure,
                            #[cfg(test)]
                            cutoff,
                            #[cfg(test)]
                            cuts,
                        }))
                    }
                }
            }
            other => Err(other),
        }
    }
    pub(super) async fn terminate(&mut self, end: Instant) -> Result<(), InstalledAdapterError> {
        match self {
            Self::Ordinary(pending) => terminate(pending, end).await,
            Self::OrdinaryFinished(_) => Ok(()),
            Self::Operation(operation) => {
                // The SAME actual owner remains here throughout cleanup.
                if let Some(OperationProcess::Running(process)) = operation.process.as_mut() {
                    let _ = process.request_termination();
                }
                loop {
                    operation.advance()?;
                    if matches!(
                        operation.process,
                        Some(OperationProcess::Finished(_)) | None
                    ) {
                        return Ok(());
                    }
                    if Instant::now() >= end {
                        return Err(InstalledAdapterError::ObservationIncomplete);
                    }
                    tokio::time::sleep_until(end.min(Instant::now() + Duration::from_millis(1)))
                        .await;
                }
            }
        }
    }
}
impl Operation {
    fn advance(&mut self) -> Result<(), InstalledAdapterError> {
        let Some(OperationProcess::Running(process)) = self.process.as_mut() else {
            return Ok(());
        };
        match process.advance() {
            ProcessProgress::Faulted(_) | ProcessProgress::ExitObserved(_) => {
                let _ = process.request_termination();
            }
            ProcessProgress::Working | ProcessProgress::Finished(_) => {}
        }
        self.reap()
    }
    fn advance_observed(
        &mut self,
        run: &mut InstalledClientRun<'_>,
        events: &mut InstalledHostObservation,
    ) -> Result<(), InstalledAdapterError> {
        let Some(OperationProcess::Running(process)) = self.process.as_mut() else {
            return Ok(());
        };
        match run.advance_consumer_process(process)? {
            ProcessProgress::Faulted(_) => {
                let _ = process.request_termination();
                self.failure = Some(InstalledAdapterError::ObservationIncomplete);
                self.ports.revoke();
                events.close();
            }
            ProcessProgress::ExitObserved(_) => {
                let _ = process.request_termination();
            }
            ProcessProgress::Working | ProcessProgress::Finished(_) => {}
        }
        self.reap()
    }
    fn reap(&mut self) -> Result<(), InstalledAdapterError> {
        let Some(OperationProcess::Running(process)) = self.process.as_mut() else {
            return Ok(());
        };
        process
            .reap_retained()
            .map_err(|_| InstalledAdapterError::ObservationIncomplete)?;
        let Some(OperationProcess::Running(process)) = self.process.take() else {
            unreachable!()
        };
        self.process = Some(match process.try_finish() {
            InstalledProcessFinish::Pending(process) => OperationProcess::Running(process),
            InstalledProcessFinish::Finished(process) => OperationProcess::Finished(process),
        });
        Ok(())
    }
    fn collect(&mut self, run: &mut InstalledClientRun<'_>) -> Result<(), InstalledAdapterError> {
        for (index, role) in [
            ConsumerProducerRole::Outer,
            ConsumerProducerRole::TransferHelper,
        ]
        .into_iter()
        .enumerate()
        {
            if let Some(ticket) = self.acknowledgements[index].as_mut() {
                #[cfg(test)]
                if self.cuts == 0
                    && let Some(kind) = self.cutoff
                {
                    if run.test_shutdown_consumer_ack(&mut self.ports, ticket, kind)? {
                        self.cuts += 1;
                    }
                }
                if run.write_consumer_retained(&mut self.ports, ticket)?
                    == ConsumerAckProgress::Complete
                {
                    self.acknowledgements[index] = None;
                }
                continue;
            }
            if !matches!(
                self.ports.transport_state(role),
                ConsumerTransportState::Collecting
            ) {
                continue;
            }
            match run.poll_consumer_operation(&mut self.ports, role)? {
                ConsumerReceiveProgress::Retained(ticket) => {
                    self.acknowledgements[index] = Some(ticket)
                }
                ConsumerReceiveProgress::Pending
                | ConsumerReceiveProgress::AwaitingAssociation
                | ConsumerReceiveProgress::Unused => {}
            }
        }
        Ok(())
    }
    async fn execute(
        &mut self,
        run: &mut InstalledClientRun<'_>,
        events: &mut InstalledHostObservation,
        end: Instant,
        interrupted: &AtomicBool,
    ) -> Result<(), InstalledAdapterError> {
        loop {
            super::check(end, interrupted)?;
            if self.failure.is_some() {
                self.advance()?;
            } else {
                self.advance_observed(run, events)?;
            }
            let drain = if self.failure.is_none() {
                match self
                    .collect(run)
                    .and_then(|()| run.drain_consumer_operation(&mut self.ports))
                {
                    Ok(progress) => progress,
                    Err(error) => {
                        self.failure = Some(error);
                        // Collector/drain revokes actual port peers and latches
                        // the first typed fault. Let actual consumer deferred
                        // cleanup run within SAME end while retaining owners.
                        events.close();
                        ConsumerDrainProgress::Pending
                    }
                }
            } else {
                ConsumerDrainProgress::Pending
            };
            if matches!(self.process, Some(OperationProcess::Finished(_))) {
                if let Some(error) = self.failure {
                    return Err(error);
                }
                if drain == ConsumerDrainProgress::Complete {
                    run.require_consumer_close(&mut self.ports)?;
                    return Ok(());
                }
            }
            if self.failure.is_some() {
                tokio::time::sleep_until(end.min(Instant::now() + Duration::from_millis(1))).await;
            } else {
                tokio::select! {
                    event = events.next() => {
                        event.ok_or(InstalledAdapterError::ObservationIncomplete)?
                            .collect(run).map_err(|_| InstalledAdapterError::ObservationIncomplete)?;
                    }
                    _ = tokio::time::sleep_until(end.min(Instant::now()+Duration::from_millis(1))) => {}
                }
            }
        }
    }
}

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

#[cfg(test)]
mod terminal_tests;
