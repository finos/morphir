//! Closed internal candidate, not a generic runtime or source-build claim.
//! Source/probe association: selected arm64 Node bytes b468…, length122503472;
//! Node24.22/libuv1.52.1 Darwin continuous integer basis, actual disjoint-clock
//! probe with real child/status/readers. Program path is matched, not pinned.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::data;
use wire::ConsumerCodecError as Error;

pub(super) const RESERVED_KEYS: [&str; 9] = [
    "MORPHIR_PRIVATE_CONSUMER_OUTER_FD",
    "MORPHIR_PRIVATE_CONSUMER_HELPER_FD",
    "MORPHIR_PRIVATE_CONSUMER_VERSION",
    "MORPHIR_PRIVATE_CONSUMER_CLOCK_DOMAIN",
    "MORPHIR_PRIVATE_CONSUMER_CLOCK_VERSION",
    "MORPHIR_PRIVATE_CONSUMER_CLOCK_AT_NS",
    "MORPHIR_PRIVATE_CONSUMER_END_NS",
    "MORPHIR_PRIVATE_CONSUMER_TIMEBASE_NUMER",
    "MORPHIR_PRIVATE_CONSUMER_TIMEBASE_DENOM",
];
use super::candidate::{SELECTED_LENGTH, SELECTED_SHA};
struct Decimal {
    bytes: [u8; 20],
    start: usize,
}
impl Decimal {
    fn new(mut value: u64) -> Self {
        let mut bytes = [0; 20];
        let mut start = 20;
        loop {
            start -= 1;
            bytes[start] = b'0' + (value % 10) as u8;
            value /= 10;
            if value == 0 {
                break;
            }
        }
        Self { bytes, start }
    }
    fn as_str(&self) -> &str {
        std::str::from_utf8(&self.bytes[self.start..]).expect("decimal ASCII")
    }
}
impl InstalledClientRun<'_> {
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn prepare_clocked_observed_consumer_process(
        &mut self,
        command: ConsumerProcessCommand<'_>,
        end: Instant,
        implementation: &data::ImplementationObservation,
    ) -> Result<(PreparedInstalledConsumerProcess, InstalledConsumerPorts), Error> {
        self.work_ready().map_err(|_| Error::PriorFault)?;
        // Caller selectors never become execution, lane or clock authority.
        // Reject before any copies or endpoint registration.
        for (key, _) in command.environment {
            let visits = RESERVED_KEYS
                .iter()
                .try_fold(key.len(), |count, key| count.checked_add(key.len()))
                .ok_or_else(|| {
                    self.overflow_failure();
                    Error::Resource(InstalledObservationError::SizeOverflow)
                })?;
            self.visit_observation_bytes(visits)
                .map_err(|_| self.consumer_receiving_error())?;
            if RESERVED_KEYS.iter().any(|reserved| key == reserved) {
                return Err(self.consumer_fault(Error::Association));
            }
        }
        let data::ImplementationObservation::Observed {
            runtime, launch, ..
        } = implementation
        else {
            return Err(self.consumer_fault(Error::ClockBasis));
        };
        let observed = binding::operand(&runtime.program)
            .map_err(|_| self.consumer_fault(Error::ClockBasis))?;
        self.visit_observation_bytes(
            observed
                .len()
                .saturating_add(command.program.as_os_str().len())
                .saturating_add(64),
        )
        .map_err(|_| self.consumer_receiving_error())?;
        if !cfg!(all(target_os = "macos", target_arch = "aarch64"))
            || runtime.byte_length.get() != SELECTED_LENGTH
            || runtime.sha256.0 != SELECTED_SHA
            || matches!(launch, data::LaunchObservation::NodePackage { .. })
                && observed != command.program.as_os_str()
        {
            return Err(self.consumer_fault(Error::ClockBasis));
        }
        // Existing full canonical matcher also binds native's verified Node
        // operand. Native executable is not confused with its Node runtime.
        let binding = self
            .observed_consumer_binding(&command, implementation)
            .map_err(|_| self.consumer_receiving_error())?;
        let effective = self
            .consumer_end(end)
            .map_err(|_| self.consumer_receiving_error())?;
        let (before, ticks, after, timebase) =
            export::sample().map_err(|error| self.consumer_fault(error))?;
        if timebase.numerator() != 125 || timebase.denominator() != 3 {
            return Err(self.consumer_fault(Error::ClockBasis));
        }
        let issued = deadline::export(effective, before, ticks, after, timebase)
            .map_err(|error| self.consumer_fault(Error::Deadline(error)))?;
        self.prepare_consumer_bound(
            command,
            effective,
            binding::ConsumerBinding::Observed(binding),
            export::PreparedClock::Issued(issued),
        )
        .map_err(|_| self.consumer_receiving_error())
    }
    pub(super) fn consumer_clock_environment(
        &mut self,
        environment: &mut Vec<(OsString, OsString)>,
        clock: &export::PreparedClock,
    ) -> Result<(), InstalledAdapterError> {
        let export::PreparedClock::Issued(clock) = clock else {
            return Ok(());
        };
        self.reserve_storage(4 * std::mem::size_of::<Decimal>())?;
        self.visit_observation_bytes(80)?;
        let at = Decimal::new(clock.calibrated_at_ns());
        let end = Decimal::new(clock.end_ns());
        let numer = Decimal::new(u64::from(clock.timebase().numerator()));
        let denom = Decimal::new(u64::from(clock.timebase().denominator()));
        for (key, value) in [
            (RESERVED_KEYS[2], wire::VERSION),
            (RESERVED_KEYS[3], "darwin-mach-continuous-nanoseconds"),
            (RESERVED_KEYS[4], wire::VERSION),
            (RESERVED_KEYS[5], at.as_str()),
            (RESERVED_KEYS[6], end.as_str()),
            (RESERVED_KEYS[7], numer.as_str()),
            (RESERVED_KEYS[8], denom.as_str()),
        ] {
            environment.push((
                self.copy_command_operand(OsStr::new(key))?,
                self.copy_command_operand(OsStr::new(value))?,
            ));
        }
        Ok(())
    }
}
