//! Preissued output/work and same-owner process projection. No saved DATA grants.
use super::*;
use crate::workbench::model_originals::workflow::{Items, Natural, installed_measurements as data};
use serde::Serialize;
#[path = "preflight.rs"]
mod preflight;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow) enum ConsumerEncodingFault {
    Limit,
    WorkLimit,
    Unsupported,
    Serialization,
    PriorFault,
}
#[derive(Debug)]
pub(in crate::workbench::model_originals::workflow) struct OutputRequirements {
    report_limit: usize,
    diagnostic: usize,
    retained: usize,
    visits: usize,
    stdout: usize,
    stderr: usize,
}
pub(in crate::workbench::model_originals::workflow) struct ReservedConsumerOutput {
    destination: Vec<u8>,
    requirements: OutputRequirements,
    prefixes: Option<PrefixPair>,
}
impl std::fmt::Debug for ReservedConsumerOutput {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ReservedConsumerOutput")
            .field("requirements", &self.requirements)
            .finish_non_exhaustive()
    }
}
struct PrefixPair;
pub(in crate::workbench::model_originals::workflow) struct IssuedPrefixProjection {
    _private: (),
}
impl PrefixPair {
    fn split(self) -> (IssuedPrefixProjection, IssuedPrefixProjection) {
        (
            IssuedPrefixProjection { _private: () },
            IssuedPrefixProjection { _private: () },
        )
    }
}
pub(super) struct PreparedProcessProjection {
    ordinal: u64,
    purpose: InstalledProcessPurpose,
    program: data::implementation::OsOperand,
    directory: data::implementation::OsOperand,
    arguments: Items<data::implementation::OsOperand, 0, { usize::MAX }>,
}
pub(super) enum ProcessProjection {
    Prepared(PreparedProcessProjection),
    Projected(data::ProcessMeasurement),
    Moving,
    Attached,
}

impl InstalledClientRun<'_> {
    fn consumer_output_requirements(
        &mut self,
        limits: Limits,
    ) -> Result<OutputRequirements, InstalledAdapterError> {
        let report_limit = self
            .decode
            .saved_limit()
            .min(crate::workbench::MAX_REPORT_BYTES);
        if report_limit == 0 {
            return Err(self.overflow_failure());
        }
        let diagnostic = crate::json::strict::requested_serializer_io_storage_bound()
            .ok_or_else(|| self.overflow_failure())?;
        let retained = report_limit
            .checked_add(diagnostic)
            .ok_or_else(|| self.overflow_failure())?;
        let visits = limits
            .max_frame
            .checked_add(limits.stderr_capture)
            .and_then(|n| report_limit.checked_mul(8).and_then(|r| n.checked_add(r)))
            .and_then(|n| n.checked_add(20))
            .and_then(|n| n.checked_add(diagnostic))
            .ok_or_else(|| self.overflow_failure())?;
        Ok(OutputRequirements {
            report_limit,
            diagnostic,
            retained,
            visits,
            stdout: limits.max_frame,
            stderr: limits.stderr_capture,
        })
    }
    pub(super) fn prepare_consumer_output(
        &mut self,
        limits: Limits,
    ) -> Result<ReservedConsumerOutput, InstalledAdapterError> {
        self.work_ready()?;
        if !self.revoker.active() {
            return Err(self.observation_failure(InstalledObservationError::Abandoned));
        }
        let requirements = self.consumer_output_requirements(limits)?;
        let charge = self.decode.slots(3);
        self.decoded(charge)?;
        let charge = self.decode.bytes(requirements.visits);
        self.decoded(charge)?;
        self.reserve_storage(requirements.retained)?;
        let extra = requirements
            .visits
            .checked_sub(requirements.retained)
            .ok_or_else(|| self.overflow_failure())?;
        self.receiving
            .reserve_span(InstalledObservationResource::ByteVisits, extra)
            .map_err(|fault| self.observation_failure(fault))?;
        let mut destination = Vec::new();
        destination
            .try_reserve_exact(requirements.report_limit)
            .map_err(|_| self.allocate_failure())?;
        self.storage_excess(requirements.report_limit, destination.capacity())?;
        Ok(ReservedConsumerOutput {
            destination,
            requirements,
            prefixes: Some(PrefixPair),
        })
    }
    pub(super) fn prepare_consumer_process_projection(
        &mut self,
        description: &ProcessDescription,
    ) -> Result<ProcessProjection, InstalledAdapterError> {
        let program = self.observation_operand(&description.program)?;
        let directory = self.observation_operand(&description.directory)?;
        let mut arguments = self.vector(description.arguments.len())?;
        for arg in &description.arguments {
            arguments.push(self.observation_operand(arg)?)
        }
        Ok(ProcessProjection::Prepared(PreparedProcessProjection {
            ordinal: description.ordinal,
            purpose: description.purpose,
            program,
            directory,
            arguments: Items(arguments),
        }))
    }
    pub(super) fn encoding_fault(&mut self, fault: ConsumerEncodingFault) {
        use crate::workbench::model_originals::workflow::decode::{DecodeError, OperandResource};
        let cause = match fault {
            ConsumerEncodingFault::Limit => DecodeError::SavedBytes,
            ConsumerEncodingFault::WorkLimit => DecodeError::Work(OperandResource::ByteVisits),
            _ => DecodeError::Shape("selected consumer report encoding"),
        };
        self.attempt.fail(RunFault::Decode(cause));
    }
}

fn project(record: &mut record::ConsumerOperationRecord) -> Result<(), ConsumerEncodingFault> {
    let ProcessProjection::Prepared(metadata) = &record.reservation.process else {
        return if matches!(
            record.reservation.process,
            ProcessProjection::Projected(_) | ProcessProjection::Attached
        ) {
            Ok(())
        } else {
            Err(ConsumerEncodingFault::PriorFault)
        };
    };
    let output = record
        .reservation
        .output
        .as_mut()
        .ok_or(ConsumerEncodingFault::PriorFault)?;
    if metadata.ordinal != record.finished.description.ordinal
        || metadata.purpose != record.finished.description.purpose
    {
        return Err(ConsumerEncodingFault::Unsupported);
    }
    if record.finished.outcome.stdout().len() > output.requirements.stdout
        || record.finished.outcome.stderr().len() > output.requirements.stderr
    {
        return Err(ConsumerEncodingFault::Limit);
    }
    let pair = output
        .prefixes
        .take()
        .ok_or(ConsumerEncodingFault::PriorFault)?;
    let (stdout_permission, stderr_permission) = pair.split();
    let ProcessProjection::Prepared(metadata) =
        std::mem::replace(&mut record.reservation.process, ProcessProjection::Moving)
    else {
        unreachable!("checked private projection state")
    };
    let (stdout, stderr) = record.finished.outcome.take_record_prefixes();
    let outcome = &record.finished.outcome;
    let status = outcome.status();
    let exit = match status.code() {
        Some(code) if code >= 0 => data::ProcessExit::Code {
            value: Natural(code as u64),
        },
        _ => {
            #[cfg(unix)]
            {
                use std::os::unix::process::ExitStatusExt;
                match status.signal() {
                    Some(signal) if signal > 0 => data::ProcessExit::Signal {
                        value: Natural(signal as u64),
                    },
                    _ => data::ProcessExit::Other {},
                }
            }
            #[cfg(not(unix))]
            {
                data::ProcessExit::Other {}
            }
        }
    };
    let InstalledProcessPurpose::Canonical {
        action_index,
        command,
    } = metadata.purpose
    else {
        unreachable!("private Canonical Publish reservation")
    };
    record.reservation.process = ProcessProjection::Projected(data::ProcessMeasurement {
        directory: metadata.directory,
        process_ordinal: Natural(metadata.ordinal),
        program: metadata.program,
        arguments: metadata.arguments,
        action_index: Natural(action_index as u64),
        command: match command {
            InstalledCommand::Connect => data::ProcessCommand::Connect,
            InstalledCommand::List => data::ProcessCommand::List,
            InstalledCommand::Publish => data::ProcessCommand::Publish,
        },
        completion: data::DirectProcessCompletion::Finished { exit },
        stdout: data::ObservedBytes::adopt_prefix(stdout, stdout_permission),
        stderr: data::ObservedBytes::adopt_prefix(stderr, stderr_permission),
        stderr_truncated: data::MeasuredBool::live(outcome.stderr_truncated()),
        descendants: match outcome.descendants() {
            crate::transport::process::DescendantEvidence::Unobserved => {
                data::DescendantCoverage::Unobserved
            }
            crate::transport::process::DescendantEvidence::TerminationRequestedUnverified => {
                data::DescendantCoverage::TerminationRequestedUnverified
            }
        },
    });
    Ok(())
}
fn projected(
    record: &record::ConsumerOperationRecord,
) -> Option<(
    &data::ProcessMeasurement,
    &crate::transport::process::ProcessOutcome,
)> {
    match &record.reservation.process {
        ProcessProjection::Projected(value) => Some((value, &record.finished.outcome)),
        _ => None,
    }
}
impl record::ConsumerOperationRecord {
    pub(in crate::workbench::model_originals::workflow::pipeline) fn take_output(
        &mut self,
    ) -> Option<ReservedConsumerOutput> {
        self.reservation.output.take()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline) fn take_measurement_slot(
        &mut self,
    ) -> Vec<data::InstalledClientMeasurements> {
        std::mem::take(&mut self.reservation.measurement_slot)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline) fn take_failure_slot(
        &mut self,
    ) -> Vec<data::LiveMeasurements> {
        std::mem::take(&mut self.reservation.failure_slot)
    }
    pub(super) fn take_projected_process(&mut self) -> Option<data::ProcessMeasurement> {
        match std::mem::replace(&mut self.reservation.process, ProcessProjection::Attached) {
            ProcessProjection::Projected(value) => Some(value),
            same => {
                self.reservation.process = same;
                None
            }
        }
    }
    /// Moves only the two precharged prefixes. The SAME joined outcome and
    /// its retained process-tree evidence remain owned by this record.
    pub(in crate::workbench::model_originals::workflow::pipeline) fn project_process(
        &mut self,
    ) -> Result<(), ConsumerEncodingFault> {
        project(self)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline) fn projected_process(
        &self,
    ) -> Option<(
        &data::ProcessMeasurement,
        &crate::transport::process::ProcessOutcome,
    )> {
        projected(self)
    }
}

/// The writer never reserves or grows. Count and write see the same value.
struct BoundedWriter<'a> {
    destination: Option<&'a mut Vec<u8>>,
    used: usize,
    limit: usize,
    refused: bool,
}
impl std::io::Write for BoundedWriter<'_> {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        let Some(next) = self
            .used
            .checked_add(bytes.len())
            .filter(|n| *n <= self.limit)
        else {
            self.refused = true;
            return Err(std::io::ErrorKind::FileTooLarge.into());
        };
        if let Some(destination) = &mut self.destination {
            if next > destination.capacity() {
                self.refused = true;
                return Err(std::io::ErrorKind::FileTooLarge.into());
            }
            destination.extend_from_slice(bytes)
        }
        self.used = next;
        Ok(bytes.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}
#[derive(Debug)]
pub(in crate::workbench::model_originals::workflow) struct EncodedConsumerOutput {
    text: String,
}
impl EncodedConsumerOutput {
    pub(in crate::workbench::model_originals::workflow::pipeline) fn into_text(self) -> String {
        self.text
    }
}
pub(in crate::workbench::model_originals::workflow::pipeline) struct BufferRejected {
    output: ReservedConsumerOutput,
    fault: ConsumerEncodingFault,
    progress: preflight::Progress,
    passes: usize,
}
impl std::fmt::Debug for BufferRejected {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BufferRejected")
            .field("fault", &self.fault)
            .field("progress", &self.progress)
            .field("passes", &self.passes)
            .finish_non_exhaustive()
    }
}
impl BufferRejected {
    pub(in crate::workbench::model_originals::workflow::pipeline) fn fault(
        &self,
    ) -> ConsumerEncodingFault {
        self.fault
    }
}
fn encode<T: ?Sized + Serialize>(
    mut output: ReservedConsumerOutput,
    value: &T,
    bound: usize,
    steps: usize,
) -> Result<EncodedConsumerOutput, BufferRejected> {
    let mut progress = preflight::Progress::default();
    let mut passes = 0;
    let result = (|| {
        if bound > output.requirements.report_limit || steps > output.requirements.report_limit {
            return Err(ConsumerEncodingFault::Unsupported);
        }
        let limit = bound.checked_sub(1).ok_or(ConsumerEncodingFault::Limit)?;
        progress = preflight::check_string_input(value, limit, steps).map_err(|refused| {
            progress = refused.progress;
            match refused.fault {
                preflight::InputFault::Limit => ConsumerEncodingFault::Limit,
                preflight::InputFault::WorkLimit => ConsumerEncodingFault::WorkLimit,
                preflight::InputFault::Unsupported => ConsumerEncodingFault::Unsupported,
            }
        })?;
        let mut counter = BoundedWriter {
            destination: None,
            used: 0,
            limit,
            refused: false,
        };
        passes += 1;
        serde_json::to_writer(&mut counter, value).map_err(|_| {
            if counter.refused {
                ConsumerEncodingFault::Limit
            } else {
                ConsumerEncodingFault::Serialization
            }
        })?;
        let mut writer = BoundedWriter {
            destination: Some(&mut output.destination),
            used: 0,
            limit,
            refused: false,
        };
        passes += 1;
        serde_json::to_writer(&mut writer, value).map_err(|_| {
            if writer.refused {
                ConsumerEncodingFault::Limit
            } else {
                ConsumerEncodingFault::Serialization
            }
        })?;
        if writer.used != counter.used {
            return Err(ConsumerEncodingFault::Serialization);
        }
        // The one newline is within preissued R/capacity, not a grow path.
        output.destination.push(b'\n');
        Ok(())
    })();
    if let Err(fault) = result {
        return Err(BufferRejected {
            output,
            fault,
            progress,
            passes,
        });
    }
    match String::from_utf8(output.destination) {
        Ok(text) => Ok(EncodedConsumerOutput { text }),
        Err(error) => {
            output.destination = error.into_bytes();
            Err(BufferRejected {
                output,
                fault: ConsumerEncodingFault::Serialization,
                progress,
                passes,
            })
        }
    }
}
impl ReservedConsumerOutput {
    /// The sole production encoder accepts the closed selected report only.
    /// Caller owns the same report/record on error; integration follows later.
    pub(in crate::workbench::model_originals::workflow::pipeline) fn encode_report(
        self,
        report: &crate::workbench::model_originals::workflow::pipeline::wire::RuntimeReport<'_>,
    ) -> Result<EncodedConsumerOutput, BufferRejected> {
        let bound = self.requirements.report_limit;
        encode(self, report, bound, bound)
    }
}

#[cfg(test)]
mod test_support;
