//! One cached OS-domain export. No claim about an arbitrary runtime's clock.
use super::*;
use wire::ConsumerCodecError as Error;
unsafe extern "C" {
    fn mach_continuous_time() -> u64;
    fn mach_timebase_info(info: *mut MachTimebase) -> i32;
}
#[repr(C)]
struct MachTimebase {
    numer: u32,
    denom: u32,
}
pub(super) enum PreparedClock {
    Unlaunched,
    Issued(deadline::DarwinContinuousDeadline),
}
impl PreparedClock {
    pub(super) fn selector_count(&self) -> usize {
        match self {
            Self::Unlaunched => 0,
            Self::Issued(_) => 7,
        }
    }
    pub(super) fn into_cache(self) -> OnceLock<Result<deadline::DarwinContinuousDeadline, Error>> {
        match self {
            Self::Unlaunched => OnceLock::new(),
            Self::Issued(value) => OnceLock::from(Ok(value)),
        }
    }
}
pub(super) fn sample() -> Result<(Instant, u64, Instant, deadline::Timebase), Error> {
    let mut ratio = MachTimebase { numer: 0, denom: 0 };
    // SDK C layout/calls; no allocation or pointer escape.
    if unsafe { mach_timebase_info(&mut ratio) } != 0 {
        return Err(Error::Deadline(deadline::DeadlineError::InvalidTimebase));
    }
    let timebase = deadline::Timebase::new(ratio.numer, ratio.denom).map_err(Error::Deadline)?;
    let before = Instant::now();
    let ticks = unsafe { mach_continuous_time() };
    let after = Instant::now();
    Ok((before, ticks, after, timebase))
}
impl InstalledClientRun<'_> {
    fn issue_consumer_deadline<'p>(
        &mut self,
        ports: &'p InstalledConsumerPorts,
        sample: impl FnOnce() -> Result<(Instant, u64, Instant, deadline::Timebase), Error>,
    ) -> Result<&'p deadline::DarwinContinuousDeadline, Error> {
        self.check_consumer_ports(ports)?;
        if matches!(ports.control.binding, binding::ConsumerBinding::Raw) {
            return Err(self.consumer_fault(Error::Association));
        }
        let value = ports.control.deadline.get_or_init(|| {
            sample().and_then(|(before, ticks, after, timebase)| {
                deadline::export(ports.control.end, before, ticks, after, timebase)
                    .map_err(Error::Deadline)
            })
        });
        match value {
            Ok(value) => Ok(value),
            Err(error) => Err(self.consumer_fault(*error)),
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn consumer_deadline<
        'p,
    >(
        &mut self,
        ports: &'p InstalledConsumerPorts,
    ) -> Result<&'p deadline::DarwinContinuousDeadline, Error> {
        self.issue_consumer_deadline(ports, sample)
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn test_consumer_deadline_with<
        'p,
    >(
        &mut self,
        ports: &'p InstalledConsumerPorts,
        _role: ConsumerProducerRole,
        sample: impl FnOnce() -> (Instant, u64, Instant, deadline::Timebase),
    ) -> Result<&'p deadline::DarwinContinuousDeadline, Error> {
        self.issue_consumer_deadline(ports, || Ok(sample()))
    }
}
