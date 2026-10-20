//! Borrowed installed-client invocation. Effects stay with the actual adapter;
//! source labels, recipe DATA and budget permission never grant OS authority.
use super::super::super::UniqueKey;
use super::super::super::{
    installed_client, observation_check, source_compile::CompiledSourceCase,
};
use super::super::{Attempt, RunFault, WorkflowRecordError};
use super::observation::InstalledObservationOwner;
pub use super::observation::{
    InstalledObservationFault as InstalledObservationError, InstalledObservationResource,
    InstalledObservationUsage, ProcessPrefixReservation, SnapshotReadPermission,
};
use crate::workbench::configuration::NativeObservationLimits;
pub use crate::workbench::model_originals::workflow::installed_measurements::InstalledClientMeasurements;
use crate::workbench::model_originals::workflow::native::{self, record_retention};
use native::data::{Bytes, SourcePath, Text};
use native::{FixtureAlias, PrivateRecordAdoption, PrivateRecordError, RecordRetentionUsage};
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstalledAdapterError {
    Cancelled,
    ObservationIncomplete,
}
pub trait InstalledClientAdapter {
    fn observe(
        &mut self,
        run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError>;
}
/// Actual compiled immutable source plus the real whole-run owners. No free
/// constructor, Clone, Deserialize, Deref or expected/core/whole-input access.
pub struct InstalledClientRun<'a> {
    source: super::InstalledClientRun<'a, 'a, 'a, 'a, 'a>,
    limits: &'a NativeObservationLimits,
    comparison: &'a mut observation_check::CompareOwner,
    records: &'a mut record_retention::RecordRetentionOwner,
    receiving: &'a mut InstalledObservationOwner,
    attempt: &'a mut Attempt,
}
impl<'a> InstalledClientRun<'a> {
    pub(super) fn from_prepared(
        source: super::InstalledClientRun<'a, 'a, 'a, 'a, 'a>,
        limits: &'a NativeObservationLimits,
        comparison: &'a mut observation_check::CompareOwner,
        records: &'a mut record_retention::RecordRetentionOwner,
        receiving: &'a mut InstalledObservationOwner,
        attempt: &'a mut Attempt,
    ) -> Self {
        Self {
            source,
            limits,
            comparison,
            records,
            receiving,
            attempt,
        }
    }
    pub fn source(&self) -> InstalledClientSource<'_> {
        InstalledClientSource(self.source.selected)
    }
    pub fn fixture(&self) -> InstalledClientFixture<'a> {
        InstalledClientFixture(self.source.plan)
    }
    pub fn actions(&self) -> impl ExactSizeIterator<Item = InstalledClientAction<'a>> + use<'a> {
        self.source.plan.actions().map(action)
    }
    pub fn observation_limits(&self) -> &NativeObservationLimits {
        self.limits
    }
    fn work_ready(&mut self) -> Result<(), InstalledAdapterError> {
        if let Err(error) = self.comparison.ready() {
            self.attempt
                .fail(RunFault::Record(WorkflowRecordError::Observation(error)))
        }
        if let Err(error) = self.records.ready() {
            self.attempt.fail(RunFault::RecordRetention(*error))
        }
        if let Err(error) = self.receiving.ready() {
            self.attempt.fail(RunFault::InstalledObservation(*error))
        }
        self.attempt
            .ready()
            .map_err(|_| InstalledAdapterError::ObservationIncomplete)
    }
    pub fn materialize_fixture_bytes(
        &mut self,
        bytes: &Bytes,
    ) -> Result<crate::workbench::model_originals::FixtureBytes, InstalledAdapterError> {
        self.work_ready()?;
        match observation_check::server::recipe(bytes, self.comparison) {
            Ok(recipe) => Ok(recipe),
            Err(error) => {
                self.attempt
                    .fail(RunFault::Record(WorkflowRecordError::Observation(error)));
                Err(InstalledAdapterError::ObservationIncomplete)
            }
        }
    }
    pub fn private_record_retention_usage(&self) -> RecordRetentionUsage {
        self.records.usage()
    }
    pub fn prepare_private_record_adoption<'ticket>(
        &'ticket mut self,
        actual: &Vec<u8>,
    ) -> Result<PrivateRecordAdoption<'ticket>, &'ticket PrivateRecordError> {
        if self.work_ready().is_err() {
            return Err(self.records.refuse_prior_work());
        }
        match record_retention::prepare(self.records, self.comparison, actual) {
            Ok(ticket) => Ok(ticket),
            Err(error) => {
                self.attempt.fail(RunFault::RecordRetention(*error));
                Err(error)
            }
        }
    }
    pub fn installed_observation_usage(&self) -> InstalledObservationUsage {
        self.receiving.usage()
    }
    pub fn reserve_process_prefixes(
        &mut self,
        actual: &crate::transport::Limits,
    ) -> Result<ProcessPrefixReservation<'_>, &InstalledObservationError> {
        if self.work_ready().is_err() {
            return Err(self.receiving.refuse_prior_fault());
        }
        match self.receiving.reserve_process_prefixes(actual) {
            Ok(ticket) => Ok(ticket),
            Err(error) => {
                self.attempt.fail(RunFault::InstalledObservation(*error));
                Err(error)
            }
        }
    }
    pub fn prepare_snapshot_read(
        &mut self,
        requested: usize,
    ) -> Result<SnapshotReadPermission<'_>, &InstalledObservationError> {
        if self.work_ready().is_err() {
            return Err(self.receiving.refuse_prior_fault());
        }
        match self.receiving.prepare_snapshot_read(requested) {
            Ok(ticket) => Ok(ticket),
            Err(error) => {
                self.attempt.fail(RunFault::InstalledObservation(*error));
                Err(error)
            }
        }
    }
}
pub struct InstalledClientSource<'a>(&'a CompiledSourceCase<'a, 'a, 'a, 'a>);
impl InstalledClientSource<'_> {
    pub fn case_id(&self) -> &str {
        self.0.source().case().id()
    }
    pub fn original_packet(&self) -> &str {
        self.0.source().paired().scenario().origin.packet.key()
    }
    pub fn original_id(&self) -> &str {
        self.0.source().paired().scenario().origin.id.0.as_str()
    }
    pub fn run_index(&self) -> usize {
        self.0.source().paired().run_index()
    }
    pub fn operation(&self) -> crate::workbench::Operation {
        crate::workbench::Operation::ModelOriginalsClient
    }
}
pub struct InstalledClientFixture<'a>(&'a installed_client::InstalledClientPlan<'a>);
impl<'a> InstalledClientFixture<'a> {
    pub fn module(&self) -> &'a SourcePath {
        &self.0.fixture().module
    }
    pub fn nodes(&self) -> impl ExactSizeIterator<Item = InstalledFixtureNode<'a>> + use<'a> {
        let mut sources = self.0.fixture_sources();
        self.0.fixture().nodes.0.iter().map(move |node| match node {
            installed_client::FixtureNode::Literal { path, bytes } => {
                InstalledFixtureNode::Literal { path, bytes }
            }
            installed_client::FixtureNode::ByteSource { path, source } => {
                InstalledFixtureNode::ByteSource {
                    path,
                    alias: source,
                    bytes: &sources
                        .next()
                        .expect("compiler resolved each fixture source in order")
                        .bytes,
                }
            }
        })
    }
}
pub enum InstalledFixtureNode<'a> {
    Literal {
        path: &'a SourcePath,
        bytes: &'a Bytes,
    },
    ByteSource {
        path: &'a SourcePath,
        alias: &'a FixtureAlias,
        bytes: &'a Bytes,
    },
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstalledCommand {
    Connect,
    List,
    Publish,
}
pub enum InstalledClientAction<'a> {
    PrepareFixture,
    StartObservedHost,
    Run {
        command: InstalledCommand,
        arguments: &'a [Text<0, { usize::MAX }>],
    },
    Checkpoint {
        name: &'a str,
    },
    WriteSourceSelection,
    WriteProjectSelection,
    StopAndJoin,
}
fn action(value: &installed_client::Action) -> InstalledClientAction<'_> {
    match value {
        installed_client::Action::Prepare {} => InstalledClientAction::PrepareFixture,
        installed_client::Action::Host {} => InstalledClientAction::StartObservedHost,
        installed_client::Action::Run { command, arguments } => InstalledClientAction::Run {
            command: match command {
                installed_client::Command::Connect => InstalledCommand::Connect,
                installed_client::Command::List => InstalledCommand::List,
                installed_client::Command::Publish => InstalledCommand::Publish,
            },
            arguments: &arguments.0,
        },
        installed_client::Action::Checkpoint { name } => InstalledClientAction::Checkpoint {
            name: name.as_str(),
        },
        installed_client::Action::Source {} => InstalledClientAction::WriteSourceSelection,
        installed_client::Action::Project {} => InstalledClientAction::WriteProjectSelection,
        installed_client::Action::Stop {} => InstalledClientAction::StopAndJoin,
    }
}
