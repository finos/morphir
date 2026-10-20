//! Pair the independently authored scenario and expectation before compiling
//! references or executing effects. Pairing does not verify packet provenance.
use super::{UniqueKey, domain, input};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum PairError {
    Packet,
    Digest,
    Case,
    RunIndex,
    Role,
}

#[derive(Debug, Clone, Copy)]
pub(super) enum PairedRun<'a> {
    Server {
        actions: &'a [input::HostAction],
        fixture: &'a input::HostFixture,
    },
    Client {
        actions: &'a [input::ClientAction],
        fixture: &'a input::ClientFixture,
    },
}

/// Only origin-metadata equality, run selection and role correspondence have
/// been checked. This value grants no effect or filesystem authority and is
/// not a compiled, provenance-verified or ready-to-run workflow.
pub(super) struct PairedWorkflow<'a> {
    scenario: &'a input::Scenario,
    expected: &'a domain::ExpectedWorkflow,
    run: PairedRun<'a>,
    run_index: usize,
}
impl<'a> PairedWorkflow<'a> {
    pub(super) fn new(
        scenario: &'a input::Scenario,
        expected: &'a domain::ExpectedWorkflow,
    ) -> Result<Self, PairError> {
        let (origin, index) = match expected {
            domain::ExpectedWorkflow::ModelOriginalsServer {
                origin, run_index, ..
            }
            | domain::ExpectedWorkflow::ModelOriginalsClient {
                origin, run_index, ..
            } => (origin, run_index.0),
        };
        // The two independent wire schemas have closed packet vocabularies.
        // Their canonical tokens are compared only at this pairing boundary;
        // equality is not proof that either hash belongs to a trusted packet.
        if scenario.origin.packet.key() != origin.packet.key() {
            return Err(PairError::Packet);
        }
        if scenario.origin.sha256 != origin.sha256 {
            return Err(PairError::Digest);
        }
        if scenario.origin.id.0 != origin.id.0 {
            return Err(PairError::Case);
        }
        let run_index = usize::try_from(index).map_err(|_| PairError::RunIndex)?;
        let source = scenario.runs.0.get(run_index).ok_or(PairError::RunIndex)?;
        let run = match (source, expected) {
            (
                input::Run::ModelOriginalsServer { actions, fixture },
                domain::ExpectedWorkflow::ModelOriginalsServer { .. },
            ) => PairedRun::Server {
                actions: &actions.0,
                fixture,
            },
            (
                input::Run::ModelOriginalsClient { actions, fixture },
                domain::ExpectedWorkflow::ModelOriginalsClient { .. },
            ) => PairedRun::Client {
                actions: &actions.0,
                fixture,
            },
            _ => return Err(PairError::Role),
        };
        Ok(Self {
            scenario,
            expected,
            run,
            run_index,
        })
    }
    pub(super) fn run_index(&self) -> usize {
        self.run_index
    }
    pub(super) fn scenario(&self) -> &'a input::Scenario {
        self.scenario
    }
    pub(super) fn expected(&self) -> &'a domain::ExpectedWorkflow {
        self.expected
    }
    pub(super) fn run(&self) -> PairedRun<'a> {
        self.run
    }
}

#[cfg(test)]
mod tests;
