//! Pair the independently authored scenario and expectation before compiling
//! references or executing effects. Pairing does not verify packet provenance.
use super::historical::{
    ClientExpectedRef, HistoricalClientExpected, HistoricalClientScenario, HistoricalError,
    ScenarioRef,
};
use super::{UniqueKey, domain, input};

#[derive(Clone, Copy)]
enum ExpectedRole {
    Client,
    Server,
}

/// Shared correspondence check for current and explicitly historical operands.
/// It compares actual independent claims, never packet trust or effect rights.
fn pair_run<'a>(
    scenario_origin: &input::PacketRef,
    runs: &'a [input::Run],
    origin: &domain::PacketRef,
    index: u64,
    role: ExpectedRole,
) -> Result<(PairedRun<'a>, usize), PairError> {
    if scenario_origin.packet.key() != origin.packet.key() {
        return Err(PairError::Packet);
    }
    if scenario_origin.sha256 != origin.sha256 {
        return Err(PairError::Digest);
    }
    if scenario_origin.id.0 != origin.id.0 {
        return Err(PairError::Case);
    }
    let index = usize::try_from(index).map_err(|_| PairError::RunIndex)?;
    let run = match (runs.get(index).ok_or(PairError::RunIndex)?, role) {
        (input::Run::ModelOriginalsClient { actions, fixture }, ExpectedRole::Client) => {
            PairedRun::Client {
                actions: &actions.0,
                fixture,
            }
        }
        (input::Run::ModelOriginalsServer { actions, fixture }, ExpectedRole::Server) => {
            PairedRun::Server {
                actions: &actions.0,
                fixture,
            }
        }
        _ => return Err(PairError::Role),
    };
    Ok((run, index))
}

/// Common borrowed client fields. Existing current consumers remain unchanged;
/// historical compiler plumbing must opt into these views explicitly.
pub(super) struct ClientPairView<'a> {
    scenario: ScenarioRef<'a>,
    expected: ClientExpectedRef<'a>,
    run: PairedRun<'a>,
    run_index: usize,
}
impl<'a> ClientPairView<'a> {
    pub(super) fn current(paired: &PairedWorkflow<'a>) -> Result<Self, PairError> {
        Ok(Self {
            scenario: paired.scenario(),
            expected: paired.client_expected()?,
            run: paired.run,
            run_index: paired.run_index,
        })
    }
    pub(super) fn historical(
        s: &'a HistoricalClientScenario,
        e: &'a HistoricalClientExpected,
        owner: &mut super::Decoder,
    ) -> Result<Self, HistoricalError> {
        owner.ready()?;
        owner.bytes(s.origin.packet.key().len())?;
        owner.bytes(e.origin.packet.key().len())?;
        owner.bytes(s.origin.sha256.0.len() + e.origin.sha256.0.len())?;
        owner.bytes(s.origin.id.0.len())?;
        owner.bytes(e.origin.id.0.len())?;
        let (run, run_index) = pair_run(
            &s.origin,
            &s.runs.0,
            &e.origin,
            e.run_index.0,
            ExpectedRole::Client,
        )?;
        Ok(Self {
            scenario: ScenarioRef::Historical(s, e.version),
            expected: ClientExpectedRef::historical(e),
            run,
            run_index,
        })
    }
    pub(super) fn scenario(&self) -> ScenarioRef<'a> {
        self.scenario
    }
    pub(super) fn expected(&self) -> &ClientExpectedRef<'a> {
        &self.expected
    }
    pub(super) fn run(&self) -> PairedRun<'a> {
        self.run
    }
    pub(super) fn run_index(&self) -> usize {
        self.run_index
    }
}

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
    operands: WorkflowOperands<'a>,
    run: PairedRun<'a>,
    run_index: usize,
}
#[derive(Clone, Copy)]
pub(super) enum WorkflowOperands<'a> {
    Current {
        scenario: &'a input::Scenario,
        expected: &'a domain::ExpectedWorkflow,
    },
    Historical {
        scenario: &'a HistoricalClientScenario,
        expected: &'a HistoricalClientExpected,
    },
}
#[derive(Clone, Copy)]
pub(super) enum ExpectedSource<'a> {
    Current(&'a domain::ExpectedWorkflow),
    Historical(&'a HistoricalClientExpected),
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
        let role = match expected {
            domain::ExpectedWorkflow::ModelOriginalsClient { .. } => ExpectedRole::Client,
            domain::ExpectedWorkflow::ModelOriginalsServer { .. } => ExpectedRole::Server,
        };
        let (run, run_index) = pair_run(&scenario.origin, &scenario.runs.0, origin, index, role)?;
        Ok(Self {
            operands: WorkflowOperands::Current { scenario, expected },
            run,
            run_index,
        })
    }
    pub(super) fn run_index(&self) -> usize {
        self.run_index
    }
    pub(super) fn scenario(&self) -> ScenarioRef<'a> {
        match self.operands {
            WorkflowOperands::Current { scenario, .. } => ScenarioRef::Current(scenario),
            WorkflowOperands::Historical { scenario, expected } => {
                ScenarioRef::Historical(scenario, expected.version)
            }
        }
    }
    pub(super) fn expected(&self) -> Option<&'a domain::ExpectedWorkflow> {
        match self.operands {
            WorkflowOperands::Current { expected, .. } => Some(expected),
            WorkflowOperands::Historical { .. } => None,
        }
    }
    pub(super) fn operands(&self) -> WorkflowOperands<'a> {
        self.operands
    }
    pub(super) fn expected_source(&self) -> ExpectedSource<'a> {
        match self.operands {
            WorkflowOperands::Current { expected, .. } => ExpectedSource::Current(expected),
            WorkflowOperands::Historical { expected, .. } => ExpectedSource::Historical(expected),
        }
    }
    pub(super) fn client_expected(&self) -> Result<ClientExpectedRef<'a>, PairError> {
        match self.expected_source() {
            ExpectedSource::Current(e) => ClientExpectedRef::current(e),
            ExpectedSource::Historical(e) => Ok(ClientExpectedRef::historical(e)),
        }
    }
    pub(super) fn historical(
        s: &'a HistoricalClientScenario,
        e: &'a HistoricalClientExpected,
        owner: &mut super::Decoder,
    ) -> Result<Self, HistoricalError> {
        let view = ClientPairView::historical(s, e, owner)?;
        Ok(Self {
            operands: WorkflowOperands::Historical {
                scenario: s,
                expected: e,
            },
            run: view.run,
            run_index: view.run_index,
        })
    }
    /// Like new(), metadata correspondence only. Canonical source binding uses
    /// historical() above with its SAME cumulative validation owner.
    pub(super) fn historical_claims(
        s: &'a HistoricalClientScenario,
        e: &'a HistoricalClientExpected,
    ) -> Result<Self, PairError> {
        let (run, run_index) = pair_run(
            &s.origin,
            &s.runs.0,
            &e.origin,
            e.run_index.0,
            ExpectedRole::Client,
        )?;
        Ok(Self {
            operands: WorkflowOperands::Historical {
                scenario: s,
                expected: e,
            },
            run,
            run_index,
        })
    }
    pub(super) fn run(&self) -> PairedRun<'a> {
        self.run
    }
}

#[cfg(test)]
mod tests;
