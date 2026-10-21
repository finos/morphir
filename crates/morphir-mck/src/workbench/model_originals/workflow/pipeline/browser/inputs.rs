//! Borrowed input projections. No expected, raw scenario or compiled-core getter.
use crate::workbench::model_originals::workflow::{
    FixtureAlias, Natural, Text,
    compile::{Definition, DefinitionOrigin},
    decode::DecodeError,
    expansion::ExpansionError,
    input::{self, ClientAction, ClientFixture, ClientFixtureMode, ClientRuntime},
    meaning::Role,
    observation_check::ObservationError,
    pairing::PairedRun,
    pipeline::{
        installed::observation::{InstalledObservationFault, InstalledObservationOwner},
        policy::Owners,
    },
    scope::SourcePosition,
    source_compile::{CompiledExecution, CompiledSourceCase},
    work::{ClosureError, Resource},
};
#[derive(Debug)]
pub(super) enum BrowserInputFault {
    Decode(DecodeError),
    Closure(ClosureError),
    Expansion(ExpansionError),
    Comparison(ObservationError),
    Receiving(InstalledObservationFault),
}
pub(super) struct BrowserOwnerLoans<'owners> {
    owners: &'owners mut Owners,
    receiving: &'owners mut InstalledObservationOwner,
}
impl<'owners> BrowserOwnerLoans<'owners> {
    pub(super) fn new(
        owners: &'owners mut Owners,
        receiving: &'owners mut InstalledObservationOwner,
    ) -> Self {
        Self { owners, receiving }
    }
    pub(super) fn ready(&self) -> Result<(), BrowserInputFault> {
        // Retain the existing comparison-before-decoder order.
        self.owners
            .comparison
            .ready()
            .map_err(BrowserInputFault::Comparison)?;
        self.owners
            .decode
            .ready()
            .map_err(BrowserInputFault::Decode)?;
        self.owners
            .closure
            .ready()
            .map_err(BrowserInputFault::Closure)?;
        self.owners
            .expansion
            .ready()
            .map_err(BrowserInputFault::Expansion)?;
        self.receiving
            .ready()
            .map_err(|fault| BrowserInputFault::Receiving(*fault))
    }
    fn visits(&mut self, count: usize) -> Result<(), BrowserInputFault> {
        self.ready()?;
        self.owners
            .closure
            .charge(Resource::StructuralVisits, count)
            .map_err(BrowserInputFault::Closure)
    }
}
pub(super) struct BorrowedOriginalClients<'compiled, 'case, 'sources, 'raw, 'supplied> {
    compiled: &'compiled [CompiledExecution<'case, 'sources, 'raw, 'supplied>],
}
impl<'compiled, 'case, 'sources, 'raw, 'supplied>
    BorrowedOriginalClients<'compiled, 'case, 'sources, 'raw, 'supplied>
{
    pub(super) fn new(
        compiled: &'compiled [CompiledExecution<'case, 'sources, 'raw, 'supplied>],
    ) -> Self {
        Self { compiled }
    }
    pub(super) fn case_count(&self) -> usize {
        self.compiled.len()
    }
    pub(super) fn visit_clients(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
        mut visit: impl FnMut(
            BrowserClientInput<'compiled, 'case, 'sources, 'raw, 'supplied>,
            &mut BrowserOwnerLoans<'_>,
        ) -> Result<(), BrowserInputFault>,
    ) -> Result<(), BrowserInputFault> {
        loans.ready()?;
        for (case_index, execution) in self.compiled.iter().enumerate() {
            loans.visits(1)?;
            if let CompiledExecution::Current(core) = execution
                && matches!(core.source().paired().run(), PairedRun::Client { .. })
            {
                visit(BrowserClientInput { core, case_index }, loans)?;
            }
        }
        Ok(())
    }
}
pub(super) struct BrowserClientInput<'compiled, 'case, 'sources, 'raw, 'supplied> {
    core: &'compiled CompiledSourceCase<'case, 'sources, 'raw, 'supplied>,
    case_index: usize,
}
impl<'compiled, 'case> BrowserClientInput<'compiled, 'case, '_, '_, '_> {
    pub(super) fn case_index(&self) -> usize {
        self.case_index
    }
    pub(super) fn run_index(&self) -> usize {
        self.core.source().paired().run_index()
    }
    pub(super) fn fixture(&self) -> BrowserFixtureInput<'case> {
        let PairedRun::Client { fixture, .. } = self.core.source().paired().run() else {
            unreachable!("issued client view")
        };
        BrowserFixtureInput { input: fixture }
    }
    pub(super) fn actions(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<
        impl ExactSizeIterator<Item = BrowserActionInput<'case>> + use<'case>,
        BrowserInputFault,
    > {
        let PairedRun::Client { actions, .. } = self.core.source().paired().run() else {
            unreachable!("issued client view")
        };
        loans.visits(actions.len())?;
        Ok(actions
            .iter()
            .enumerate()
            .map(|(position, input)| BrowserActionInput {
                kind: project_action(input),
                #[cfg(test)]
                input,
                position,
            }))
    }
    pub(super) fn input_aliases(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<
        impl Iterator<Item = BrowserInputAlias<'compiled, 'compiled>> + use<'compiled>,
        BrowserInputFault,
    > {
        let definitions = self.core.aliases().definitions();
        loans.visits(definitions.len())?;
        Ok(definitions.iter().filter_map(|definition| {
            if definition.origin != DefinitionOrigin::Input {
                return None;
            }
            let position = match definition.position {
                SourcePosition::Fixture => BrowserInputPosition::Fixture,
                SourcePosition::Action(index) => BrowserInputPosition::Action(index),
                SourcePosition::Expected(_) => return None,
            };
            alias_kind(definition.role).map(|kind| BrowserInputAlias {
                kind,
                position,
                definition,
            })
        }))
    }
}
pub(super) struct BrowserActionInput<'case> {
    #[cfg(test)]
    input: &'case ClientAction,
    position: usize,
    kind: BrowserActionKind<'case>,
}
#[derive(Clone, Copy)]
pub(super) enum BrowserActionKind<'case> {
    StartConnected {
        attempt: &'case FixtureAlias,
        project_id: &'case Text<0, 12288>,
        scope: &'case input::ClientActionStartConnectedScope,
        semantic: &'case input::ClientActionStartConnectedSemantic,
        source: &'case input::SourceIdentity,
    },
    BindModelOwner {
        attempt: &'case FixtureAlias,
        model: &'case FixtureAlias,
    },
    DownloadOriginal {
        model: &'case FixtureAlias,
        target: &'case input::ClientActionDownloadOriginalTarget,
    },
    DownloadArchive {
        model: &'case FixtureAlias,
    },
    CloseModel {
        model: &'case FixtureAlias,
    },
    CloseCurrentModel,
    Checkpoint {
        name: &'case FixtureAlias,
    },
    Unsupported,
}
impl<'case> BrowserActionInput<'case> {
    pub(super) fn position(&self) -> usize {
        self.position
    }
    pub(super) fn kind(&self) -> BrowserActionKind<'case> {
        self.kind
    }
}
fn project_action(input: &ClientAction) -> BrowserActionKind<'_> {
    match input {
        ClientAction::StartConnected {
            attempt,
            project_id,
            scope,
            semantic,
            source,
        } => BrowserActionKind::StartConnected {
            attempt,
            project_id,
            scope,
            semantic,
            source,
        },
        ClientAction::BindModelOwner { attempt, model } => {
            BrowserActionKind::BindModelOwner { attempt, model }
        }
        ClientAction::DownloadOriginal { model, target } => {
            BrowserActionKind::DownloadOriginal { model, target }
        }
        ClientAction::DownloadArchive { model } => BrowserActionKind::DownloadArchive { model },
        ClientAction::CloseModel { model } => BrowserActionKind::CloseModel { model },
        ClientAction::CloseCurrentModel {} => BrowserActionKind::CloseCurrentModel,
        ClientAction::Checkpoint { name } => BrowserActionKind::Checkpoint { name },
        _ => BrowserActionKind::Unsupported,
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum BrowserInputAliasKind {
    Model,
    OpeningAttempt,
    LiteralPeer,
    File,
    Checkpoint,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum BrowserInputPosition {
    Fixture,
    Action(usize),
}
fn alias_kind(role: Role) -> Option<BrowserInputAliasKind> {
    match role {
        Role::Model => Some(BrowserInputAliasKind::Model),
        Role::OpeningAttempt => Some(BrowserInputAliasKind::OpeningAttempt),
        Role::LiteralPeer => Some(BrowserInputAliasKind::LiteralPeer),
        Role::File => Some(BrowserInputAliasKind::File),
        Role::Checkpoint => Some(BrowserInputAliasKind::Checkpoint),
        _ => None,
    }
}
pub(super) struct BrowserInputAlias<'definition, 'case> {
    definition: &'definition Definition<'case>,
    kind: BrowserInputAliasKind,
    position: BrowserInputPosition,
}
impl<'case> BrowserInputAlias<'_, 'case> {
    pub(super) fn kind(&self) -> BrowserInputAliasKind {
        self.kind
    }
    pub(super) fn alias(&self) -> &'case FixtureAlias {
        self.definition.alias
    }
    pub(super) fn position(&self) -> BrowserInputPosition {
        self.position
    }
}
pub(super) struct BrowserFixtureInput<'case> {
    input: &'case ClientFixture,
}
pub(super) enum BrowserRuntimeInput<'case> {
    ControlledModelOriginalsHttpV1 {
        manifest: &'case input::ClientRuntimeControlledModelOriginalsHttpV1Manifest,
        manifest_byte_limit: &'case Natural<1, 131072>,
        peer: &'case FixtureAlias,
    },
    Unsupported,
}
pub(super) struct BrowserFixtureFile<'case> {
    input: &'case input::ClientFixtureFilesItem,
}
pub(super) struct BrowserFixturePeer<'case> {
    input: &'case input::ClientFixtureLiteralPeersItem,
}
impl<'case> BrowserFixtureInput<'case> {
    pub(super) fn runtime(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<BrowserRuntimeInput<'case>, BrowserInputFault> {
        loans.visits(1)?;
        Ok(match &self.input.mode {
            ClientFixtureMode::Runtime {
                runtime:
                    ClientRuntime::ControlledModelOriginalsHttpV1 {
                        manifest,
                        manifest_byte_limit,
                        peer,
                    },
            } => BrowserRuntimeInput::ControlledModelOriginalsHttpV1 {
                manifest,
                manifest_byte_limit,
                peer,
            },
            _ => BrowserRuntimeInput::Unsupported,
        })
    }
    pub(super) fn files(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<
        impl ExactSizeIterator<Item = BrowserFixtureFile<'case>> + use<'case>,
        BrowserInputFault,
    > {
        loans.visits(self.input.files.0.len())?;
        Ok(self
            .input
            .files
            .0
            .iter()
            .map(|input| BrowserFixtureFile { input }))
    }
    pub(super) fn peers(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<
        impl ExactSizeIterator<Item = BrowserFixturePeer<'case>> + use<'case>,
        BrowserInputFault,
    > {
        loans.visits(self.input.literal_peers.0.len())?;
        Ok(self
            .input
            .literal_peers
            .0
            .iter()
            .map(|input| BrowserFixturePeer { input }))
    }
}
impl<'case> BrowserFixtureFile<'case> {
    pub(super) fn alias(&self) -> &'case FixtureAlias {
        &self.input.alias
    }
    pub(super) fn bytes(&self) -> &'case input::Bytes {
        &self.input.bytes
    }
}
impl<'case> BrowserFixturePeer<'case> {
    pub(super) fn alias(&self) -> &'case FixtureAlias {
        &self.input.alias
    }
    pub(super) fn frames(&self) -> &'case [input::Frame] {
        &self.input.frames.0
    }
    pub(super) fn requests(&self) -> Option<&'case [input::Frame]> {
        match &self.input.requests {
            crate::workbench::model_originals::workflow::Presence::Absent => None,
            crate::workbench::model_originals::workflow::Presence::Present(requests) => {
                Some(&requests.0)
            }
        }
    }
}
#[cfg(test)]
mod tests;
