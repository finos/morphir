//! Canonical prepared inventory execution. No selected public dispatch or verdict.
use super::super::{PreparationFault, Source, policy::Policy, prepared_typed};
use super::{
    adapter::{
        BrowserInputError, BrowserLoans, BrowserPreparationErrorKind, BrowserSourceTerminal,
        execution_loans::{
            BrowserActionCursorTerminal, BrowserActionIssueError,
            BrowserConnectedOperationsSnapshot, ExecutionChild, PreparedBrowserClientRun,
            SourceOperationJournal,
        },
    },
    collection::{
        BrowserCollectionTerminal, BrowserDocumentBounds, BrowserIssuedHostsTerminal,
        BrowserRowCollection, BrowserRowProducer,
    },
    inputs::BrowserOwnerLoans,
    source_scope::BrowserSourceScope,
};
use crate::workbench::{
    Corpus, RunConfiguration,
    configuration::{
        BrowserClient as ConfiguredBrowserClient, Configuration, InstalledObservationLimits,
    },
    corpus::CorpusStorage,
    model_originals::workflow::{
        pairing::PairedRun,
        pipeline::installed::observation::{
            InstalledObservationFault, InstalledObservationOwner, InstalledObservationResource,
        },
        reviewed_sources::ReviewedSources,
        source_compile::{CompiledExecution, WorkflowReportContext},
    },
};
use std::{
    alloc::Layout,
    any::Any,
    mem::size_of,
    panic::{AssertUnwindSafe, catch_unwind},
};

#[derive(Debug)]
enum BrowserExecutionPreparationCause {
    WrongConfiguration,
    WrongCorpus,
    Preparation(PreparationFault<BrowserInputError>),
}
#[derive(Debug)]
pub struct BrowserExecutionPreparationError {
    cause: BrowserExecutionPreparationCause,
}
impl BrowserExecutionPreparationError {
    pub fn kind(&self) -> BrowserPreparationErrorKind {
        use BrowserPreparationErrorKind as Kind;
        match &self.cause {
            BrowserExecutionPreparationCause::WrongConfiguration => Kind::WrongConfiguration,
            BrowserExecutionPreparationCause::WrongCorpus => Kind::WrongCorpus,
            BrowserExecutionPreparationCause::Preparation(fault) => match fault {
                PreparationFault::Ingress(_) => Kind::Ingress,
                PreparationFault::InventoryWork(_) => Kind::InventoryWork,
                PreparationFault::InventoryAllocation(_) => Kind::InventoryAllocation,
                PreparationFault::Anchors(_) => Kind::Anchors,
                PreparationFault::Compilation(_) => Kind::Compilation,
                PreparationFault::Callback(_) => Kind::Input,
            },
        }
    }
}

/// Controlled-source execution and retained DATA collection only. This neither
/// enables the public CLI mode nor supplies physical completion or qualification.
/// The adapter receives no compiler context, expected values or verdict setter.
pub fn with_executed_browser_originals<R, E>(
    corpus: &Corpus,
    configuration: &RunConfiguration,
    bounds: BrowserDocumentBounds,
    adapter: impl FnMut(
        &PreparedBrowserClientRun<'_, '_, '_, '_, '_, '_>,
        &mut BrowserLoans<'_, '_>,
        &mut BrowserRowProducer<'_>,
    ) -> Result<(), E>,
    inspect: impl FnOnce(&BrowserExecutionInventory<'_, '_, '_, '_, '_, E>) -> R,
) -> Result<R, BrowserExecutionPreparationError> {
    let Configuration::BrowserOriginals {
        checker,
        receiving,
        client: ConfiguredBrowserClient::Chromium,
    } = &configuration.mode
    else {
        return Err(BrowserExecutionPreparationError {
            cause: BrowserExecutionPreparationCause::WrongConfiguration,
        });
    };
    let CorpusStorage::ModelOriginals(source) = &corpus.storage else {
        return Err(BrowserExecutionPreparationError {
            cause: BrowserExecutionPreparationCause::WrongCorpus,
        });
    };
    with_prepared_browser_execution(
        source,
        checker,
        receiving,
        bounds,
        adapter,
        |inventory, _loans| inspect(inventory),
    )
    .map_err(|cause| BrowserExecutionPreparationError {
        cause: BrowserExecutionPreparationCause::Preparation(cause),
    })
}

/// The adapter's real return or original unwind payload, never a verdict.
pub enum BrowserAdapterCompletion<E> {
    Returned(Result<(), E>),
    Panicked(Box<dyn Any + Send>),
}
pub enum BrowserRowSetupFailure {
    Input(BrowserInputError),
    UnsupportedRole,
}
pub struct BrowserRowAttempt<E> {
    callback: BrowserAdapterCompletion<E>,
    child: BrowserSourceTerminal,
    owner_failure: Option<BrowserInputError>,
    issued_hosts: BrowserIssuedHostsTerminal,
    actions: BrowserActionCursorTerminal,
    connected_operations: BrowserConnectedOperationsSnapshot,
    first_action_issue: Option<BrowserActionIssueError>,
    collection: BrowserRowCollection,
}
impl<E> BrowserRowAttempt<E> {
    pub fn callback(&self) -> &BrowserAdapterCompletion<E> {
        &self.callback
    }
    pub fn child_terminal(&self) -> BrowserSourceTerminal {
        self.child
    }
    pub fn owner_failure(&self) -> Option<&BrowserInputError> {
        self.owner_failure.as_ref()
    }
    pub fn collection(&self) -> &BrowserRowCollection {
        &self.collection
    }
    /// Captured at the actual callback/revocation boundary. Later DATA-only
    /// completion may enrich the journal but cannot heal this earlier outcome.
    pub fn issued_hosts_terminal(&self) -> BrowserIssuedHostsTerminal {
        self.issued_hosts
    }
    /// Immutable source progression captured before the callback's run drops.
    /// This is independent of actual driver or physical operation completion.
    pub fn actions_terminal(&self) -> BrowserActionCursorTerminal {
        self.actions
    }
    pub fn connected_operations(&self) -> BrowserConnectedOperationsSnapshot {
        self.connected_operations
    }
    pub fn first_action_issue(&self) -> Option<&BrowserActionIssueError> {
        self.first_action_issue.as_ref()
    }
    pub fn collection_complete(&self) -> bool {
        matches!(
            self.collection.terminal(),
            BrowserCollectionTerminal::AllDocumentsEnded { documents, .. } if documents > 0
        )
    }
    fn failed(&self) -> bool {
        !matches!(self.callback, BrowserAdapterCompletion::Returned(Ok(())))
            || self.child != BrowserSourceTerminal::Quiescent
            || self.owner_failure.is_some()
            || !matches!(
                self.actions,
                BrowserActionCursorTerminal::FullSourceActionsConsumed { .. }
            )
            || matches!(
                self.issued_hosts,
                BrowserIssuedHostsTerminal::Incomplete { .. }
            )
            || !self.collection_complete()
    }
}
pub enum BrowserRowState<E> {
    SetupFailed {
        cause: BrowserRowSetupFailure,
        child: Option<BrowserSourceTerminal>,
    },
    Attempted(BrowserRowAttempt<E>),
    NotAttempted {
        prior_failure_row: usize,
    },
}
pub struct BrowserExecutionRow<'compiled, 'case, 'sources, 'raw, 'supplied, E> {
    compiled: &'compiled CompiledExecution<'case, 'sources, 'raw, 'supplied>,
    state: BrowserRowState<E>,
}
impl<'case, 'sources, 'raw, 'supplied, E>
    BrowserExecutionRow<'_, 'case, 'sources, 'raw, 'supplied, E>
{
    pub fn case_id(&self) -> &str {
        self.compiled.case().id()
    }
    pub fn run_index(&self) -> usize {
        self.compiled.run_index()
    }
    pub(super) fn context(
        &self,
    ) -> Option<WorkflowReportContext<'_, 'case, 'sources, 'raw, 'supplied>> {
        match self.compiled {
            CompiledExecution::Current(core) => Some(core.report_context()),
            CompiledExecution::Native(_) => None,
        }
    }
    pub fn attempt(&self) -> Option<&BrowserRowAttempt<E>> {
        match &self.state {
            BrowserRowState::Attempted(attempt) => Some(attempt),
            _ => None,
        }
    }
    pub fn state(&self) -> &BrowserRowState<E> {
        &self.state
    }
    pub fn not_attempted_after(&self) -> Option<usize> {
        match self.state {
            BrowserRowState::NotAttempted { prior_failure_row } => Some(prior_failure_row),
            _ => None,
        }
    }
}
pub struct BrowserExecutionInventory<'compiled, 'case, 'sources, 'raw, 'supplied, E> {
    rows: Vec<BrowserExecutionRow<'compiled, 'case, 'sources, 'raw, 'supplied, E>>,
    first_failed_row: Option<usize>,
    global: BrowserSourceTerminal,
}
impl<'compiled, 'case, 'sources, 'raw, 'supplied, E>
    BrowserExecutionInventory<'compiled, 'case, 'sources, 'raw, 'supplied, E>
{
    pub fn rows(&self) -> &[BrowserExecutionRow<'compiled, 'case, 'sources, 'raw, 'supplied, E>] {
        &self.rows
    }
    pub fn first_failed_row(&self) -> Option<usize> {
        self.first_failed_row
    }
    pub fn source_terminal(&self) -> BrowserSourceTerminal {
        self.global
    }
}
fn failure(
    loans: &mut BrowserOwnerLoans<'_>,
    cause: InstalledObservationFault,
) -> BrowserInputError {
    match loans.physical_owners() {
        Ok((_, receiving, _)) => {
            super::inputs::BrowserInputFault::Receiving(*receiving.fail(cause)).into()
        }
        Err(first) => first.into(),
    }
}
fn reserve_rows<'compiled, 'case, 'sources, 'raw, 'supplied, E>(
    count: usize,
    global: &BrowserSourceScope,
    loans: &mut BrowserOwnerLoans<'_>,
) -> Result<
    Vec<BrowserExecutionRow<'compiled, 'case, 'sources, 'raw, 'supplied, E>>,
    BrowserInputError,
> {
    loans.ready()?;
    global
        .ready()
        .map_err(super::inputs::BrowserInputFault::Source)?;
    let requested =
        Layout::array::<BrowserExecutionRow<'compiled, 'case, 'sources, 'raw, 'supplied, E>>(count)
            .ok()
            .and_then(|layout| {
                layout.size().checked_add(size_of::<
                    BrowserExecutionInventory<'compiled, 'case, 'sources, 'raw, 'supplied, E>,
                >())
            })
            .ok_or_else(|| failure(loans, InstalledObservationFault::SizeOverflow))?;
    let slots = count
        .checked_add(1)
        .ok_or_else(|| failure(loans, InstalledObservationFault::SizeOverflow))?;
    fn reserve(
        loans: &mut BrowserOwnerLoans<'_>,
        bytes: usize,
        slots: usize,
    ) -> Result<(), BrowserInputError> {
        let (decode, receiving, _) = loans.physical_owners()?;
        decode
            .slots(slots)
            .map_err(super::inputs::BrowserInputFault::Decode)?;
        receiving
            .reserve_span(InstalledObservationResource::RetainedBytes, bytes)
            .map_err(super::inputs::BrowserInputFault::Receiving)?;
        decode
            .bytes(bytes)
            .map_err(super::inputs::BrowserInputFault::Decode)?;
        receiving
            .reserve_span(InstalledObservationResource::ByteVisits, bytes)
            .map_err(super::inputs::BrowserInputFault::Receiving)?;
        Ok(())
    }
    // The complete outcome inventory is funded before any adapter can run.
    reserve(loans, requested, slots)?;
    let mut rows = Vec::new();
    rows.try_reserve_exact(count)
        .map_err(|_| failure(loans, InstalledObservationFault::Allocation))?;
    let excess = rows
        .capacity()
        .checked_sub(count)
        .and_then(|count| {
            count.checked_mul(size_of::<
                BrowserExecutionRow<'compiled, 'case, 'sources, 'raw, 'supplied, E>,
            >())
        })
        .ok_or_else(|| failure(loans, InstalledObservationFault::LayoutMismatch))?;
    reserve(loans, excess, 0)?;
    Ok(rows)
}
fn invoke_client<E>(
    core: &crate::workbench::model_originals::workflow::source_compile::CompiledSourceCase<
        '_,
        '_,
        '_,
        '_,
    >,
    global: &BrowserSourceScope,
    child: &ExecutionChild,
    loans: &mut BrowserOwnerLoans<'_>,
    bounds: BrowserDocumentBounds,
    adapter: &mut impl FnMut(
        &PreparedBrowserClientRun<'_, '_, '_, '_, '_, '_>,
        &mut BrowserLoans<'_, '_>,
        &mut BrowserRowProducer<'_>,
    ) -> Result<(), E>,
) -> Result<
    (
        BrowserAdapterCompletion<E>,
        BrowserRowCollection,
        BrowserActionCursorTerminal,
        SourceOperationJournal,
        Option<BrowserActionIssueError>,
    ),
    BrowserInputError,
> {
    let run = PreparedBrowserClientRun::prepare(core, global, child, loans)?;
    let mut execution_loans = BrowserLoans::execution(loans, global, child)?;
    let mut collection = BrowserRowCollection::prepare(&run, &mut execution_loans, bounds)?;
    let result = catch_unwind(AssertUnwindSafe(|| {
        let mut producer = collection.producer();
        adapter(&run, &mut execution_loans, &mut producer)
    }));
    // Borrowed tokens cannot escape this callback/run lifetime. Record its
    // closed state now, including a forgotten or dropped outstanding operand;
    // destroying the run must not erase an ignored refusal.
    let (actions, operations, first_action_issue) = run.into_action_capture();
    // Keep actual error/panic ownership; no payload is copied or normalized.
    let completion = match result {
        Ok(result) => BrowserAdapterCompletion::Returned(result),
        Err(original) => BrowserAdapterCompletion::Panicked(original),
    };
    Ok((
        completion,
        collection,
        actions,
        operations,
        first_action_issue,
    ))
}
/// Sole preparation owns all compiled rows and report contexts through inspection.
/// The adapter receives only source-selected inputs and an issued producer loan.
/// This private entry does not open the unavailable public browser mode.
pub(super) fn with_prepared_browser_execution<R, E>(
    source: &Source,
    policy: &Policy,
    receiving: &InstalledObservationLimits,
    bounds: BrowserDocumentBounds,
    mut adapter: impl FnMut(
        &PreparedBrowserClientRun<'_, '_, '_, '_, '_, '_>,
        &mut BrowserLoans<'_, '_>,
        &mut BrowserRowProducer<'_>,
    ) -> Result<(), E>,
    inspect: impl FnOnce(
        &BrowserExecutionInventory<'_, '_, '_, '_, '_, E>,
        &mut BrowserOwnerLoans<'_>,
    ) -> R,
) -> Result<R, PreparationFault<BrowserInputError>> {
    let mut receiving = InstalledObservationOwner::new(receiving);
    prepared_typed(
        source,
        policy,
        ReviewedSources::selected(),
        |compiled, owners| {
            let mut loans = BrowserOwnerLoans::new(owners, &mut receiving);
            let mut global = BrowserSourceScope::prepare(&mut loans)?;
            let mut rows = reserve_rows(compiled.len(), &global, &mut loans)?;
            let mut first_failed_row = None;
            for (index, compiled) in compiled.iter().enumerate() {
                let state = if let Some(prior_failure_row) = first_failed_row {
                    // No new source/task/allocation work after the first failed row.
                    BrowserRowState::NotAttempted { prior_failure_row }
                } else {
                    match ExecutionChild::prepare(&global, &mut loans) {
                        Err(cause) => BrowserRowState::SetupFailed {
                            cause: BrowserRowSetupFailure::Input(cause),
                            child: None,
                        },
                        Ok(mut child) => {
                            let result = match compiled {
                                CompiledExecution::Current(core)
                                    if matches!(
                                        core.source().paired().run(),
                                        PairedRun::Client { .. }
                                    ) =>
                                {
                                    invoke_client(
                                        core,
                                        &global,
                                        &child,
                                        &mut loans,
                                        bounds,
                                        &mut adapter,
                                    )
                                    .map_err(BrowserRowSetupFailure::Input)
                                }
                                CompiledExecution::Current(_) | CompiledExecution::Native(_) => {
                                    Err(BrowserRowSetupFailure::UnsupportedRole)
                                }
                            };
                            // Cut retained host DATA under SAME parent→child
                            // source locks, then revoke before those gates can
                            // reopen. Late pending outcomes may still append
                            // DATA, but cannot enter this immutable attempt cut.
                            let ((issued_hosts, connected_operations), terminal) = child
                                .revoke_with_capture(|| match &result {
                                    Ok((_, collection, _, operations, _)) => {
                                        (collection.issued_hosts_terminal(), operations.snapshot())
                                    }
                                    Err(_) => (
                                        BrowserIssuedHostsTerminal::NoneIssued,
                                        BrowserConnectedOperationsSnapshot::not_requested(),
                                    ),
                                });
                            match result {
                                Ok((
                                    callback,
                                    collection,
                                    actions,
                                    _operations,
                                    first_action_issue,
                                )) => {
                                    // Check cumulative owners independently of
                                    // the now-revoked child. An ignored refusal
                                    // belongs to this actual callback, including
                                    // the final row, rather than next-row setup.
                                    let owner_failure = loans.ready().err().map(Into::into);
                                    BrowserRowState::Attempted(BrowserRowAttempt {
                                        callback,
                                        child: terminal,
                                        owner_failure,
                                        issued_hosts,
                                        actions,
                                        connected_operations,
                                        first_action_issue,
                                        collection,
                                    })
                                }
                                Err(cause) => BrowserRowState::SetupFailed {
                                    cause,
                                    child: Some(terminal),
                                },
                            }
                        }
                    }
                };
                let failed = match &state {
                    BrowserRowState::SetupFailed { .. } => true,
                    BrowserRowState::Attempted(attempt) => attempt.failed(),
                    BrowserRowState::NotAttempted { .. } => false,
                };
                if failed && first_failed_row.is_none() {
                    first_failed_row = Some(index);
                }
                rows.push(BrowserExecutionRow { compiled, state });
            }
            let global = global.revoke();
            let inventory = BrowserExecutionInventory {
                rows,
                first_failed_row,
                global,
            };
            Ok(inspect(&inventory, &mut loans))
        },
    )
}

#[cfg(test)]
#[path = "execution/tests.rs"]
mod tests;
