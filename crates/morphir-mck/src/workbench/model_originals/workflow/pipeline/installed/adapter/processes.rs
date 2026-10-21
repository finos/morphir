//! Budget the actual spec before spawn. The wrapper moves that SAME spec into
//! the existing process owner and retains its private ordinal through finish.
use super::*;
use crate::transport::{
    Limits,
    process::{
        CommandSpec, OneShotProcess, ProcessError, ProcessFinish, ProcessOutcome, ProcessProgress,
        ReapError, ReapProgress, TerminationDisposition, TerminationRefusal,
    },
};
use std::{
    ffi::{OsStr, OsString},
    path::{Path, PathBuf},
};
pub(super) mod consumer;
pub(in crate::workbench::model_originals::workflow) use consumer::record::ConsumerOperationRecord;
pub(in crate::workbench::model_originals::workflow) use consumer::wire::{
    ConsumerCodecError, ConsumerFailureKind,
};
pub use consumer::{
    ConsumerAckProgress, ConsumerDrainProgress, ConsumerPendingAck, ConsumerProcessCommand,
    ConsumerProducerRole, ConsumerReceiveProgress, ConsumerTransportState, InstalledConsumerPorts,
    PreparedInstalledConsumerProcess,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InstalledMetadataQuery {
    Revision,
    TrackedInventory,
    TrackedStatus,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InstalledProcessPurpose {
    Canonical {
        action_index: usize,
        command: InstalledCommand,
    },
    Metadata(InstalledMetadataQuery),
}
pub(in crate::workbench::model_originals::workflow) struct ProcessDescription {
    pub(in crate::workbench::model_originals::workflow) ordinal: u64,
    pub(in crate::workbench::model_originals::workflow) purpose: InstalledProcessPurpose,
    pub(in crate::workbench::model_originals::workflow) program: OsString,
    pub(in crate::workbench::model_originals::workflow) arguments: Vec<OsString>,
    pub(in crate::workbench::model_originals::workflow) directory: OsString,
    pub(super) invocation: std::sync::Weak<dyn InvocationGateSource>,
}
struct PreparedInstalledProcess {
    description: ProcessDescription,
    spec: CommandSpec,
    limits: Limits,
}
pub struct RunningInstalledProcess {
    description: ProcessDescription,
    process: OneShotProcess,
}
pub struct FinishedInstalledProcess {
    pub(super) description: ProcessDescription,
    pub(super) outcome: ProcessOutcome,
}
pub enum InstalledProcessFinish {
    Pending(RunningInstalledProcess),
    Finished(FinishedInstalledProcess),
}
impl PreparedInstalledProcess {
    fn spawn(self) -> Result<RunningInstalledProcess, ProcessError> {
        OneShotProcess::spawn(self.spec, self.limits).map(|process| RunningInstalledProcess {
            description: self.description,
            process,
        })
    }
}
impl RunningInstalledProcess {
    pub fn advance(&mut self) -> ProcessProgress<'_> {
        self.process.advance()
    }
    pub fn request_termination(&mut self) -> Result<TerminationDisposition, TerminationRefusal> {
        self.process.request_termination()
    }
    pub fn reap_retained(&mut self) -> Result<ReapProgress, ReapError> {
        self.process.reap_retained()
    }
    pub fn try_finish(self) -> InstalledProcessFinish {
        match self.process.into_finished() {
            ProcessFinish::Finished(outcome) => {
                InstalledProcessFinish::Finished(FinishedInstalledProcess {
                    description: self.description,
                    outcome,
                })
            }
            ProcessFinish::Pending(process) => InstalledProcessFinish::Pending(Self {
                description: self.description,
                process,
            }),
        }
    }
}
impl FinishedInstalledProcess {
    pub fn outcome(&self) -> &ProcessOutcome {
        &self.outcome
    }
    pub fn purpose(&self) -> InstalledProcessPurpose {
        self.description.purpose
    }
}
impl InstalledClientRun<'_> {
    pub(super) fn observation_failure(
        &mut self,
        error: InstalledObservationError,
    ) -> InstalledAdapterError {
        self.receiving.fail(error);
        self.attempt.fail(RunFault::InstalledObservation(error));
        InstalledAdapterError::ObservationIncomplete
    }
    pub(super) fn allocate_failure(&mut self) -> InstalledAdapterError {
        self.observation_failure(InstalledObservationError::Allocation)
    }
    pub(super) fn overflow_failure(&mut self) -> InstalledAdapterError {
        self.observation_failure(InstalledObservationError::SizeOverflow)
    }
    pub(super) fn reserve_storage(&mut self, length: usize) -> Result<(), InstalledAdapterError> {
        self.charge_storage(length, length)
    }
    pub(super) fn storage_excess(
        &mut self,
        requested: usize,
        capacity: usize,
    ) -> Result<(), InstalledAdapterError> {
        let excess = capacity
            .checked_sub(requested)
            .ok_or_else(|| self.observation_failure(InstalledObservationError::LayoutMismatch))?;
        self.charge_storage(0, excess)
    }
    pub(super) fn vector<T>(&mut self, count: usize) -> Result<Vec<T>, InstalledAdapterError> {
        self.work_ready()?;
        self.decode.slots(count).map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })?;
        let bytes = count
            .checked_mul(std::mem::size_of::<T>())
            .ok_or_else(|| self.overflow_failure())?;
        self.reserve_storage(bytes)?;
        let mut values = Vec::new();
        values
            .try_reserve_exact(count)
            .map_err(|_| self.allocate_failure())?;
        let capacity = values
            .capacity()
            .checked_mul(std::mem::size_of::<T>())
            .ok_or_else(|| self.overflow_failure())?;
        self.storage_excess(bytes, capacity)?;
        Ok(values)
    }
    pub(super) fn charge_storage(
        &mut self,
        bytes: usize,
        capacity: usize,
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        for (resource, count) in [
            (InstalledObservationResource::RetainedBytes, capacity),
            (InstalledObservationResource::ByteVisits, bytes),
        ] {
            if let Err(error) = self.receiving.reserve_span(resource, count) {
                self.attempt.fail(RunFault::InstalledObservation(error));
                return Err(InstalledAdapterError::ObservationIncomplete);
            }
        }
        Ok(())
    }
    pub fn copy_command_operand(
        &mut self,
        value: &OsStr,
    ) -> Result<OsString, InstalledAdapterError> {
        self.work_ready()?;
        self.reserve_storage(value.len())?;
        let mut copy = OsString::new();
        copy.try_reserve_exact(value.len())
            .map_err(|_| self.allocate_failure())?;
        self.storage_excess(value.len(), copy.capacity())?;
        copy.push(value);
        Ok(copy)
    }
    pub fn command_path(
        &mut self,
        root: &Path,
        member: &str,
    ) -> Result<PathBuf, InstalledAdapterError> {
        let length = root
            .as_os_str()
            .len()
            .checked_add(member.len())
            .and_then(|n| n.checked_add(1))
            .ok_or_else(|| self.overflow_failure())?;
        self.reserve_storage(length)?;
        let mut path = PathBuf::new();
        path.try_reserve_exact(length)
            .map_err(|_| self.allocate_failure())?;
        self.storage_excess(length, path.capacity())?;
        path.push(root);
        path.push(member);
        Ok(path)
    }
    pub fn spawn_process<'arg>(
        &mut self,
        purpose: InstalledProcessPurpose,
        program: &Path,
        arguments: impl ExactSizeIterator<Item = &'arg OsStr>,
        directory: &Path,
        environment: &[(OsString, OsString)],
        limits: Limits,
    ) -> Result<RunningInstalledProcess, InstalledAdapterError> {
        let prepared =
            self.prepare_process(purpose, program, arguments, directory, environment, limits)?;
        self.work_ready()?;
        if !self.revoker.active() {
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        prepared.spawn().map_err(|_| {
            self.attempt.fail(RunFault::Installed(
                InstalledAdapterError::ObservationIncomplete,
            ));
            InstalledAdapterError::ObservationIncomplete
        })
    }
    fn prepare_process<'arg>(
        &mut self,
        purpose: InstalledProcessPurpose,
        program: &Path,
        arguments: impl ExactSizeIterator<Item = &'arg OsStr>,
        directory: &Path,
        environment: &[(OsString, OsString)],
        limits: Limits,
    ) -> Result<PreparedInstalledProcess, InstalledAdapterError> {
        self.work_ready()?;
        if let InstalledProcessPurpose::Canonical {
            action_index,
            command,
        } = purpose
            && !matches!(self.actions().nth(action_index),Some(InstalledClientAction::Run{command:actual,..}) if actual==command)
        {
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        self.reserve_process_prefixes(&limits)
            .map_err(|_| InstalledAdapterError::ObservationIncomplete)?
            .commit();
        self.receiving
            .prepare_record(ObservationRecordRole::Process)
            .map_err(|_| InstalledAdapterError::ObservationIncomplete)?
            .issue();
        let mut args = self.vector(arguments.len())?;
        for argument in arguments {
            args.push(self.copy_command_operand(argument)?);
        }
        let mut env = self.vector(environment.len())?;
        for (key, value) in environment {
            env.push((
                self.copy_command_operand(key)?,
                self.copy_command_operand(value)?,
            ));
        }
        let owned_program = PathBuf::from(self.copy_command_operand(program.as_os_str())?);
        let owned_directory = PathBuf::from(self.copy_command_operand(directory.as_os_str())?);
        let spec = CommandSpec::new(owned_program, args, owned_directory, env)
            .map_err(|_| self.observation_failure(InstalledObservationError::LayoutMismatch))?;
        // This second, explicitly funded retention is copied from the actual
        // spec before that exact spec moves to the existing OS process owner.
        let observed_program = self.copy_command_operand(spec.program().as_os_str())?;
        let observed_directory = self.copy_command_operand(spec.directory().as_os_str())?;
        let mut observed_arguments = self.vector(spec.arguments().len())?;
        for argument in spec.arguments() {
            observed_arguments.push(self.copy_command_operand(argument)?);
        }
        let ordinal = self.next_process;
        self.next_process = ordinal
            .checked_add(1)
            .ok_or_else(|| self.overflow_failure())?;
        let invocation = self
            .revoker
            .projection()
            .filter(|source| self.revoker.matches(source))
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        Ok(PreparedInstalledProcess {
            description: ProcessDescription {
                ordinal,
                purpose,
                program: observed_program,
                arguments: observed_arguments,
                directory: observed_directory,
                invocation,
            },
            spec,
            limits,
        })
    }
}

#[cfg(test)]
#[path = "processes_finish_test.rs"]
mod finish_state_tests;
