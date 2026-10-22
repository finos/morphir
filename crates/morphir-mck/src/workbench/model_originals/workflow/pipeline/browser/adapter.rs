//! Borrowed INPUT only. This facade neither selects a physical browser nor
//! creates an action, source, download, report or comparison authority.
#[path = "adapter/document.rs"]
mod document;
#[path = "adapter/execution_loans.rs"]
pub(super) mod execution_loans;
pub use super::controlled_input::{
    ControlledDeliveryFault, ControlledHostDelivery, ControlledHostStimulus,
    ControlledManifestDelivery, ControlledOpening, ControlledPeerDelivery,
};
use super::source_scope::BrowserSourceScope;
pub use super::source_scope::{
    ScopeFault as BrowserSourceFault, ScopeTerminal as BrowserSourceTerminal,
};
use super::{BrowserPreparationFault, inputs, prepared_browser_originals};
use crate::workbench::model_originals::workflow::{input, pipeline::PreparationFault};
use crate::workbench::{
    Corpus, RunConfiguration, configuration::Configuration, corpus::CorpusStorage,
};
pub use document::*;
use execution_loans::LoanRelation;

#[derive(Debug)]
pub struct BrowserInputError {
    cause: inputs::BrowserInputFault,
}
impl BrowserInputError {
    pub(super) fn source_cause(&self) -> Option<BrowserSourceFault> {
        match self.cause {
            inputs::BrowserInputFault::Source(cause) => Some(cause),
            _ => None,
        }
    }
}
impl From<inputs::BrowserInputFault> for BrowserInputError {
    fn from(cause: inputs::BrowserInputFault) -> Self {
        Self { cause }
    }
}
#[derive(Debug)]
pub enum BrowserVisitError<E> {
    Input(BrowserInputError),
    Callback(E),
}
impl From<BrowserVisitError<BrowserInputError>> for BrowserInputError {
    fn from(fault: BrowserVisitError<Self>) -> Self {
        match fault {
            BrowserVisitError::Input(fault) | BrowserVisitError::Callback(fault) => fault,
        }
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserPreparationErrorKind {
    WrongConfiguration,
    WrongCorpus,
    Ingress,
    InventoryWork,
    InventoryAllocation,
    Anchors,
    Compilation,
    Input,
}
#[derive(Debug)]
enum PreparationCause {
    WrongConfiguration,
    WrongCorpus,
    Prepared(BrowserPreparationFault<inputs::BrowserInputFault>),
}
#[derive(Debug)]
pub struct BrowserPreparationError {
    cause: PreparationCause,
}
impl BrowserPreparationError {
    pub fn kind(&self) -> BrowserPreparationErrorKind {
        use BrowserPreparationErrorKind as Kind;
        match &self.cause {
            PreparationCause::WrongConfiguration
            | PreparationCause::Prepared(BrowserPreparationFault::WrongConfiguration) => {
                Kind::WrongConfiguration
            }
            PreparationCause::WrongCorpus => Kind::WrongCorpus,
            PreparationCause::Prepared(BrowserPreparationFault::Preparation(fault)) => {
                match fault {
                    PreparationFault::Ingress(_) => Kind::Ingress,
                    PreparationFault::InventoryWork(_) => Kind::InventoryWork,
                    PreparationFault::InventoryAllocation(_) => Kind::InventoryAllocation,
                    PreparationFault::Anchors(_) => Kind::Anchors,
                    PreparationFault::Compilation(_) => Kind::Compilation,
                    PreparationFault::Callback(_) => Kind::Input,
                }
            }
        }
    }
}
/// Retains actual callback ownership even when its source scope has unfinished
/// debt. Quiescent is scope bookkeeping, never a certificate of physical joins.
#[derive(Debug)]
pub struct BrowserCallbackOutcome<R, E> {
    result: Result<R, E>,
    source: BrowserSourceTerminal,
}
impl<R, E> BrowserCallbackOutcome<R, E> {
    pub fn into_parts(self) -> (Result<R, E>, BrowserSourceTerminal) {
        (self.result, self.source)
    }
}
pub struct BrowserClients<'a> {
    inner: inputs::BorrowedOriginalClients<'a, 'a, 'a, 'a, 'a>,
    scope: &'a BrowserSourceScope,
}
pub struct BrowserClient<'a> {
    inner: inputs::BrowserClientInput<'a, 'a, 'a, 'a, 'a>,
    scope: &'a BrowserSourceScope,
}
pub struct BrowserLoans<'a, 'owners> {
    inner: &'a mut inputs::BrowserOwnerLoans<'owners>,
    relation: LoanRelation<'a>,
}
/// Opaque identity of one actual preparation. Neither a browser nor an action grant.
pub struct BrowserApplicationSource {
    identity: super::source_scope::ApplicationSourceIdentity,
}
impl BrowserApplicationSource {
    /// Source liveness only, serialized with revocation. Never hold across await.
    pub fn while_source_active<R>(
        &self,
        action: impl FnOnce() -> R,
    ) -> Result<R, BrowserSourceFault> {
        self.identity.while_active(action)
    }
}
/// A request permission in the existing receiving domain, not observed IO.
pub struct BrowserApplicationRead<'a> {
    inner: super::super::installed::observation::SnapshotReadPermission<'a>,
}
impl BrowserApplicationRead<'_> {
    pub fn finish(self, actual: usize) -> Result<(), BrowserInputError> {
        self.inner
            .finish(actual)
            .map_err(|fault| inputs::BrowserInputFault::Receiving(*fault).into())
    }
}
impl ControlledHostStimulus {
    pub fn prepare_delivery(
        &self,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<ControlledHostDelivery, BrowserInputError> {
        loans.validate_controlled_source(self)?;
        self.while_source_active(|| self.copy_delivery(loans.inner))
            .map_err(inputs::BrowserInputFault::Source)?
            .map_err(Into::into)
    }
}
impl BrowserLoans<'_, '_> {
    pub fn prepare_application_source(
        &mut self,
    ) -> Result<BrowserApplicationSource, BrowserInputError> {
        self.reserve_controlled_host_storage(
            std::mem::size_of::<BrowserApplicationSource>(),
            1,
            std::mem::size_of::<BrowserApplicationSource>()
                + std::mem::size_of::<std::sync::atomic::AtomicUsize>(),
        )?;
        Ok(BrowserApplicationSource {
            identity: self
                .global()
                .application_identity()
                .map_err(inputs::BrowserInputFault::Source)?,
        })
    }
    pub fn validate_application_source(
        &self,
        source: &BrowserApplicationSource,
    ) -> Result<(), BrowserInputError> {
        self.ready()?;
        source
            .identity
            .validate(self.global())
            .map_err(|fault| inputs::BrowserInputFault::Source(fault).into())
    }
    pub fn validate_controlled_application(
        &self,
        source: &BrowserApplicationSource,
        stimulus: &ControlledHostStimulus,
    ) -> Result<(), BrowserInputError> {
        self.validate_application_source(source)?;
        self.validate_controlled_source(stimulus)
    }
    /// Check the actual source relation before preparing any document backing.
    /// This produces no binding, permission, action or completion receipt.
    pub fn validate_controlled_source(
        &self,
        stimulus: &ControlledHostStimulus,
    ) -> Result<(), BrowserInputError> {
        self.ready()?;
        match self.relation {
            LoanRelation::Application(global) => stimulus.validate_scope(global),
            LoanRelation::Execution { child, .. } => stimulus.validate_invocation(&child.identity),
        }
        .map_err(|fault| inputs::BrowserInputFault::Source(fault).into())
    }
    /// Named application backing/work debit on the SAME cumulative owners.
    pub fn reserve_application_storage(
        &mut self,
        source: &BrowserApplicationSource,
        bytes: usize,
        slots: usize,
        initialized: usize,
    ) -> Result<(), BrowserInputError> {
        self.validate_application_source(source)?;
        self.reserve_controlled_host_storage(bytes, slots, initialized)
    }
    pub fn reserve_application_comparison(
        &mut self,
        source: &BrowserApplicationSource,
        visits: usize,
        bytes: usize,
        checks: usize,
    ) -> Result<(), BrowserInputError> {
        self.validate_application_source(source)?;
        use crate::workbench::model_originals::workflow::observation_check::CompareResource;
        let (_, _, owner) = self.inner.physical_owners()?;
        owner
            .charge(CompareResource::StructuralVisits, visits)
            .map_err(inputs::BrowserInputFault::Comparison)?;
        owner
            .charge(CompareResource::ComparisonBytes, bytes)
            .map_err(inputs::BrowserInputFault::Comparison)?;
        owner
            .charge(CompareResource::Checks, checks)
            .map_err(inputs::BrowserInputFault::Comparison)?;
        Ok(())
    }
    pub fn prepare_application_read(
        &mut self,
        source: &BrowserApplicationSource,
        requested: usize,
    ) -> Result<BrowserApplicationRead<'_>, BrowserInputError> {
        self.validate_application_source(source)?;
        let (_, receiving, _) = self.inner.physical_owners()?;
        receiving
            .prepare_snapshot_read(requested)
            .map(|inner| BrowserApplicationRead { inner })
            .map_err(|fault| inputs::BrowserInputFault::Receiving(*fault).into())
    }
    /// Latch a failed application preparation. The caller retains its typed cause.
    pub fn refuse_application(
        &mut self,
        source: &BrowserApplicationSource,
    ) -> Result<(), BrowserInputError> {
        self.validate_application_source(source)?;
        let (_, receiving, _) = self.inner.physical_owners()?;
        Err(inputs::BrowserInputFault::Receiving(
            *receiving
                .fail(super::super::installed::observation::InstalledObservationFault::PriorFault),
        )
        .into())
    }
    /// Consume existing cumulative permissions for the concrete controlled host's
    /// own requested backing. This issues no source, task or physical permission.
    pub fn reserve_controlled_host_storage(
        &mut self,
        bytes: usize,
        slots: usize,
        initialized: usize,
    ) -> Result<(), BrowserInputError> {
        self.ready()?;
        use crate::workbench::model_originals::workflow::pipeline::installed::observation::InstalledObservationResource as Resource;
        let (decode, receiving, _) = self.inner.physical_owners()?;
        decode
            .slots(slots)
            .map_err(inputs::BrowserInputFault::Decode)?;
        receiving
            .reserve_span(Resource::RetainedBytes, bytes)
            .map_err(inputs::BrowserInputFault::Receiving)?;
        decode
            .bytes(initialized)
            .map_err(inputs::BrowserInputFault::Decode)?;
        receiving
            .reserve_span(Resource::ByteVisits, initialized)
            .map_err(inputs::BrowserInputFault::Receiving)?;
        Ok(())
    }
    fn ready_for(&self, scope: &BrowserSourceScope) -> Result<(), BrowserInputError> {
        self.ready()?;
        if !matches!(self.relation, LoanRelation::Application(global) if std::ptr::eq(global, scope))
        {
            return Err(
                inputs::BrowserInputFault::Source(BrowserSourceFault::ForeignSource).into(),
            );
        }
        scope
            .ready()
            .map_err(|fault| inputs::BrowserInputFault::Source(fault).into())
    }
}
pub fn with_prepared_browser_clients<R, E>(
    corpus: &Corpus,
    configuration: &RunConfiguration,
    action: impl FnOnce(BrowserClients<'_>, &mut BrowserLoans<'_, '_>) -> Result<R, E>,
) -> Result<BrowserCallbackOutcome<R, E>, BrowserPreparationError> {
    if !matches!(configuration.mode, Configuration::BrowserOriginals { .. }) {
        return Err(BrowserPreparationError {
            cause: PreparationCause::WrongConfiguration,
        });
    }
    let CorpusStorage::ModelOriginals(source) = &corpus.storage else {
        return Err(BrowserPreparationError {
            cause: PreparationCause::WrongCorpus,
        });
    };
    prepared_browser_originals(source, configuration, |inner, loans| {
        let mut scope = BrowserSourceScope::prepare(loans)?;
        let result = action(
            BrowserClients {
                inner,
                scope: &scope,
            },
            &mut BrowserLoans {
                inner: loans,
                relation: LoanRelation::Application(&scope),
            },
        );
        let source = scope.revoke();
        Ok(BrowserCallbackOutcome { result, source })
    })
    .map_err(|cause| BrowserPreparationError {
        cause: PreparationCause::Prepared(cause),
    })
}
impl BrowserClients<'_> {
    /// Descriptive selected source inventory, never an effect grant.
    pub fn case_count(&self) -> usize {
        self.inner.case_count()
    }
    pub fn visit<E>(
        &self,
        loans: &mut BrowserLoans<'_, '_>,
        mut visit: impl FnMut(BrowserClient<'_>, &mut BrowserLoans<'_, '_>) -> Result<(), E>,
    ) -> Result<(), BrowserVisitError<E>> {
        loans
            .ready_for(self.scope)
            .map_err(BrowserVisitError::Input)?;
        self.inner
            .try_visit_clients(loans.inner, |inner, loans| {
                visit(
                    BrowserClient {
                        inner,
                        scope: self.scope,
                    },
                    &mut BrowserLoans {
                        inner: loans,
                        relation: LoanRelation::Application(self.scope),
                    },
                )
            })
            .map_err(|fault| match fault {
                inputs::ClientVisitFault::Input(fault) => BrowserVisitError::Input(fault.into()),
                inputs::ClientVisitFault::Callback(fault) => BrowserVisitError::Callback(fault),
            })
    }
}
#[derive(Debug, Clone, Copy)]
pub struct BrowserSourceIdentity<'a> {
    pub provider_id: &'a str,
    pub locator: &'a str,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserScope {
    Primary,
    Complete,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserSemantic {
    None,
    Projection,
}
#[derive(Debug, Clone, Copy)]
pub enum BrowserDownloadTarget<'a> {
    RetainedFile,
    InventoryPath(&'a str),
}
#[derive(Debug, Clone, Copy)]
pub enum BrowserActionKind<'a> {
    BeginConnectedOpening {
        attempt: &'a str,
        pending: &'a str,
        project_id: &'a str,
        scope: BrowserScope,
        semantic: BrowserSemantic,
        source: BrowserSourceIdentity<'a>,
        inventory_max_entries: u64,
        read_max_bytes: u64,
    },
    StartConnected {
        attempt: &'a str,
        project_id: &'a str,
        scope: BrowserScope,
        semantic: BrowserSemantic,
        source: BrowserSourceIdentity<'a>,
    },
    BindModelOwner {
        attempt: &'a str,
        model: &'a str,
    },
    DownloadOriginal {
        model: &'a str,
        target: BrowserDownloadTarget<'a>,
    },
    DownloadArchive {
        model: &'a str,
    },
    CloseModel {
        model: &'a str,
    },
    CloseCurrentModel,
    Checkpoint {
        name: &'a str,
    },
    Unsupported,
}
pub struct BrowserAction<'a> {
    position: usize,
    kind: BrowserActionKind<'a>,
}
impl<'a> BrowserAction<'a> {
    pub fn position(&self) -> usize {
        self.position
    }
    pub fn kind(&self) -> BrowserActionKind<'a> {
        self.kind
    }
}
impl BrowserClient<'_> {
    pub fn prepare_controlled_host(
        &self,
        loans: &mut BrowserLoans<'_, '_>,
        opening_action_position: usize,
    ) -> Result<ControlledHostStimulus, BrowserInputError> {
        loans.ready_for(self.scope)?;
        ControlledHostStimulus::prepare(
            &self.inner,
            loans.inner,
            self.scope,
            opening_action_position,
        )
        .map_err(Into::into)
    }
    pub fn case_index(&self) -> usize {
        self.inner.case_index()
    }
    pub fn run_index(&self) -> usize {
        self.inner.run_index()
    }
    pub fn actions<'a>(
        &'a self,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<impl ExactSizeIterator<Item = BrowserAction<'a>> + use<'a>, BrowserInputError> {
        loans.ready_for(self.scope)?;
        self.inner
            .actions(loans.inner)
            .map(|actions| {
                actions.map(|action| {
                    use inputs::BrowserActionKind as Input;
                    let kind = match action.kind() {
                        Input::BeginConnectedOpening {
                            attempt,
                            pending,
                            project_id,
                            scope,
                            semantic,
                            source,
                            transfer_limits,
                        } => BrowserActionKind::BeginConnectedOpening {
                            attempt: attempt.as_str(),
                            pending: pending.as_str(),
                            project_id: project_id.as_str(),
                            scope: match scope {
                                input::ClientActionBeginConnectedOpeningScope::Primary => {
                                    BrowserScope::Primary
                                }
                                input::ClientActionBeginConnectedOpeningScope::Complete => {
                                    BrowserScope::Complete
                                }
                            },
                            semantic: match semantic {
                                input::ClientActionBeginConnectedOpeningSemantic::None => {
                                    BrowserSemantic::None
                                }
                                input::ClientActionBeginConnectedOpeningSemantic::Projection => {
                                    BrowserSemantic::Projection
                                }
                            },
                            source: BrowserSourceIdentity {
                                provider_id: source.provider_id.as_str(),
                                locator: source.locator.as_str(),
                            },
                            inventory_max_entries: transfer_limits.inventory_max_entries.0,
                            read_max_bytes: transfer_limits.read_max_bytes.0,
                        },
                        Input::StartConnected {
                            attempt,
                            project_id,
                            scope,
                            semantic,
                            source,
                        } => BrowserActionKind::StartConnected {
                            attempt: attempt.as_str(),
                            project_id: project_id.as_str(),
                            scope: match scope {
                                input::ClientActionStartConnectedScope::Primary => {
                                    BrowserScope::Primary
                                }
                                input::ClientActionStartConnectedScope::Complete => {
                                    BrowserScope::Complete
                                }
                            },
                            semantic: match semantic {
                                input::ClientActionStartConnectedSemantic::None => {
                                    BrowserSemantic::None
                                }
                                input::ClientActionStartConnectedSemantic::Projection => {
                                    BrowserSemantic::Projection
                                }
                            },
                            source: BrowserSourceIdentity {
                                provider_id: source.provider_id.as_str(),
                                locator: source.locator.as_str(),
                            },
                        },
                        Input::BindModelOwner { attempt, model } => {
                            BrowserActionKind::BindModelOwner {
                                attempt: attempt.as_str(),
                                model: model.as_str(),
                            }
                        }
                        Input::DownloadOriginal { model, target } => {
                            BrowserActionKind::DownloadOriginal {
                                model: model.as_str(),
                                target: match target {
                                    input::ClientActionDownloadOriginalTarget::RetainedFile {} => {
                                        BrowserDownloadTarget::RetainedFile
                                    }
                                    input::ClientActionDownloadOriginalTarget::InventoryPath {
                                        path,
                                    } => BrowserDownloadTarget::InventoryPath(path.as_str()),
                                },
                            }
                        }
                        Input::DownloadArchive { model } => BrowserActionKind::DownloadArchive {
                            model: model.as_str(),
                        },
                        Input::CloseModel { model } => BrowserActionKind::CloseModel {
                            model: model.as_str(),
                        },
                        Input::CloseCurrentModel => BrowserActionKind::CloseCurrentModel,
                        Input::Checkpoint { name } => BrowserActionKind::Checkpoint {
                            name: name.as_str(),
                        },
                        Input::Unsupported => BrowserActionKind::Unsupported,
                    };
                    BrowserAction {
                        position: action.position(),
                        kind,
                    }
                })
            })
            .map_err(Into::into)
    }
}
