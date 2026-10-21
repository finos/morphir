//! Consuming live evidence retention. Decoded report DATA cannot issue this owner.
use super::*;
use crate::workbench::model_originals::workflow::installed_measurements as measurements;
use crate::workbench::model_originals::workflow::pipeline::wire::FailureSummary;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow) enum ConsumerRecordCompletion {
    Drained,
    Interrupted,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow) enum ConsumerAckDelivery {
    NotIssued,
    Prefix { written: usize, total: usize },
    Written { total: usize },
}

/// Issued before endpoint effects. The destination is the one inline Option in
/// LiveMeasurements; caches and actual process buffers move without conversion.
pub(super) struct ConsumerRecordReservation {
    pub(super) action_index: usize,
    pub(super) output: Option<super::projection::ReservedConsumerOutput>,
    pub(super) process: super::projection::ProcessProjection,
    pub(super) launch: super::report::LaunchData,
    pub(super) measurement_slot: Vec<measurements::InstalledClientMeasurements>,
    pub(super) failure_slot: Vec<measurements::LiveMeasurements>,
}

/// Retains the SAME unique ports and joined process, with their already funded
/// binding, issued clock, terminal phases, buffers and literal caches. There is
/// deliberately no Serialize/Deserialize or accessor back to live ports here.
pub(in crate::workbench::model_originals::workflow) struct ConsumerOperationRecord {
    pub(super) ports: InstalledConsumerPorts,
    pub(super) finished: FinishedInstalledProcess,
    pub(super) frames: [Vec<wire::DecodedConsumerEnvelope>; 2],
    pub(super) completion: ConsumerRecordCompletion,
    pub(super) first_failure: Option<FailureSummary>,
    pub(super) reservation: ConsumerRecordReservation,
}

pub struct ConsumerRecordRejected {
    fault: wire::ConsumerCodecError,
    ports: InstalledConsumerPorts,
    finished: FinishedInstalledProcess,
}
impl ConsumerRecordRejected {
    pub(in crate::workbench::model_originals::workflow) fn fault(
        &self,
    ) -> wire::ConsumerCodecError {
        self.fault
    }
    pub fn into_parts(self) -> (InstalledConsumerPorts, FinishedInstalledProcess) {
        (self.ports, self.finished)
    }
}

#[cfg(target_os = "macos")]
impl InstalledClientRun<'_> {
    pub(super) fn prepare_consumer_record(
        &mut self,
        description: &ProcessDescription,
        limits: Limits,
        binding: &super::binding::ConsumerBinding,
    ) -> Result<ConsumerRecordReservation, InstalledAdapterError> {
        let InstalledProcessPurpose::Canonical {
            action_index,
            command: InstalledCommand::Publish,
        } = description.purpose
        else {
            return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
        };
        self.reserve_storage(std::mem::size_of::<Option<ConsumerOperationRecord>>())?;
        let result = self.decode.slots(1);
        self.decoded(result)?;
        let result = self
            .receiving
            .prepare_record(ObservationRecordRole::ConsumerOperation)
            .map(|permission| permission.issue())
            .map_err(|error| *error);
        result.map_err(|error| self.observation_failure(error))?;
        let output = self.prepare_consumer_output(limits)?;
        let process = self.prepare_consumer_process_projection(description)?;
        let launch = super::report::LaunchData::prepare(self, binding, description)?;
        super::super::super::collection::grow(self.receiving, &mut self.collected.processes, 1)
            .map_err(|error| self.observation_failure(error))?;
        super::super::super::collection::grow(self.receiving, &mut self.collected.claims, 1)
            .map_err(|error| self.observation_failure(error))?;
        let slots = self.decode.slots(2);
        self.decoded(slots)?;
        let measurement_slot = self.vector(1)?;
        let failure_slot = self.vector(1)?;
        Ok(ConsumerRecordReservation {
            action_index,
            output: Some(output),
            process,
            launch,
            measurement_slot,
            failure_slot,
        })
    }

    pub fn record_consumer_process(
        &mut self,
        mut ports: InstalledConsumerPorts,
        finished: FinishedInstalledProcess,
    ) -> Result<(), ConsumerRecordRejected> {
        use super::super::super::invocation::ConsumerRegistration;
        use wire::ConsumerCodecError as Error;
        let registered = matches!(
            &self.revoker.consumer_ports,
            ConsumerRegistration::Registered(control)
                if control.ptr_eq(&Arc::downgrade(&ports.control))
        );
        // Pointer identity is checked independently of the gate's current
        // openness: this cleanup-only transfer can retain facts after a fault,
        // and cannot issue another effect or repair the original first fault.
        let same_invocation = self.revoker.same_source(&ports.control.invocation)
            && finished
                .description
                .invocation
                .ptr_eq(&ports.control.invocation);
        let same_process = finished.description.ordinal == ports.control.process_ordinal
            && finished.description.purpose == ports.control.purpose;
        let error = if !registered
            || !same_invocation
            || !same_process
            || self.collected.consumer.is_some()
            || ports.record_reservation.is_none()
        {
            Some(Error::Association)
        } else {
            None
        };
        if let Some(error) = error {
            self.consumer_fault(error);
            return Err(ConsumerRecordRejected {
                fault: error,
                ports,
                finished,
            });
        }
        if let Some(fault) = finished.outcome.first_fault() {
            self.attempt.fail(RunFault::InstalledProcessFault(*fault));
        }
        if ports.control.revoked() || !self.revoker.active() {
            // Actual port or source revocation is abandonment. Normalize it
            // after identity and the matching process fault, before requiring
            // healthy physical drain. The existing first fault stays unchanged.
            self.attempt.fail(RunFault::InstalledObservation(
                InstalledObservationError::Abandoned,
            ));
        }
        if self.attempt.ready().is_ok() && !ports.frames_drained() {
            let error = self.consumer_fault(Error::Framing);
            return Err(ConsumerRecordRejected {
                fault: error,
                ports,
                finished,
            });
        }
        let mut completion = if self.attempt.ready().is_ok() {
            ConsumerRecordCompletion::Drained
        } else {
            ConsumerRecordCompletion::Interrupted
        };
        let control = Arc::downgrade(&ports.control);
        if !self.revoker.record_consumer(control.clone(), completion) {
            // Gate closure can race the terminal metadata transfer. Preserve
            // the live evidence as interrupted, without reopening that gate.
            self.attempt.fail(RunFault::InstalledObservation(
                InstalledObservationError::Abandoned,
            ));
            completion = ConsumerRecordCompletion::Interrupted;
            if !self.revoker.record_consumer(control, completion) {
                let error = self.consumer_fault(Error::Association);
                return Err(ConsumerRecordRejected {
                    fault: error,
                    ports,
                    finished,
                });
            }
        }
        let first_failure = self.attempt.ready().err().map(RunFault::summary);
        // Reservation was issued before socketpair/spawn. Taking these values
        // neither copies literal/process bytes nor obtains fresh work/storage.
        let reservation = ports
            .record_reservation
            .take()
            .expect("validated export reservation");
        self.collected.consumer = Some(ConsumerOperationRecord {
            ports,
            finished,
            frames: std::mem::take(&mut self.collected.consumer_cache),
            completion,
            first_failure,
            reservation,
        });
        if let Some(record) = self.collected.consumer.as_mut()
            && let Err(fault) = record.project_process()
        {
            self.encoding_fault(fault);
        }
        if self.attempt.ready().is_ok() {
            let claim = {
                let record = self.collected.consumer.as_ref().expect("stored record");
                let process = record.projected_process().expect("projected record").0;
                process.stdout.utf8(self.decode).and_then(|raw| match raw {
                    Some(raw) => measurements::literal(raw, self.decode),
                    None => Ok(None),
                })
            };
            match claim {
                Ok(claim) => {
                    let record = self.collected.consumer.as_mut().expect("stored record");
                    let process = record
                        .take_projected_process()
                        .expect("single measured move");
                    self.collected.processes.push(process);
                    self.collected.claims.push(claim);
                }
                Err(error) => {
                    self.attempt.fail(RunFault::Decode(error));
                }
            }
        }
        Ok(())
    }
}

#[cfg(not(target_os = "macos"))]
impl InstalledClientRun<'_> {
    pub fn record_consumer_process(
        &mut self,
        ports: InstalledConsumerPorts,
        finished: FinishedInstalledProcess,
    ) -> Result<(), ConsumerRecordRejected> {
        let fault = wire::ConsumerCodecError::Association;
        self.attempt.fail(RunFault::InstalledConsumer(fault));
        Err(ConsumerRecordRejected {
            fault,
            ports,
            finished,
        })
    }
}

#[cfg(test)]
impl InstalledClientRun<'_> {
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn test_consumer_record(
        &self,
    ) -> Option<&ConsumerOperationRecord> {
        self.collected.consumer.as_ref()
    }
}
impl ConsumerOperationRecord {
    pub(in crate::workbench::model_originals::workflow) fn process_ordinal(&self) -> u64 {
        self.finished.description.ordinal
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow) fn completion(
        &self,
    ) -> ConsumerRecordCompletion {
        self.completion
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow) fn frames(
        &self,
        role: ConsumerProducerRole,
    ) -> &[wire::DecodedConsumerEnvelope] {
        &self.frames[match role {
            ConsumerProducerRole::Outer => 0,
            ConsumerProducerRole::TransferHelper => 1,
        }]
    }
}
