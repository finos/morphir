//! Bounded nonblocking steps on the SAME owned endpoints. Cache precedes ACK.
use super::*;
use std::{fmt::Write, os::fd::AsFd};
use wire::{
    ConsumerAckProgress as Ack, ConsumerCodecError as Error, ConsumerPendingAck as Ticket,
    ConsumerReceiveProgress as Progress,
};
pub(super) struct Channel {
    buffer: Vec<u8>,
    header: [u8; 4],
    phase: Phase,
    next: u64,
}
#[derive(Clone, Copy)]
enum Phase {
    Header(usize),
    Body { length: usize, filled: usize },
    Association { index: usize, sequence: u64 },
    Ack { index: usize, sequence: u64 },
    EmptyHelperEof,
    Unused,
    Closed,
    Drained,
    Poisoned,
}
impl Channel {
    pub(super) fn new(buffer: Vec<u8>) -> Self {
        Self {
            buffer,
            header: [0; 4],
            phase: Phase::Header(0),
            next: 0,
        }
    }
}
impl InstalledConsumerPorts {
    pub fn transport_state(&self, role: ConsumerProducerRole) -> ConsumerTransportState {
        match self.channels[role.index()].phase {
            Phase::Closed | Phase::Drained => ConsumerTransportState::Closed,
            Phase::Unused => ConsumerTransportState::Unused,
            _ => ConsumerTransportState::Collecting,
        }
    }
    pub(super) fn frames_drained(&self) -> bool {
        self.channels
            .iter()
            .all(|channel| matches!(channel.phase, Phase::Drained | Phase::Unused))
    }
}
pub(super) enum HelperAssociation {
    Unbound,
    InProcess,
    AwaitingLaunch,
    Associated,
}
impl HelperAssociation {
    fn accepts_outer_completion(&self, completion: &wire::HelperCompletion) -> bool {
        matches!(
            (self, completion),
            (Self::InProcess, wire::HelperCompletion::InProcess { .. })
                | (
                    Self::AwaitingLaunch,
                    wire::HelperCompletion::NotAttempted { .. }
                        | wire::HelperCompletion::LaunchFailed { .. }
                )
                | (Self::Associated, wire::HelperCompletion::Started { .. })
        )
    }
    pub(super) fn new(binding: &binding::ConsumerBinding) -> Self {
        match binding {
            binding::ConsumerBinding::Raw => Self::Unbound,
            binding::ConsumerBinding::Observed(binding::ObservedLaunch::NodePackage { .. }) => {
                Self::InProcess
            }
            binding::ConsumerBinding::Observed(binding::ObservedLaunch::NativeExecutable {
                ..
            }) => Self::AwaitingLaunch,
        }
    }
}
struct AckWriter {
    bytes: [u8; 128],
    length: usize,
}
impl std::fmt::Write for AckWriter {
    fn write_str(&mut self, value: &str) -> std::fmt::Result {
        let end = self
            .length
            .checked_add(value.len())
            .filter(|n| *n <= self.bytes.len())
            .ok_or(std::fmt::Error)?;
        self.bytes[self.length..end].copy_from_slice(value.as_bytes());
        self.length = end;
        Ok(())
    }
}
impl InstalledClientRun<'_> {
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn drain_consumer_frames(
        &mut self,
        ports: &mut InstalledConsumerPorts,
    ) -> Result<wire::ConsumerDrainProgress, Error> {
        self.check_consumer_ports(ports)?;
        for index in 0..ports.channels.len() {
            if !matches!(ports.channels[index].phase, Phase::Closed) {
                continue;
            }
            // SAME owner/end and cumulative visit permission precede every
            // physical read. Logical Close/ACK remains distinct from EOF.
            self.check_consumer_ports(ports)?;
            let parent = ports.control.parents.get().expect("published endpoints")[index].as_fd();
            match self.consumer_read(parent, &mut [0u8; 1]) {
                Ok(Some(0)) => ports.channels[index].phase = Phase::Drained,
                Ok(None) => {}
                Ok(Some(_)) => return Err(self.poison_consumer(ports, Error::Framing)),
                Err(error) => return Err(self.poison_consumer(ports, error)),
            }
        }
        Ok(if ports.frames_drained() {
            wire::ConsumerDrainProgress::Complete
        } else {
            wire::ConsumerDrainProgress::Pending
        })
    }
    fn poison_consumer(&mut self, ports: &mut InstalledConsumerPorts, error: Error) -> Error {
        for channel in &mut ports.channels {
            channel.phase = Phase::Poisoned;
        }
        ports.control.revoke();
        self.consumer_fault(error)
    }
    fn consumer_read(
        &mut self,
        fd: std::os::fd::BorrowedFd<'_>,
        bytes: &mut [u8],
    ) -> Result<Option<usize>, Error> {
        self.visit_observation_bytes(bytes.len())
            .map_err(|_| Error::PriorFault)?;
        match rustix::io::read(fd, bytes) {
            Ok(n) => Ok(Some(n)),
            Err(rustix::io::Errno::AGAIN | rustix::io::Errno::INTR) => Ok(None),
            Err(error) => Err(Error::Io(
                std::io::Error::from_raw_os_error(error.raw_os_error()).kind(),
            )),
        }
    }
    fn issue_consumer_ack(
        &mut self,
        ports: &mut InstalledConsumerPorts,
        role: ConsumerProducerRole,
        index: usize,
        sequence: u64,
    ) -> Result<Progress, Error> {
        self.reserve_storage(std::mem::size_of::<Ticket>())
            .map_err(|_| self.consumer_receiving_error())?;
        self.visit_observation_bytes(256)
            .map_err(|_| Error::PriorFault)?;
        let mut encoded = AckWriter {
            bytes: [0; 128],
            length: 4,
        };
        write!(
            &mut encoded,
            "{{\"kind\":\"retained\",\"version\":\"{}\",\"sequence\":{}}}",
            wire::VERSION,
            sequence
        )
        .map_err(|_| self.consumer_fault(Error::Shape))?;
        encoded.bytes[..4].copy_from_slice(
            &u32::try_from(encoded.length - 4)
                .map_err(|_| Error::Shape)?
                .to_be_bytes(),
        );
        ports.channels[role.index()].phase = Phase::Ack { index, sequence };
        Ok(Progress::Retained(Ticket {
            _private: (),
            control: Arc::downgrade(&ports.control),
            role,
            sequence,
            cache_index: index,
            bytes: encoded.bytes,
            length: encoded.length,
            cursor: 0,
        }))
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn poll_consumer_frame(
        &mut self,
        ports: &mut InstalledConsumerPorts,
        role: ConsumerProducerRole,
    ) -> Result<Progress, Error> {
        self.check_consumer_ports(ports)?;
        let result = self.poll_consumer_ready(ports, role);
        result.map_err(|error| self.poison_consumer(ports, error))
    }
    fn poll_consumer_ready(
        &mut self,
        ports: &mut InstalledConsumerPorts,
        role: ConsumerProducerRole,
    ) -> Result<Progress, Error> {
        if matches!(ports.control.binding, binding::ConsumerBinding::Raw) {
            return Err(Error::Association);
        }
        let index = role.index();
        match ports.channels[index].phase {
            Phase::Ack { .. } => return Err(Error::Outstanding),
            Phase::Closed | Phase::Drained => return Err(Error::Sequence),
            Phase::Unused => return Ok(Progress::Unused),
            Phase::EmptyHelperEof => return self.resolve_empty_helper_eof(ports),
            Phase::Poisoned => return Err(Error::PriorFault),
            Phase::Association {
                index: cache_index,
                sequence,
            } => {
                if matches!(ports.helper_association, HelperAssociation::Associated) {
                    return self.issue_consumer_ack(ports, role, cache_index, sequence);
                }
                return Ok(Progress::AwaitingAssociation);
            }
            _ => {}
        }
        let parent = ports.control.parents.get().expect("published endpoints")[index].as_fd();
        let channel = &mut ports.channels[index];
        if let Phase::Header(filled) = channel.phase {
            let Some(n) = self.consumer_read(parent, &mut channel.header[filled..])? else {
                return Ok(Progress::Pending);
            };
            if n == 0 {
                if role == ConsumerProducerRole::TransferHelper
                    && filled == 0
                    && channel.next == 0
                    && matches!(ports.helper_association, HelperAssociation::AwaitingLaunch)
                {
                    channel.phase = Phase::EmptyHelperEof;
                    return self.resolve_empty_helper_eof(ports);
                }
                return Err(Error::Framing);
            }
            let filled = filled + n;
            if filled < 4 {
                channel.phase = Phase::Header(filled);
                return Ok(Progress::Pending);
            }
            let length = u32::from_be_bytes(channel.header) as usize;
            if length > ports.control.max_frame {
                return Err(Error::FrameTooLarge);
            }
            if length == 0 {
                return Err(Error::Json);
            }
            channel.phase = Phase::Body { length, filled: 0 };
        }
        let Phase::Body { length, filled } = channel.phase else {
            return Err(Error::Shape);
        };
        let Some(n) = self.consumer_read(parent, &mut channel.buffer[filled..length])? else {
            return Ok(Progress::Pending);
        };
        if n == 0 {
            return Err(Error::Framing);
        }
        let filled = filled + n;
        if filled < length {
            channel.phase = Phase::Body { length, filled };
            return Ok(Progress::Pending);
        }
        let envelope = self.consumer_decode_body(role, &channel.buffer[..length])?;
        let sequence = envelope.sequence();
        if sequence != channel.next {
            return Err(Error::Sequence);
        }
        if channel.next == 0 && !matches!(envelope.frame, wire::Frame::Open { .. }) {
            return Err(Error::Sequence);
        }
        if channel.next != 0 && matches!(envelope.frame, wire::Frame::Open { .. }) {
            return Err(Error::Sequence);
        }
        // A role cannot reach a new Body until its previous actual ACK has
        // completed. Thus every prefix Fact here is both cached and ACKed.
        // Validate this prefix before recording/caching the incoming frame.
        let prefix_length = self.consumer_cache[index].len();
        let visits = prefix_length
            .checked_mul(std::mem::size_of::<wire::Frame>())
            .ok_or_else(|| {
                self.overflow_failure();
                Error::Resource(InstalledObservationError::SizeOverflow)
            })?;
        self.visit_observation_bytes(visits)
            .map_err(|_| Error::PriorFault)?;
        let result = self.decode.slots(prefix_length);
        self.consumer_decode(result)?;
        envelope
            .frame
            .validate_business_prefix(&self.consumer_cache[index])?;
        if role == ConsumerProducerRole::Outer
            && let wire::Frame::Close { helper, .. } = &envelope.frame
            && !ports.helper_association.accepts_outer_completion(helper)
        {
            return Err(Error::Association);
        }
        if let wire::Frame::HelperStarted { launch, .. } = &envelope.frame {
            let binding::ConsumerBinding::Observed(binding) = &ports.control.binding else {
                return Err(Error::Association);
            };
            if !matches!(ports.helper_association, HelperAssociation::AwaitingLaunch) {
                return Err(Error::Association);
            }
            let result = binding.helper_matches(launch, self.decode);
            if !self.consumer_decode(result)? {
                return Err(Error::Association);
            }
        }
        let record = self
            .receiving
            .prepare_record(ObservationRecordRole::ConsumerFrame)
            .map(|permission| permission.issue())
            .map_err(|e| *e);
        if let Err(error) = record {
            self.observation_failure(error);
            return Err(Error::Resource(error));
        }
        let result = self.decode.slots(1);
        self.consumer_decode(result)?;
        let result = super::super::super::collection::grow(
            self.receiving,
            &mut self.consumer_cache[index],
            1,
        );
        if let Err(error) = result {
            self.observation_failure(error);
            return Err(Error::Resource(error));
        }
        let cache_index = self.consumer_cache[index].len();
        let starts_helper = matches!(envelope.frame, wire::Frame::HelperStarted { .. });
        self.consumer_cache[index].push(envelope);
        if starts_helper {
            ports.helper_association = HelperAssociation::Associated;
        }
        if role == ConsumerProducerRole::TransferHelper
            && matches!(ports.helper_association, HelperAssociation::AwaitingLaunch)
        {
            ports.channels[index].phase = Phase::Association {
                index: cache_index,
                sequence,
            };
            return Ok(Progress::AwaitingAssociation);
        }
        self.issue_consumer_ack(ports, role, cache_index, sequence)
    }
    fn resolve_empty_helper_eof(
        &mut self,
        ports: &mut InstalledConsumerPorts,
    ) -> Result<Progress, Error> {
        // Real zero-byte EOF is retained independently of the other role's
        // progress. Only a SAME ACK-completed native no-helper Close resolves
        // it; metadata alone never invents an endpoint EOF or helper join.
        if !matches!(ports.helper_association, HelperAssociation::AwaitingLaunch) {
            return Err(Error::Framing);
        }
        if matches!(
            ports.channels[ConsumerProducerRole::Outer.index()].phase,
            Phase::Closed | Phase::Drained
        ) {
            ports.channels[ConsumerProducerRole::TransferHelper.index()].phase = Phase::Unused;
            return Ok(Progress::Unused);
        }
        Ok(Progress::AwaitingAssociation)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn write_consumer_ack(
        &mut self,
        ports: &mut InstalledConsumerPorts,
        ticket: &mut Ticket,
    ) -> Result<Ack, Error> {
        self.consumer_ack_step(ports, ticket, usize::MAX)
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn test_write_consumer_ack_capped(
        &mut self,
        ports: &mut InstalledConsumerPorts,
        ticket: &mut Ticket,
        max_bytes: std::num::NonZeroUsize,
    ) -> Result<Ack, Error> {
        self.consumer_ack_step(ports, ticket, max_bytes.get())
    }
    fn consumer_ack_step(
        &mut self,
        ports: &mut InstalledConsumerPorts,
        ticket: &mut Ticket,
        max_bytes: usize,
    ) -> Result<Ack, Error> {
        self.check_consumer_ports(ports)?;
        let result = self.consumer_ack_ready(ports, ticket, max_bytes);
        result.map_err(|error| self.poison_consumer(ports, error))
    }
    fn consumer_ack_ready(
        &mut self,
        ports: &mut InstalledConsumerPorts,
        ticket: &mut Ticket,
        max_bytes: usize,
    ) -> Result<Ack, Error> {
        if !ticket.control.ptr_eq(&Arc::downgrade(&ports.control)) || ticket.cursor >= ticket.length
        {
            return Err(Error::Ticket);
        }
        let channel = &mut ports.channels[ticket.role.index()];
        if !matches!(channel.phase,Phase::Ack{index,sequence}if index==ticket.cache_index&&sequence==ticket.sequence)
        {
            return Err(Error::Ticket);
        }
        let end = ticket.length.min(ticket.cursor.saturating_add(max_bytes));
        self.visit_observation_bytes(end - ticket.cursor)
            .map_err(|_| Error::PriorFault)?;
        let fd =
            ports.control.parents.get().expect("published endpoints")[ticket.role.index()].as_fd();
        match rustix::io::write(fd, &ticket.bytes[ticket.cursor..end]) {
            Ok(0) => Err(Error::Io(std::io::ErrorKind::WriteZero)),
            Ok(n) => {
                ticket.cursor += n;
                if ticket.cursor < ticket.length {
                    return Ok(Ack::Pending);
                }
                channel.next = ticket.sequence.checked_add(1).ok_or(Error::Sequence)?;
                channel.phase = if matches!(
                    self.consumer_cache[ticket.role.index()][ticket.cache_index].frame,
                    wire::Frame::Close { .. }
                ) {
                    Phase::Closed
                } else {
                    Phase::Header(0)
                };
                Ok(Ack::Complete)
            }
            Err(rustix::io::Errno::AGAIN | rustix::io::Errno::INTR) => Ok(Ack::Pending),
            Err(error) => Err(Error::Io(
                std::io::Error::from_raw_os_error(error.raw_os_error()).kind(),
            )),
        }
    }
}
