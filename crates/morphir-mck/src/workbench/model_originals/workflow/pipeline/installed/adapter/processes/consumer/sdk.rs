//! Linear adapter projection. No decoded payloads or producer-issued authority.
use super::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConsumerTransportState {
    Collecting,
    /// Actual Close cached and parent ACK write completed. This does not prove
    /// that the producer read it, performed an effect or joined a process.
    Closed,
    /// Real empty helper EOF plus SAME ACK-completed native no-helper Close.
    Unused,
}
#[cfg(not(target_os = "macos"))]
impl InstalledConsumerPorts {
    pub fn transport_state(&self, _role: ConsumerProducerRole) -> ConsumerTransportState {
        ConsumerTransportState::Collecting
    }
}
impl InstalledClientRun<'_> {
    pub fn advance_consumer_process<'process>(
        &mut self,
        process: &'process mut RunningInstalledProcess,
    ) -> Result<crate::transport::process::ProcessProgress<'process>, InstalledAdapterError> {
        self.work_ready()?;
        let ConsumerWindow::Bound(end) = self.revoker.consumer_window else {
            return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
        };
        self.consumer_end(end)?;
        if !self.revoker.matches(&process.description.invocation) {
            return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
        }
        let progress = process.advance();
        if let crate::transport::process::ProcessProgress::Faulted(fault) = &progress {
            self.attempt.fail(RunFault::InstalledProcessFault(**fault));
        }
        Ok(progress)
    }
    pub fn consumer_observation(&self) -> ConsumerObservationSelection {
        self.revoker.consumer_selection
    }
    pub fn copy_command_arguments<'arg>(
        &mut self,
        arguments: impl ExactSizeIterator<Item = &'arg OsStr>,
    ) -> Result<Vec<OsString>, InstalledAdapterError> {
        let length = arguments.len();
        let mut values = self.vector(length)?;
        for argument in arguments {
            if values.len() == length {
                return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
            }
            values.push(self.copy_command_operand(argument)?);
        }
        if values.len() != length {
            return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
        }
        Ok(values)
    }
    pub fn prepare_consumer_operation(
        &mut self,
        command: ConsumerProcessCommand<'_>,
        end: Instant,
        implementation: &data::ImplementationObservation,
    ) -> Result<(PreparedInstalledConsumerProcess, InstalledConsumerPorts), InstalledAdapterError>
    {
        #[cfg(target_os = "macos")]
        return self
            .prepare_clocked_observed_consumer_process(command, end, implementation)
            .map_err(|_| InstalledAdapterError::ObservationIncomplete);
        #[cfg(not(target_os = "macos"))]
        {
            let _ = (command, end, implementation);
            self.attempt.fail(RunFault::InstalledConsumer(
                wire::ConsumerCodecError::ClockBasis,
            ));
            Err(InstalledAdapterError::ObservationIncomplete)
        }
    }
    /// Retain the SAME already-observed implementation and selected runtime
    /// before endpoint effects. The borrowed preparation remains available for
    /// raw transport controls; it does not issue this partial-context record.
    pub fn prepare_retained_consumer_operation(
        &mut self,
        command: ConsumerProcessCommand<'_>,
        end: Instant,
        implementation: data::ImplementationObservation,
    ) -> Result<(PreparedInstalledConsumerProcess, InstalledConsumerPorts), InstalledAdapterError>
    {
        self.work_ready()?;
        if self.collected.consumer_context.is_some() {
            return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
        }
        self.reserve_storage(std::mem::size_of::<crate::workbench::model_originals::workflow::installed_measurements::ConsumerPrefixContext>())?;
        let slots = self.decode.slots(1);
        self.decoded(slots)?;
        let selected = super::super::super::selections::runtime_selection(
            self.collected,
            self.decode,
            self.receiving,
        )
        .map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })?;
        let result = self.prepare_consumer_operation(command, end, &implementation);
        self.collected.consumer_context=Some(crate::workbench::model_originals::workflow::installed_measurements::ConsumerPrefixContext{implementation,selection:selected});
        result
    }
    pub fn poll_consumer_operation(
        &mut self,
        ports: &mut InstalledConsumerPorts,
        role: ConsumerProducerRole,
    ) -> Result<ConsumerReceiveProgress, InstalledAdapterError> {
        #[cfg(target_os = "macos")]
        return self
            .poll_consumer_frame(ports, role)
            .map_err(|_| InstalledAdapterError::ObservationIncomplete);
        #[cfg(not(target_os = "macos"))]
        {
            let _ = (ports, role);
            Err(InstalledAdapterError::ObservationIncomplete)
        }
    }
    pub fn write_consumer_retained(
        &mut self,
        ports: &mut InstalledConsumerPorts,
        ticket: &mut ConsumerPendingAck,
    ) -> Result<ConsumerAckProgress, InstalledAdapterError> {
        #[cfg(target_os = "macos")]
        return self
            .write_consumer_ack(ports, ticket)
            .map_err(|_| InstalledAdapterError::ObservationIncomplete);
        #[cfg(not(target_os = "macos"))]
        {
            let _ = (ports, ticket);
            Err(InstalledAdapterError::ObservationIncomplete)
        }
    }
    pub fn require_consumer_close(
        &mut self,
        ports: &mut InstalledConsumerPorts,
    ) -> Result<(), InstalledAdapterError> {
        #[cfg(target_os = "macos")]
        {
            self.check_consumer_ports(ports)
                .map_err(|_| InstalledAdapterError::ObservationIncomplete)?;
            if ports.frames_drained() {
                return Ok(());
            }
            ports.control.revoke();
            self.consumer_fault(wire::ConsumerCodecError::Framing);
        }
        Err(InstalledAdapterError::ObservationIncomplete)
    }
    /// Physical terminal EOF on both SAME endpoints, separately from logical
    /// cached Close/ACK. Pending keeps these actual ports for a later step.
    pub fn drain_consumer_operation(
        &mut self,
        ports: &mut InstalledConsumerPorts,
    ) -> Result<ConsumerDrainProgress, InstalledAdapterError> {
        #[cfg(target_os = "macos")]
        return self
            .drain_consumer_frames(ports)
            .map_err(|_| InstalledAdapterError::ObservationIncomplete);
        #[cfg(not(target_os = "macos"))]
        {
            let _ = ports;
            Err(InstalledAdapterError::ObservationIncomplete)
        }
    }
}
