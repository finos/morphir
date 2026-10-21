//! Owned endpoints and a private operation transport; no business report claim.
use super::super::invocation::ConsumerWindow;
use super::*;
use crate::workbench::configuration::ConsumerObservationSelection;
use std::time::Instant;
#[cfg(target_os = "macos")]
mod binding;
#[cfg(target_os = "macos")]
mod codec;
#[cfg(target_os = "macos")]
mod collector;
pub(in crate::workbench::model_originals::workflow) mod deadline;
#[cfg(target_os = "macos")]
mod export;
#[cfg(target_os = "macos")]
mod launch;
mod sdk;
pub(in crate::workbench::model_originals::workflow) mod wire;
pub use sdk::ConsumerTransportState;
pub use wire::{ConsumerAckProgress, ConsumerPendingAck, ConsumerReceiveProgress};

pub struct ConsumerProcessCommand<'a> {
    pub purpose: InstalledProcessPurpose,
    pub program: &'a Path,
    pub arguments: &'a [OsString],
    pub directory: &'a Path,
    pub environment: &'a [(OsString, OsString)],
    pub limits: Limits,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum ConsumerProducerRole {
    Outer,
    TransferHelper,
}

pub struct PreparedInstalledConsumerProcess {
    _private: (),
    #[cfg(target_os = "macos")]
    process: PreparedInstalledProcess,
    #[cfg(target_os = "macos")]
    control: std::sync::Arc<ConsumerPortControl>,
    #[cfg(target_os = "macos")]
    end: Instant,
}
pub struct InstalledConsumerPorts {
    _private: (),
    #[cfg(target_os = "macos")]
    control: std::sync::Arc<ConsumerPortControl>,
    #[cfg(target_os = "macos")]
    channels: [collector::Channel; 2],
    #[cfg(target_os = "macos")]
    helper_association: collector::HelperAssociation,
}
impl InstalledConsumerPorts {
    /// Revoke these SAME owned peers after a delivery/process fault. Logical
    /// revocation never proves producer cleanup or any task/process join.
    pub fn revoke(&mut self) {
        #[cfg(target_os = "macos")]
        self.control.revoke();
    }
}

impl InstalledClientRun<'_> {
    pub fn bind_consumer_window(
        &mut self,
        original_end: Instant,
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        if !cfg!(target_os = "macos")
            || !matches!(
                self.revoker.consumer_selection,
                ConsumerObservationSelection::OperationPort(_)
            )
            || !self.revoker.active()
            || original_end <= Instant::now()
            || !matches!(self.revoker.consumer_window, ConsumerWindow::Unbound)
        {
            return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
        }
        self.revoker.consumer_window = ConsumerWindow::Bound(original_end);
        Ok(())
    }
    fn consumer_end(&mut self, caller_end: Instant) -> Result<Instant, InstalledAdapterError> {
        self.work_ready()?;
        let ConsumerWindow::Bound(end) = self.revoker.consumer_window else {
            return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
        };
        let end = end.min(caller_end);
        if end <= Instant::now() || !self.revoker.active() {
            return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
        }
        Ok(end)
    }
    #[cfg(not(target_os = "macos"))]
    pub fn prepare_consumer_process(
        &mut self,
        _command: ConsumerProcessCommand<'_>,
        _end: Instant,
    ) -> Result<(PreparedInstalledConsumerProcess, InstalledConsumerPorts), InstalledAdapterError>
    {
        Err(self.observation_failure(InstalledObservationError::LayoutMismatch))
    }
    #[cfg(not(target_os = "macos"))]
    pub fn spawn_prepared_consumer_process(
        &mut self,
        _prepared: PreparedInstalledConsumerProcess,
    ) -> Result<RunningInstalledProcess, InstalledAdapterError> {
        Err(self.observation_failure(InstalledObservationError::LayoutMismatch))
    }
}

#[cfg(all(test, target_os = "macos"))]
use std::os::fd::{AsFd, BorrowedFd};
#[cfg(target_os = "macos")]
use std::{
    net::Shutdown,
    os::unix::net::UnixStream,
    sync::{Arc, Mutex, OnceLock},
};
#[cfg(target_os = "macos")]
enum PortState {
    Preparing,
    Ready,
    SpawnClaimed,
    Revoked,
}
#[cfg(target_os = "macos")]
pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) struct ConsumerPortControl
{
    state: Mutex<PortState>,
    parents: OnceLock<[UnixStream; 2]>,
    // Actual capacities are funded before allocation and before socketpair.
    binding: binding::ConsumerBinding,
    end: Instant,
    max_frame: usize,
    invocation: std::sync::Weak<dyn InvocationGateSource>,
    deadline: OnceLock<Result<deadline::DarwinContinuousDeadline, wire::ConsumerCodecError>>,
}
#[cfg(target_os = "macos")]
impl ConsumerPortControl {
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn revoked(
        &self,
    ) -> bool {
        match self.state.lock() {
            Ok(state) => matches!(*state, PortState::Revoked),
            Err(_) => true,
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn revoke(
        &self,
    ) {
        *self
            .state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner()) = PortState::Revoked;
        // Release control lock before OS shutdown. The stable owned FDs remain
        // alive, so borrowed diagnostics cannot race FD close/reuse.
        if let Some(parents) = self.parents.get() {
            for peer in parents {
                let _ = peer.shutdown(Shutdown::Both);
            }
        }
    }
    fn claim(&self) -> bool {
        let Ok(mut state) = self.state.lock() else {
            return false;
        };
        if !matches!(*state, PortState::Ready) {
            return false;
        }
        *state = PortState::SpawnClaimed;
        true
    }
    fn claimed(&self) -> bool {
        self.state
            .lock()
            .is_ok_and(|state| matches!(*state, PortState::SpawnClaimed))
    }
    fn opened(&self) -> bool {
        let Ok(mut state) = self.state.lock() else {
            return false;
        };
        if !matches!(*state, PortState::Preparing) {
            return false;
        }
        *state = PortState::Ready;
        true
    }
}
#[cfg(target_os = "macos")]
impl Drop for InstalledConsumerPorts {
    fn drop(&mut self) {
        self.control.revoke();
    }
}

#[cfg(target_os = "macos")]
impl InstalledClientRun<'_> {
    pub fn prepare_consumer_process(
        &mut self,
        command: ConsumerProcessCommand<'_>,
        caller_end: Instant,
    ) -> Result<(PreparedInstalledConsumerProcess, InstalledConsumerPorts), InstalledAdapterError>
    {
        self.prepare_consumer_bound(
            command,
            caller_end,
            binding::ConsumerBinding::Raw,
            export::PreparedClock::Unlaunched,
        )
    }
    fn prepare_consumer_bound(
        &mut self,
        command: ConsumerProcessCommand<'_>,
        caller_end: Instant,
        binding: binding::ConsumerBinding,
        clock: export::PreparedClock,
    ) -> Result<(PreparedInstalledConsumerProcess, InstalledConsumerPorts), InstalledAdapterError>
    {
        let end = self.consumer_end(caller_end)?;
        let ConsumerProcessCommand {
            purpose,
            program,
            arguments,
            directory,
            environment,
            limits,
        } = command;
        if !matches!(
            self.revoker.consumer_selection,
            ConsumerObservationSelection::OperationPort(_)
        ) || !matches!(purpose, InstalledProcessPurpose::Canonical {action_index, command:InstalledCommand::Publish} if matches!(self.actions().nth(action_index),Some(InstalledClientAction::Run {command:InstalledCommand::Publish,..})))
            || !program.is_absolute()
            || !directory.is_absolute()
        {
            return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
        }
        const KEYS: [&str; 2] = [
            "MORPHIR_PRIVATE_CONSUMER_OUTER_FD",
            "MORPHIR_PRIVATE_CONSUMER_HELPER_FD",
        ];
        for (key, _) in environment {
            let visits = launch::RESERVED_KEYS
                .iter()
                .try_fold(key.len(), |count, key| count.checked_add(key.len()))
                .ok_or_else(|| self.overflow_failure())?;
            self.visit_observation_bytes(visits)?;
            if launch::RESERVED_KEYS.iter().any(|reserved| key == reserved) {
                return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
            }
        }
        // All retained command/observation storage and fixed bookkeeping are
        // funded before the first socketpair/descriptor operation. Same owners,
        // no implicit transport-prefix/helper-process permission.
        let count = environment
            .len()
            .checked_add(2)
            .and_then(|count| count.checked_add(clock.selector_count()))
            .ok_or_else(|| self.overflow_failure())?;
        let mut env = self.vector(count)?;
        for (key, value) in environment {
            env.push((
                self.copy_command_operand(key)?,
                self.copy_command_operand(value)?,
            ));
        }
        self.consumer_clock_environment(&mut env, &clock)?;
        for key in KEYS {
            env.push((
                self.copy_command_operand(OsStr::new(key))?,
                self.copy_command_operand(OsStr::new("0000000000"))?,
            ));
        }
        let process = self.prepare_process(
            purpose,
            program,
            arguments.iter().map(|arg| arg.as_os_str()),
            directory,
            &env,
            limits,
        )?;
        for _ in 0..2 {
            match self
                .receiving
                .prepare_record(ObservationRecordRole::ConsumerProducer)
            {
                Ok(ticket) => {
                    ticket.issue();
                }
                Err(error) => {
                    let error = *error;
                    self.attempt.fail(RunFault::InstalledObservation(error));
                    return Err(InstalledAdapterError::ObservationIncomplete);
                }
            }
        }
        let buffers = [
            self.observation_read_buffer(limits.max_frame)?,
            self.observation_read_buffer(limits.max_frame)?,
        ];
        // Arc's two atomic counters are fixed infrastructure, not RSS or a
        // promise about allocator bookkeeping. Same cumulative storage ledger.
        let atomic = std::alloc::Layout::new::<std::sync::atomic::AtomicUsize>();
        // Pinned alloc::sync::ArcInner is repr(C): strong, weak, then data.
        let (header, _) = atomic.extend(atomic).map_err(|_| self.overflow_failure())?;
        let (layout, _) = header
            .extend(std::alloc::Layout::new::<ConsumerPortControl>())
            .map_err(|_| self.overflow_failure())?;
        self.reserve_storage(layout.pad_to_align().size())?;
        let callback_storage =
            crate::transport::process::OwnedConsumerChildEnds::callback_storage()
                .ok_or_else(|| self.overflow_failure())?;
        self.reserve_storage(callback_storage)?;
        self.reserve_storage(std::mem::size_of::<InstalledConsumerPorts>())?;
        self.visit_observation_bytes(2 * (10 + KEYS[0].len() + KEYS[1].len()))?;
        let control = Arc::new(ConsumerPortControl {
            state: Mutex::new(PortState::Preparing),
            parents: OnceLock::new(),
            binding,
            end,
            max_frame: limits.max_frame,
            invocation: process.description.invocation.clone(),
            deadline: clock.into_cache(),
        });
        self.revoker
            .register_consumer(Arc::downgrade(&control))
            .map_err(|_| self.observation_failure(InstalledObservationError::LayoutMismatch))?;
        self.consumer_end(end)?;
        let created = (|| {
            let (outer_parent, outer_child) = UnixStream::pair()?;
            let (helper_parent, helper_child) = UnixStream::pair()?;
            for socket in [&outer_parent, &outer_child, &helper_parent, &helper_child] {
                socket.set_nonblocking(true)?;
            }
            let ends =
                crate::transport::process::OwnedConsumerChildEnds::new(outer_child, helper_child)?;
            Ok::<_, std::io::Error>(([outer_parent, helper_parent], ends))
        })();
        let (parents, ends) = created
            .map_err(|_| self.observation_failure(InstalledObservationError::LayoutMismatch))?;
        let _ = control.parents.set(parents);
        if !control.opened() {
            control.revoke();
            return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
        }
        let PreparedInstalledProcess {
            description,
            spec,
            limits,
        } = process;
        let spec = spec
            .with_consumer_handles(ends)
            .map_err(|_| self.observation_failure(InstalledObservationError::LayoutMismatch))?;
        Ok((
            PreparedInstalledConsumerProcess {
                _private: (),
                process: PreparedInstalledProcess {
                    description,
                    spec,
                    limits,
                },
                control: control.clone(),
                end,
            },
            InstalledConsumerPorts {
                _private: (),
                helper_association: collector::HelperAssociation::new(&control.binding),
                control,
                channels: buffers.map(collector::Channel::new),
            },
        ))
    }
    pub fn spawn_prepared_consumer_process(
        &mut self,
        prepared: PreparedInstalledConsumerProcess,
    ) -> Result<RunningInstalledProcess, InstalledAdapterError> {
        self.spawn_consumer_claimed(prepared, || ())
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn test_spawn_after_consumer_claim(
        &mut self,
        prepared: PreparedInstalledConsumerProcess,
        hook: impl FnOnce(),
    ) -> Result<RunningInstalledProcess, InstalledAdapterError> {
        self.spawn_consumer_claimed(prepared, hook)
    }
    fn spawn_consumer_claimed(
        &mut self,
        prepared: PreparedInstalledConsumerProcess,
        after_claim: impl FnOnce(),
    ) -> Result<RunningInstalledProcess, InstalledAdapterError> {
        self.consumer_end(prepared.end)?;
        if !self
            .revoker
            .matches(&prepared.process.description.invocation)
            || !prepared.control.claim()
        {
            return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
        }
        // Callback-external revocation cannot destroy its borrowed revoker
        // during this SAME synchronous Run method. No locks span spawn.
        after_claim();
        if Instant::now() >= prepared.end {
            return Err(self.observation_failure(InstalledObservationError::LayoutMismatch));
        }
        let mut process = prepared
            .process
            .spawn()
            .map_err(|_| self.observation_failure(InstalledObservationError::LayoutMismatch))?;
        if !prepared.control.claimed() {
            self.observation_failure(InstalledObservationError::Abandoned);
            let _ = process.request_termination();
        }
        Ok(process)
    }
}
#[cfg(all(test, target_os = "macos"))]
impl InstalledConsumerPorts {
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn test_parent_handle(
        &self,
        role: ConsumerProducerRole,
    ) -> BorrowedFd<'_> {
        self.control.parents.get().expect("published endpoints")[match role {
            ConsumerProducerRole::Outer => 0,
            ConsumerProducerRole::TransferHelper => 1,
        }]
        .as_fd()
    }
}
#[cfg(all(test, target_os = "macos"))]
impl PreparedInstalledConsumerProcess {
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn test_child_handle(
        &self,
        role: ConsumerProducerRole,
    ) -> BorrowedFd<'_> {
        self.process
            .spec
            .test_consumer_child_handle(role == ConsumerProducerRole::TransferHelper)
    }
}
