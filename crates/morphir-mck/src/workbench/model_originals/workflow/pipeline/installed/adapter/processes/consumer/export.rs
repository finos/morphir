//! One cached OS-domain export. No claim about an arbitrary runtime's clock.
use super::*;
use wire::ConsumerCodecError as Error;
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
    crate::workbench::model_originals::workflow::pipeline::clock::sample().map_err(Error::Deadline)
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
