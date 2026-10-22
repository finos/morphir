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
    Source(super::source_scope::ScopeFault),
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
    /// Reborrow the SAME parent-stack cumulative owners. This gives no browser,
    /// path, source, process or action permission and cannot reset any domain.
    pub(super) fn physical_owners(
        &mut self,
    ) -> Result<
        (
            &mut crate::workbench::model_originals::workflow::Decoder,
            &mut InstalledObservationOwner,
            &mut crate::workbench::model_originals::workflow::observation_check::CompareOwner,
        ),
        BrowserInputFault,
    > {
        self.ready()?;
        Ok((
            &mut self.owners.decode,
            self.receiving,
            &mut self.owners.comparison,
        ))
    }
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
    pub(super) fn visits(&mut self, count: usize) -> Result<(), BrowserInputFault> {
        self.ready()?;
        self.owners
            .closure
            .charge(Resource::StructuralVisits, count)
            .map_err(BrowserInputFault::Closure)
    }
    pub(super) fn refuse_selection<T>(
        &mut self,
        cause: ClosureError,
    ) -> Result<T, BrowserInputFault> {
        self.ready()?;
        self.owners
            .closure
            .refuse(cause)
            .map_err(BrowserInputFault::Closure)
    }
    pub(super) fn same_alias(
        &mut self,
        first: &FixtureAlias,
        second: &FixtureAlias,
    ) -> Result<bool, BrowserInputFault> {
        self.ready()?;
        self.owners
            .closure
            .same_alias(first, second)
            .map_err(BrowserInputFault::Closure)
    }
}
pub(super) struct BorrowedOriginalClients<'compiled, 'case, 'sources, 'raw, 'supplied> {
    compiled: &'compiled [CompiledExecution<'case, 'sources, 'raw, 'supplied>],
}
pub(super) enum ClientVisitFault<E> {
    Input(BrowserInputFault),
    Callback(E),
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
        visit: impl FnMut(
            BrowserClientInput<'compiled, 'case, 'sources, 'raw, 'supplied>,
            &mut BrowserOwnerLoans<'_>,
        ) -> Result<(), BrowserInputFault>,
    ) -> Result<(), BrowserInputFault> {
        self.try_visit_clients(loans, visit)
            .map_err(|fault| match fault {
                ClientVisitFault::Input(fault) | ClientVisitFault::Callback(fault) => fault,
            })
    }
    pub(super) fn try_visit_clients<E>(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
        mut visit: impl FnMut(
            BrowserClientInput<'compiled, 'case, 'sources, 'raw, 'supplied>,
            &mut BrowserOwnerLoans<'_>,
        ) -> Result<(), E>,
    ) -> Result<(), ClientVisitFault<E>> {
        loans.ready().map_err(ClientVisitFault::Input)?;
        for (case_index, execution) in self.compiled.iter().enumerate() {
            loans.visits(1).map_err(ClientVisitFault::Input)?;
            if let CompiledExecution::Current(core) = execution
                && matches!(core.source().paired().run(), PairedRun::Client { .. })
            {
                visit(BrowserClientInput { core, case_index }, loans)
                    .map_err(ClientVisitFault::Callback)?;
            }
        }
        Ok(())
    }
}
pub(super) struct BrowserClientInput<'compiled, 'case, 'sources, 'raw, 'supplied> {
    core: &'compiled CompiledSourceCase<'case, 'sources, 'raw, 'supplied>,
    case_index: usize,
}
/// Issued only by the canonical engine from its actual compiled current row.
/// This view carries no report context or expected values.
pub(super) struct BrowserExecutionInput<'compiled, 'case, 'sources, 'raw, 'supplied> {
    core: &'compiled CompiledSourceCase<'case, 'sources, 'raw, 'supplied>,
}
impl<'compiled, 'case, 'sources, 'raw, 'supplied>
    BrowserExecutionInput<'compiled, 'case, 'sources, 'raw, 'supplied>
{
    pub(super) fn from_compiled_client(
        core: &'compiled CompiledSourceCase<'case, 'sources, 'raw, 'supplied>,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<Self, BrowserInputFault> {
        loans.ready()?;
        if !matches!(core.source().paired().run(), PairedRun::Client { .. }) {
            return loans.refuse_selection(ClosureError::Semantic);
        }
        Ok(Self { core })
    }
    pub(super) fn fixture(&self) -> BrowserFixtureInput<'case> {
        let PairedRun::Client { fixture, .. } = self.core.source().paired().run() else {
            unreachable!("issued compiled client view")
        };
        BrowserFixtureInput { input: fixture }
    }
    pub(super) fn actions(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<BrowserActionInputs<'case>, BrowserInputFault> {
        client_actions(self.core, loans)
    }
}
fn client_actions<'case>(
    core: &CompiledSourceCase<'case, '_, '_, '_>,
    loans: &mut BrowserOwnerLoans<'_>,
) -> Result<BrowserActionInputs<'case>, BrowserInputFault> {
    let PairedRun::Client { actions, .. } = core.source().paired().run() else {
        unreachable!("issued client view")
    };
    loans.visits(actions.len())?;
    Ok(BrowserActionInputs {
        actions: actions.iter().enumerate(),
    })
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
    ) -> Result<BrowserActionInputs<'case>, BrowserInputFault> {
        client_actions(self.core, loans)
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
pub(super) struct BrowserActionInputs<'case> {
    actions: std::iter::Enumerate<std::slice::Iter<'case, ClientAction>>,
}
impl<'case> Iterator for BrowserActionInputs<'case> {
    type Item = BrowserActionInput<'case>;
    fn next(&mut self) -> Option<Self::Item> {
        self.actions
            .next()
            .map(|(position, input)| BrowserActionInput {
                kind: project_action(input),
                #[cfg(test)]
                input,
                position,
            })
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        self.actions.size_hint()
    }
}
impl ExactSizeIterator for BrowserActionInputs<'_> {}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserUnsupportedActionKind {
    ObserveIdentity,
    InitializeExecutionRuntime,
    StartImport,
    PreparePendingCore,
    SettlePreparedCore,
    Deliver,
    Reject,
    ReadRun,
    SignalPicker,
    CancelOpening,
    MutateCaller,
    Inspect,
    Search,
    ConceptualSpecification,
    ReplaceModel,
    SubmitExecution,
    ReleaseExecution,
    SelectCurrentDeclaration,
    BeginLocalEvaluation,
    AwaitLocalEvaluation,
    BeginNativeInitialize,
    BeginNativeChoose,
    AwaitNativeBoundary,
    BindNativeProject,
    BeginNativeOpenProject,
    DisposeNativeRuntime,
    AwaitNativeDisposal,
}
pub(super) struct BrowserActionInput<'case> {
    #[cfg(test)]
    input: &'case ClientAction,
    position: usize,
    kind: BrowserActionKind<'case>,
}
#[derive(Clone, Copy)]
pub(super) enum BrowserActionKind<'case> {
    BeginConnectedOpening {
        attempt: &'case FixtureAlias,
        pending: &'case FixtureAlias,
        project_id: &'case Text<0, 12288>,
        scope: &'case input::ClientActionBeginConnectedOpeningScope,
        semantic: &'case input::ClientActionBeginConnectedOpeningSemantic,
        source: &'case input::SourceIdentity,
        transfer_limits: &'case input::ConnectedTransferLimits,
    },
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
    AwaitConnectedBoundary {
        pending: &'case FixtureAlias,
        boundary: &'case input::ClientActionAwaitConnectedBoundaryBoundary,
    },
    ExecutePendingCore {
        effect: &'case input::EffectRef,
    },
    SearchCurrent {
        query: &'case Text<0, 16000>,
    },
    DisposeConnectedOpening {
        pending: &'case FixtureAlias,
    },
    AwaitConnectedDisposal {
        pending: &'case FixtureAlias,
    },
    Unsupported {
        kind: BrowserUnsupportedActionKind,
    },
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
        ClientAction::BeginConnectedOpening {
            attempt,
            pending,
            project_id,
            scope,
            semantic,
            source,
            transfer_limits,
        } => BrowserActionKind::BeginConnectedOpening {
            attempt,
            pending,
            project_id,
            scope,
            semantic,
            source,
            transfer_limits,
        },
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
        ClientAction::AwaitConnectedBoundary { pending, boundary } => {
            BrowserActionKind::AwaitConnectedBoundary { pending, boundary }
        }
        ClientAction::ExecutePendingCore { effect } => {
            BrowserActionKind::ExecutePendingCore { effect }
        }
        ClientAction::SearchCurrent { query } => BrowserActionKind::SearchCurrent { query },
        ClientAction::DisposeConnectedOpening { pending } => {
            BrowserActionKind::DisposeConnectedOpening { pending }
        }
        ClientAction::AwaitConnectedDisposal { pending } => {
            BrowserActionKind::AwaitConnectedDisposal { pending }
        }
        ClientAction::ObserveIdentity { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::ObserveIdentity,
        },
        ClientAction::InitializeExecutionRuntime { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::InitializeExecutionRuntime,
        },
        ClientAction::StartImport { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::StartImport,
        },
        ClientAction::PreparePendingCore { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::PreparePendingCore,
        },
        ClientAction::SettlePreparedCore { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::SettlePreparedCore,
        },
        ClientAction::Deliver { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::Deliver,
        },
        ClientAction::Reject { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::Reject,
        },
        ClientAction::ReadRun { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::ReadRun,
        },
        ClientAction::SignalPicker { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::SignalPicker,
        },
        ClientAction::CancelOpening { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::CancelOpening,
        },
        ClientAction::MutateCaller { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::MutateCaller,
        },
        ClientAction::Inspect { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::Inspect,
        },
        ClientAction::Search { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::Search,
        },
        ClientAction::ConceptualSpecification { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::ConceptualSpecification,
        },
        ClientAction::ReplaceModel { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::ReplaceModel,
        },
        ClientAction::SubmitExecution { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::SubmitExecution,
        },
        ClientAction::ReleaseExecution { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::ReleaseExecution,
        },
        ClientAction::SelectCurrentDeclaration { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::SelectCurrentDeclaration,
        },
        ClientAction::BeginLocalEvaluation { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::BeginLocalEvaluation,
        },
        ClientAction::AwaitLocalEvaluation { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::AwaitLocalEvaluation,
        },
        ClientAction::BeginNativeInitialize { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::BeginNativeInitialize,
        },
        ClientAction::BeginNativeChoose { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::BeginNativeChoose,
        },
        ClientAction::AwaitNativeBoundary { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::AwaitNativeBoundary,
        },
        ClientAction::BindNativeProject { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::BindNativeProject,
        },
        ClientAction::BeginNativeOpenProject { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::BeginNativeOpenProject,
        },
        ClientAction::DisposeNativeRuntime { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::DisposeNativeRuntime,
        },
        ClientAction::AwaitNativeDisposal { .. } => BrowserActionKind::Unsupported {
            kind: BrowserUnsupportedActionKind::AwaitNativeDisposal,
        },
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
