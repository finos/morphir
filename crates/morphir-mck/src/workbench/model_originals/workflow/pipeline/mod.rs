//! One selected branch of the existing Workbench pipeline. The fixed reviewed
//! source bundle is PARTIAL. No semantic lineage/runtime qualification is issued.
pub use browser::{
    BrowserActionCursorFault, BrowserActionCursorTerminal, BrowserActionIssueError,
    BrowserConnectedControlFault, BrowserConnectedJournalFault, BrowserConnectedOpening,
    BrowserConnectedOperationObservation, BrowserConnectedOperationsSnapshot,
    BrowserConnectedPreparationFailure, BrowserControllerDispatch, BrowserControllerPreparation,
    BrowserControllerStepDispatcher, BrowserExecutionAction, BrowserInspectionBoundarySource,
    BrowserInspectionPendingReply, BrowserListenerDispatch, BrowserListenerStartDispatcher,
    BrowserOpeningSelectionReply, BrowserOwnedConnectedOpening, BrowserOwnedInspectionBoundary,
    BrowserPreparedControllerStep, BrowserPreparedListenerStart, BrowserSourcePumpGuardWork,
};
pub use browser::{
    BrowserConnectedBoundary, BrowserEffectKind, BrowserEffectRef, BrowserUnsupportedActionKind,
};
pub use browser::{
    BrowserHostFact, BrowserHostInterruption, BrowserHostIoFailure, BrowserHostManifestFailure,
    BrowserHostPeerFinish, BrowserHostPollState, BrowserHostReadOutcome, BrowserHostReadPending,
    BrowserHostReadResult, BrowserHostSendOutcome, BrowserHostTranscript,
    BrowserHostTranscriptFault, BrowserHostTranscriptPrepareError, BrowserHostTranscriptRecord,
    BrowserHostTranscriptSnapshot, BrowserHostTranscriptTerminal, BrowserIssuedHostsTerminal,
    BrowserManifestPending, BrowserReplyPending,
};
mod browser;
pub use browser::{
    BrowserAction, BrowserActionKind, BrowserApplicationRead, BrowserApplicationSource,
    BrowserCallbackOutcome, BrowserClient, BrowserClients, BrowserDocumentDecoder,
    BrowserDocumentError, BrowserDocumentErrorKind, BrowserDownloadTarget, BrowserInputError,
    BrowserLoans, BrowserPreparationError, BrowserPreparationErrorKind, BrowserScope,
    BrowserSemantic, BrowserSourceFault, BrowserSourceIdentity, BrowserSourceTerminal,
    BrowserVisitError, with_prepared_browser_clients,
};
pub use browser::{
    BrowserAdapterCompletion, BrowserExecutionInventory, BrowserExecutionPreparationError,
    BrowserExecutionRow, BrowserRowAttempt, BrowserRowSetupFailure, BrowserRowState,
    with_executed_browser_originals,
};
pub use browser::{
    BrowserArchiveData, BrowserDocumentContent, BrowserDocumentFactData, BrowserDocumentFrameData,
    BrowserDownloadOutcomeData, BrowserDownloadResultData, BrowserInventoryData,
    BrowserJsonStringSpan, BrowserOpeningData, BrowserProjectSelectionData,
    BrowserReadyArchiveData, BrowserSourceSelectionData, BrowserVisitData,
};
pub use browser::{
    BrowserCollectionFault, BrowserCollectionTerminal, BrowserDocumentBounds,
    BrowserDocumentProducer, BrowserDocumentRecord, BrowserDocumentSnapshot,
    BrowserExecutionOpening, BrowserRetainedDocumentFrame, BrowserRowCollection,
    BrowserRowProducer, PreparedBrowserClientRun,
};
pub use browser::{
    ControlledDeliveryFault, ControlledHostDelivery, ControlledHostStimulus,
    ControlledManifestDelivery, ControlledOpening, ControlledPeerDelivery,
};
mod clock;
pub(super) mod installed;
pub(in crate::workbench) mod policy;
mod raw;
mod report_revision;
mod wire;
use super::ingress::BoundCorpus;
use super::observation_check::ObservationError;
use super::reviewed_sources::ReviewedSources;
use super::source_compile::{
    CaseCompiler, CompilationError, CompiledExecution, WorkflowRecordError,
};
use super::source_proof::{SourceError, SourceVerifier};
use super::{DecodeError, Decoder, Fields, string};
use crate::json::strict::Document;
use crate::transport::{Session, TransportError};
use crate::workbench::corpus::CorpusSource;
use crate::workbench::report::{MAX_REPORT_BYTES, WorkflowExchangeRecord};
#[cfg(test)]
use installed::prepared_installed_client;
pub(in crate::workbench) use installed::{execute_installed, replay_installed};
pub(in crate::workbench) use policy::Policy;
use policy::{CaptureFault, Owners};
use raw::VERSION;
pub(in crate::workbench) use raw::{StoredReport, recognizes, recognizes_report};
use serde::Serialize;
use serde_json::value::RawValue;
use wire::{
    Capabilities, Evidence, ExecutionRef, FailureSummary, Role, RuntimeRecord, RuntimeReport,
    Verdict,
};

pub(in crate::workbench) const MISSING_POLICY: &str =
    "model-originals requires explicit checker policy";
#[derive(Debug, Clone)]
struct CorpusFileDigest(String);
#[derive(Debug, Clone)]
pub(in crate::workbench) struct Source {
    raw: CorpusSource,
    digest: CorpusFileDigest,
    count: usize,
}
impl Source {
    pub(in crate::workbench) fn new(raw: CorpusSource) -> Result<Self, String> {
        let count = raw::corpus_count(raw.text())?;
        if count == 0 {
            return Err("corpus inventory is empty".into());
        }
        let digest = CorpusFileDigest(crate::kit::hash::sha256_hex(raw.bytes()));
        Ok(Self { raw, digest, count })
    }
    pub(in crate::workbench) fn case_count(&self) -> usize {
        self.count
    }
    pub(in crate::workbench) fn digest(&self) -> &str {
        &self.digest.0
    }
}

// Phase-specific owned causes; only the existing outer wrapper renders strings.
#[derive(Debug)]
enum PreparationFault<E> {
    Ingress(super::ingress::IngressError),
    InventoryWork(DecodeError),
    InventoryAllocation(std::collections::TryReserveError),
    Anchors(SourceError),
    Compilation(CompilationError),
    Callback(E),
}
// Preparation locals own every operand and compiled view for the whole action.
// No self-reference or compiler/context borrow can escape the owned result R.
fn prepared_typed<R, E>(
    source: &Source,
    policy: &Policy,
    sources: ReviewedSources<'_>,
    action: impl FnOnce(&[CompiledExecution<'_, '_, '_, '_>], &mut Owners) -> Result<R, E>,
) -> Result<R, PreparationFault<E>> {
    let mut owners = policy.owners();
    let bound = BoundCorpus::decode_selected(source.raw.text(), &mut owners.decode)
        .map_err(PreparationFault::Ingress)?;
    owners
        .decode
        .slots(bound.cases().len())
        .map_err(PreparationFault::InventoryWork)?;
    let mut compiled = Vec::new();
    compiled
        .try_reserve_exact(bound.cases().len())
        .map_err(PreparationFault::InventoryAllocation)?;
    let verifier =
        SourceVerifier::new(&sources, &mut owners.decode).map_err(PreparationFault::Anchors)?;
    let mut compiler = CaseCompiler::new(verifier, &mut owners.closure, &mut owners.expansion);
    for case in bound.cases() {
        match compiler.compile_execution(case) {
            Ok(value) => compiled.push(value),
            Err(_) => {
                return Err(PreparationFault::Compilation(
                    compiler
                        .into_fault()
                        .expect("failed compiler retains its cause"),
                ));
            }
        }
    }
    if compiler.require_inventory(bound.cases()).is_err() {
        return Err(PreparationFault::Compilation(
            compiler
                .into_fault()
                .expect("failed inventory retains its cause"),
        ));
    }
    drop(compiler);
    action(&compiled, &mut owners).map_err(PreparationFault::Callback)
}
fn prepared<R>(
    source: &Source,
    policy: &Policy,
    sources: ReviewedSources<'_>,
    action: impl FnOnce(&[CompiledExecution<'_, '_, '_, '_>], &mut Owners) -> Result<R, String>,
) -> Result<R, String> {
    prepared_typed(source, policy, sources, action).map_err(|error| match error {
        PreparationFault::Ingress(_) => "source corpus decode refused".to_owned(),
        PreparationFault::InventoryWork(_) => "source prepared inventory work refused".to_owned(),
        PreparationFault::InventoryAllocation(_) => {
            "source prepared inventory allocation refused".to_owned()
        }
        PreparationFault::Anchors(_) => "source anchors refused".to_owned(),
        PreparationFault::Compilation(error) => compilation_message(&error),
        PreparationFault::Callback(error) => error,
    })
}
fn compilation_message(error: &CompilationError) -> String {
    match error {
        CompilationError::Source(SourceError::Inventory) => {
            "inventory differs from complete ordered reviewed subset"
        }
        CompilationError::Source(_) => "source correspondence refused",
        CompilationError::Closure(_) => "source closure refused",
        CompilationError::Expansion(_) => "source expansion refused",
        CompilationError::IdentityInput(_) => "source identity input refused",
    }
    .to_owned()
}

#[derive(Debug)]
enum RunFault {
    Decode(DecodeError),
    Capabilities(DecodeError),
    UnsupportedRole,
    Exchange(TransportError),
    Capture(CaptureFault),
    Record(WorkflowRecordError),
    Native(super::native::NativeAdapterError),
    RecordRetention(super::native::PrivateRecordError),
    Installed(installed::adapter::InstalledAdapterError),
    InstalledObservation(installed::observation::InstalledObservationFault),
    InstalledProcessFault(crate::transport::process::ProcessFault),
    InstalledConsumer(installed::adapter::processes::ConsumerCodecError),
}
impl RunFault {
    fn summary(&self) -> FailureSummary {
        let (phase, code, message) = match self {
            Self::InstalledConsumer(error) => {
                return FailureSummary::consumer(error.failure_kind());
            }
            Self::InstalledProcessFault(error) => {
                use crate::transport::process::ProcessFault;
                let code = match error {
                    ProcessFault::StdoutLimit => "stdout-limit",
                    ProcessFault::OutputAllocation(_) => "output-allocation",
                    ProcessFault::PipeRead(..) => "pipe-read",
                    ProcessFault::PipeThreadStart(..) => "pipe-thread-start",
                    ProcessFault::ReaderPanicked(_) => "reader-panicked",
                    ProcessFault::Containment => "containment",
                    ProcessFault::ChildWait(_) => "child-wait",
                };
                (
                    "installed-process",
                    code,
                    "actual installed process owner reported a fault",
                )
            }
            Self::Installed(installed::adapter::InstalledAdapterError::Cancelled) => (
                "installed-cancelled",
                "installed-cancelled",
                "installed execution was cancelled",
            ),
            Self::Installed(installed::adapter::InstalledAdapterError::ObservationIncomplete) => (
                "installed-observation",
                "installed-observation-incomplete",
                "installed observation coverage is incomplete",
            ),
            Self::InstalledObservation(_) => (
                "installed-observation",
                "installed-observation-refused",
                "installed observation receiving permission refused",
            ),
            Self::RecordRetention(error) => match error {
                super::native::PrivateRecordError::Capacity { .. } => (
                    "native-record-retention",
                    "record-retention-capacity",
                    "private record capacity refused",
                ),
                super::native::PrivateRecordError::SizeOverflow => (
                    "native-record-retention",
                    "record-retention-size-overflow",
                    "private record capacity arithmetic refused",
                ),
                super::native::PrivateRecordError::LengthMismatch { .. } => (
                    "native-record-retention",
                    "record-length-mismatch",
                    "private record length differs from permission",
                ),
                super::native::PrivateRecordError::CapacityMismatch { .. } => (
                    "native-record-retention",
                    "record-capacity-mismatch",
                    "private record capacity differs from permission",
                ),
                super::native::PrivateRecordError::AllocationMismatch => (
                    "native-record-retention",
                    "record-allocation-mismatch",
                    "private record allocation differs from permission",
                ),
                super::native::PrivateRecordError::InvalidUtf8 => (
                    "native-record-retention",
                    "record-invalid-utf8",
                    "private record UTF8 representation refused",
                ),
                super::native::PrivateRecordError::UnsupportedRepresentation => (
                    "native-record-retention",
                    "record-representation-unsupported",
                    "private record exceeds supported text representation",
                ),
                super::native::PrivateRecordError::Abandoned => (
                    "native-record-retention",
                    "record-adoption-abandoned",
                    "private record adoption was abandoned",
                ),
                super::native::PrivateRecordError::PriorWorkFault => (
                    "native-record-retention",
                    "record-prior-work-fault",
                    "private record work owner already refused",
                ),
            },
            Self::Native(error) => match error {
                super::native::NativeAdapterError::Startup => (
                    "native-startup",
                    "native-startup-refused",
                    "native adapter startup failed",
                ),
                super::native::NativeAdapterError::Fixture => (
                    "native-fixture",
                    "native-fixture-refused",
                    "native fixture preparation failed",
                ),
                super::native::NativeAdapterError::Authentication => (
                    "native-authentication",
                    "native-authentication-refused",
                    "native host authentication failed",
                ),
                super::native::NativeAdapterError::Discovery => (
                    "native-discovery",
                    "native-discovery-refused",
                    "native host discovery failed",
                ),
                super::native::NativeAdapterError::Selection => (
                    "native-selection",
                    "native-selection-refused",
                    "native host selection failed",
                ),
                super::native::NativeAdapterError::Exchange => (
                    "native-exchange",
                    "native-exchange-refused",
                    "native host exchange failed",
                ),
                super::native::NativeAdapterError::ObservationIncomplete => (
                    "native-observation",
                    "native-observation-incomplete",
                    "native observation coverage is incomplete",
                ),
                super::native::NativeAdapterError::Cleanup => (
                    "native-cleanup",
                    "native-cleanup-refused",
                    "native host cleanup failed",
                ),
                super::native::NativeAdapterError::Cancelled => (
                    "native-cancelled",
                    "native-cancelled",
                    "native execution was cancelled",
                ),
                super::native::NativeAdapterError::UnsupportedAction => (
                    "native-action",
                    "native-action-unsupported",
                    "native action is unsupported",
                ),
            },
            Self::Record(WorkflowRecordError::Observation(ObservationError::ExpectedBlocked)) => (
                "observation",
                "expected-blocked",
                "expected workflow is explicitly blocked",
            ),
            Self::Record(WorkflowRecordError::Observation(ObservationError::InstalledClient(
                fault,
            ))) => (
                "observation",
                match fault {
                    super::observation_check::InstalledClientFault::ConsumerAssociation => {
                        "installed-consumer-association"
                    }
                    super::observation_check::InstalledClientFault::ConsumerClock => {
                        "installed-consumer-clock"
                    }
                    super::observation_check::InstalledClientFault::ConsumerTranscript => {
                        "installed-consumer-transcript"
                    }
                    super::observation_check::InstalledClientFault::ConsumerRelease => {
                        "installed-consumer-release"
                    }
                    super::observation_check::InstalledClientFault::ConsumerCommit => {
                        "installed-consumer-commit"
                    }
                    super::observation_check::InstalledClientFault::ConsumerCleanup => {
                        "installed-consumer-cleanup"
                    }
                    super::observation_check::InstalledClientFault::ConsumerHelper => {
                        "installed-consumer-helper"
                    }
                    super::observation_check::InstalledClientFault::ImplementationMissing => {
                        "implementation-missing"
                    }
                    super::observation_check::InstalledClientFault::ImplementationBinding => {
                        "implementation-binding"
                    }
                    super::observation_check::InstalledClientFault::ImplementationDigest => {
                        "implementation-digest"
                    }
                    super::observation_check::InstalledClientFault::ImplementationProcess => {
                        "implementation-process"
                    }
                    super::observation_check::InstalledClientFault::SourceBinding => {
                        "installed-source-binding"
                    }
                    super::observation_check::InstalledClientFault::SourceCoverage => {
                        "installed-source-coverage"
                    }
                    super::observation_check::InstalledClientFault::SourceWitness => {
                        "installed-source-witness"
                    }
                    super::observation_check::InstalledClientFault::WorkerCoverage => {
                        "installed-worker-coverage"
                    }
                    super::observation_check::InstalledClientFault::ProcessOrder => {
                        "installed-process-order"
                    }
                    super::observation_check::InstalledClientFault::ProcessOutcome => {
                        "installed-process-outcome"
                    }
                    super::observation_check::InstalledClientFault::ProcessClaims => {
                        "installed-process-claims"
                    }
                    super::observation_check::InstalledClientFault::SocketAssociation => {
                        "installed-socket-association"
                    }
                    super::observation_check::InstalledClientFault::SocketOrder => {
                        "installed-socket-order"
                    }
                    super::observation_check::InstalledClientFault::SocketFrame => {
                        "installed-socket-frame"
                    }
                    super::observation_check::InstalledClientFault::SendOutcome => {
                        "installed-send-outcome"
                    }
                    super::observation_check::InstalledClientFault::RecordAdoption => {
                        "installed-record-adoption"
                    }
                    super::observation_check::InstalledClientFault::DestinationCoverage => {
                        "installed-destination-coverage"
                    }
                    super::observation_check::InstalledClientFault::DestinationEntries => {
                        "installed-destination-entries"
                    }
                    super::observation_check::InstalledClientFault::DestinationBytes => {
                        "installed-destination-bytes"
                    }
                    super::observation_check::InstalledClientFault::ScratchCoverage => {
                        "installed-scratch-coverage"
                    }
                    super::observation_check::InstalledClientFault::ScratchEntries => {
                        "installed-scratch-entries"
                    }
                },
                "installed factual consistency refused",
            ),
            Self::Record(WorkflowRecordError::Observation(_)) => (
                "observation",
                "observation-refused",
                "workflow observation refused",
            ),
            Self::Record(WorkflowRecordError::Envelope(_)) => {
                ("envelope", "envelope-refused", "workflow envelope refused")
            }
            Self::Record(WorkflowRecordError::Decode(_)) | Self::Decode(_) => {
                ("decode", "decode-refused", "workflow decode refused")
            }
            Self::Capabilities(_) | Self::UnsupportedRole => (
                "capabilities",
                "capabilities-refused",
                "adapter capabilities refused",
            ),
            Self::Exchange(_) => ("exchange", "exchange-refused", "adapter exchange failed"),
            Self::Capture(_) => (
                "capture",
                "capture-refused",
                "literal capture budget refused",
            ),
        };
        FailureSummary {
            phase,
            code,
            message,
        }
    }
}
/// The genuine first error stays owned here until final bounded encoding. The
/// evidence summaries cannot construct/reset it, and later rows do no work.
struct Attempt {
    fault: Option<RunFault>,
}
struct PreparedExecution<'a> {
    report: RuntimeReport<'a>,
    attempt: Attempt,
    shutdown: Option<TransportError>,
}
impl Attempt {
    fn ready(&self) -> Result<(), &RunFault> {
        self.fault.as_ref().map_or(Ok(()), Err)
    }
    fn fail(&mut self, error: RunFault) {
        if self.fault.is_none() {
            self.fault = Some(error);
        }
    }
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CapabilitiesRequest {
    op: &'static str,
    suite: &'static str,
    contract_version: &'static str,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CaseRequest<'a> {
    op: &'static str,
    suite: &'static str,
    contract_version: &'static str,
    format: &'static str,
    run_index: usize,
    input: &'a RawValue,
}

fn ready(owners: &mut Owners) -> Result<(), RunFault> {
    // Same rule as context.check_record: an existing comparison fault precedes
    // any new decoder work. No source or corpus-supplied limits are consulted.
    owners
        .comparison
        .ready()
        .map_err(|e| RunFault::Record(WorkflowRecordError::Observation(e)))?;
    owners.decode.ready().map_err(RunFault::Decode)
}
fn outer_id(document: &Document, expected: u64, owner: &mut Decoder) -> Result<(), DecodeError> {
    owner.ready()?;
    let Document::Object(fields) = document else {
        return Err(DecodeError::Shape("session outer sequence object"));
    };
    for (key, value) in fields {
        owner.bytes(key.len().checked_add(2).ok_or(DecodeError::Limits)?)?;
        if key == "id" {
            let Document::Number(number) = value else {
                return Err(DecodeError::Shape("session outer sequence id"));
            };
            owner.bytes(number.as_str().len())?;
            let id = crate::workbench::model_originals::RequestId::parse(number.as_str())
                .map_err(|_| DecodeError::Shape("session outer sequence id"))?;
            return if id.get() == expected {
                Ok(())
            } else {
                Err(DecodeError::Shape("session outer sequence differs"))
            };
        }
    }
    Err(DecodeError::Shape("session outer sequence missing"))
}
fn check_negotiation(
    record: &WorkflowExchangeRecord,
    owner: &mut Decoder,
) -> Result<Capabilities, DecodeError> {
    let (request, _) = owner.literal_with_raw(record.sent_payload())?;
    let fields = Fields::new(&request, &["id", "op", "suite", "contractVersion"], owner)?;
    outer_id(&request, 1, owner)?;
    for (field, expected) in [
        ("op", "capabilities"),
        ("suite", "workbench"),
        ("contractVersion", VERSION),
    ] {
        let actual = string(fields.document(field, owner)?, owner)?;
        owner.bytes(
            actual
                .len()
                .checked_add(expected.len())
                .ok_or(DecodeError::Limits)?,
        )?;
        if actual != expected {
            return Err(DecodeError::Shape("negotiation request differs"));
        }
    }
    let (reply, _) = owner.literal_with_raw(record.received_payload())?;
    outer_id(&reply, 1, owner)?;
    Capabilities::decode(&reply, true, owner)
}
fn check_sequence(
    record: &WorkflowExchangeRecord,
    index: usize,
    owner: &mut Decoder,
) -> Result<(), DecodeError> {
    let expected = u64::try_from(index)
        .ok()
        .and_then(|index| index.checked_add(2))
        .ok_or(DecodeError::Limits)?;
    let (request, _) = owner.literal_with_raw(record.sent_payload())?;
    outer_id(&request, expected, owner)
}
fn negotiate(
    session: &mut Session,
    owners: &mut Owners,
) -> Result<(WorkflowExchangeRecord, Capabilities), RunFault> {
    ready(owners)?;
    let request = CapabilitiesRequest {
        op: "capabilities",
        suite: "workbench",
        contract_version: VERSION,
    };
    let exchange = session
        .exchange_recorded_literal(&request)
        .map_err(RunFault::Exchange)?;
    let record = WorkflowExchangeRecord::capture(exchange);
    owners
        .capture
        .retain(record.sent_payload().len(), record.received_payload().len())
        .map_err(RunFault::Capture)?;
    let caps = check_negotiation(&record, &mut owners.decode).map_err(RunFault::Capabilities)?;
    Ok((record, caps))
}

pub(in crate::workbench) fn execute<F>(
    source: &Source,
    policy: &Policy,
    factory: F,
) -> Result<StoredReport, String>
where
    F: FnOnce() -> Result<Session, TransportError>,
{
    prepared(
        source,
        policy,
        ReviewedSources::selected(),
        |compiled, owners| {
            // All actual source/closure/expansion and ordered inventory work is
            // complete before the real factory is invoked. No context is lent out.
            ready(owners).map_err(|_| "source owner refused before spawn".to_owned())?;
            let mut session = factory().map_err(|_| "adapter spawn refused".to_owned())?;
            let result = execute_prepared(source, compiled, owners, &mut session);
            let shutdown = session.close();
            match result {
                Ok(mut execution) => {
                    if let Err(error) = shutdown {
                        execution.shutdown = Some(error);
                        execution.report.errors.push(FailureSummary {
                            phase: "shutdown",
                            code: "shutdown-refused",
                            message: "adapter shutdown failed",
                        });
                    }
                    render(execution)
                }
                Err(error) => Err(error),
            }
        },
    )
}
fn execute_prepared<'a>(
    source: &'a Source,
    compiled: &'a [CompiledExecution<'_, '_, '_, '_>],
    owners: &mut Owners,
    session: &mut Session,
) -> Result<PreparedExecution<'a>, String> {
    owners
        .decode
        .slots(compiled.len())
        .map_err(|_| "inventory work refused".to_owned())?;
    let mut records = Vec::new();
    records
        .try_reserve_exact(compiled.len())
        .map_err(|_| "inventory allocation refused".to_owned())?;
    owners
        .decode
        .slots(3)
        .map_err(|_| "failure inventory work refused".to_owned())?;
    let mut errors = Vec::new();
    errors
        .try_reserve_exact(3)
        .map_err(|_| "failure inventory allocation refused".to_owned())?;
    let mut attempt = Attempt { fault: None };
    let (negotiation, capabilities) = match negotiate(session, owners) {
        Ok((record, caps)) => (Some(record), Some(caps)),
        Err(error) => {
            attempt.fail(error);
            (None, None)
        }
    };
    for (index, compiled_case) in compiled.iter().enumerate() {
        let compiled_case = compiled_case
            .current()
            .ok_or("external adapter cannot execute native source")?;
        let context = compiled_case.report_context();
        let role = Role::of(context.paired().run());
        let evidence = if attempt.ready().is_err() {
            Evidence::NotAttempted {
                prior_failure_index: 0,
            }
        } else if !capabilities
            .as_ref()
            .is_some_and(|caps| caps.supports(role))
        {
            attempt.fail(RunFault::UnsupportedRole);
            Evidence::NotAttempted {
                prior_failure_index: 0,
            }
        } else {
            // Readiness is checked before constructing/serializing the next
            // real source request or touching the Session. No peer sees expected.
            let result = ready(owners).and_then(|()| {
                let request = CaseRequest {
                    op: role.text(),
                    suite: "workbench",
                    contract_version: VERSION,
                    format: "json",
                    run_index: context.paired().run_index(),
                    input: context.input_raw(),
                };
                session
                    .exchange_recorded_literal(&request)
                    .map_err(RunFault::Exchange)
            });
            match result {
                Err(error) => {
                    attempt.fail(error);
                    Evidence::AttemptFailed { failure_index: 0 }
                }
                Ok(exchange) => {
                    let record = WorkflowExchangeRecord::capture(exchange);
                    match owners
                        .capture
                        .retain(record.sent_payload().len(), record.received_payload().len())
                    {
                        Err(error) => {
                            attempt.fail(RunFault::Capture(error));
                            Evidence::AttemptFailed { failure_index: 0 }
                        }
                        Ok(()) => {
                            let verdict = match check_sequence(&record, index, &mut owners.decode)
                                .map_err(WorkflowRecordError::Decode)
                                .and_then(|()| {
                                    context.check_record(
                                        &record,
                                        &mut owners.decode,
                                        &mut owners.comparison,
                                    )
                                }) {
                                Ok(_) => Verdict::Checked,
                                Err(error) => {
                                    attempt.fail(RunFault::Record(error));
                                    Verdict::Failed { failure_index: 0 }
                                }
                            };
                            Evidence::Captured {
                                exchange: record,
                                verdict,
                            }
                        }
                    }
                }
            }
        };
        // Borrow genuine prepared metadata. These views allocate/copy nothing
        // after the first fault; all destinations were reserved before effects.
        records.push(RuntimeRecord {
            case_id: context.case().id(),
            execution: ExecutionRef::from_pair(compiled_case.source().paired()),
            evidence,
        });
    }
    if let Some(fault) = &attempt.fault {
        errors.push(fault.summary());
    }
    // The only selected source set is explicitly partial23; lineage remains
    // Unproven and strong producer predicates are incomplete. No complete proof
    // constructor exists here, so all-checked counts cannot grant qualification.
    Ok(PreparedExecution {
        report: RuntimeReport {
            format_version: VERSION,
            suite: "workbench",
            corpus_hash: source.digest(),
            capabilities,
            negotiation,
            records,
            errors,
            qualified: false,
        },
        attempt,
        shutdown: None,
    })
}
fn render(execution: PreparedExecution<'_>) -> Result<StoredReport, String> {
    let report = &execution.report;
    if let Some(error) = &execution.attempt.fault
        && report.errors.first() != Some(&error.summary())
    {
        return Err("report first fault changed before encoding".into());
    }
    if execution.shutdown.is_some()
        && report.errors.last().map(|error| error.code) != Some("shutdown-refused")
    {
        return Err("report lost actual shutdown fault".into());
    }
    let bytes = crate::workbench::contract::encoded_size(&report, MAX_REPORT_BYTES - 1)?;
    let mut destination = Vec::new();
    destination
        .try_reserve_exact(bytes.checked_add(1).ok_or("report encoded overflow")?)
        .map_err(|_| "report encoding allocation refused")?;
    serde_json::to_writer(&mut destination, report).map_err(|_| "report encoding refused")?;
    destination.push(b'\n');
    let raw = String::from_utf8(destination).map_err(|_| "report encoder did not produce UTF8")?;
    Ok(StoredReport::rendered(raw, report.records.len()))
}

/// The native producer uses the same source preparation, cumulative owners,
/// first-fault attempt, report representation and factual replay checker.
pub(in crate::workbench) fn execute_native(
    source: &Source,
    policy: &Policy,
    limits: &super::native::NativeObservationLimits,
    record_limits: &super::native::RecordRetentionLimits,
    adapter: &mut dyn super::native::NativeOriginalAdapter,
) -> Result<StoredReport, String> {
    // Exactly one caller-selected receiving owner for the whole invocation,
    // outside preparation and every case/callback. No per-case reset/refund.
    let mut record_owner =
        super::native::record_retention::RecordRetentionOwner::new(record_limits);
    prepared(
        source,
        policy,
        ReviewedSources::native_selected(),
        |compiled, owners| {
            owners
                .decode
                .slots(compiled.len())
                .map_err(|_| "inventory work refused")?;
            let mut records = Vec::new();
            records
                .try_reserve_exact(compiled.len())
                .map_err(|_| "inventory allocation refused")?;
            owners
                .decode
                .slots(1)
                .map_err(|_| "failure inventory work refused")?;
            let mut errors = Vec::new();
            errors
                .try_reserve_exact(1)
                .map_err(|_| "failure inventory allocation refused")?;
            let mut attempt = Attempt { fault: None };
            for case in compiled {
                let evidence = if attempt.ready().is_err() {
                    Evidence::NotAttempted {
                        prior_failure_index: 0,
                    }
                } else {
                    match ready(owners).and_then(|()| match case {
                        CompiledExecution::Native(native) => {
                            let result =
                                adapter.observe(super::native::NativeOriginalRun::from_compiled(
                                    native,
                                    limits,
                                    &mut owners.comparison,
                                    &mut record_owner,
                                ));
                            // A producer may report its own failure after recipe
                            // work refused. Preserve the genuine owner's first
                            // typed fault before interpreting that adapter result.
                            owners.comparison.ready().map_err(|error| {
                                RunFault::Record(WorkflowRecordError::Observation(error))
                            })?;
                            record_owner
                                .ready()
                                .map_err(|error| RunFault::RecordRetention(*error))?;
                            result.map_err(RunFault::Native)
                        }
                        CompiledExecution::Current(_) => Err(RunFault::UnsupportedRole),
                    }) {
                        Err(error) => {
                            attempt.fail(error);
                            Evidence::AttemptFailed { failure_index: 0 }
                        }
                        Ok(measurement) => {
                            // Count before retaining the returned factual DATA in
                            // the report. This is not an invented transport frame.
                            let retained = crate::workbench::contract::encoded_size(
                                &measurement,
                                MAX_REPORT_BYTES,
                            )
                            .map_err(|_| RunFault::Capture(CaptureFault::Reply))
                            .and_then(|bytes| {
                                owners.capture.retain(0, bytes).map_err(RunFault::Capture)
                            })
                            .and_then(|()| {
                                wire::NativeMeasurement::retain(measurement, &mut owners.decode)
                                    .map_err(RunFault::Decode)
                            });
                            match retained {
                                Err(error) => {
                                    attempt.fail(error);
                                    Evidence::AttemptFailed { failure_index: 0 }
                                }
                                Ok(measurement) => {
                                    let CompiledExecution::Native(native) = case else {
                                        return Err(
                                            "native measurement without native source".into()
                                        );
                                    };
                                    let verdict =
                                    match super::observation_check::server::compare_declaration_data(
                                        native.plan(),
                                        measurement.value(),
                                        &mut owners.comparison,
                                    ) {
                                        Ok(_) => Verdict::Checked,
                                        Err(error) => {
                                            attempt.fail(RunFault::Record(
                                                WorkflowRecordError::Observation(error),
                                            ));
                                            Verdict::Failed { failure_index: 0 }
                                        }
                                    };
                                    Evidence::NativeMeasured {
                                        measurement,
                                        verdict,
                                    }
                                }
                            }
                        }
                    }
                };
                records.push(RuntimeRecord {
                    case_id: case.case().id(),
                    execution: ExecutionRef::from_compiled(case),
                    evidence,
                });
            }
            if let Some(error) = &attempt.fault {
                errors.push(error.summary())
            }
            render(PreparedExecution {
                report: RuntimeReport {
                    format_version: VERSION,
                    suite: "workbench",
                    corpus_hash: source.digest(),
                    capabilities: None,
                    records,
                    negotiation: None,
                    errors,
                    qualified: false,
                },
                attempt,
                shutdown: None,
            })
        },
    )
}

pub(in crate::workbench) fn replay_native(
    source: &Source,
    policy: &Policy,
    report: &StoredReport,
) -> Result<(), String> {
    prepared(
        source,
        policy,
        ReviewedSources::native_selected(),
        |compiled, owners| {
            ready(owners).map_err(|_| "source owners refused before replay")?;
            let document =
                Document::parse_exact_with_work(report.text().as_bytes(), &mut owners.saved)
                    .map_err(|_| "saved report decode refused")?;
            let saved = wire::saved(document, &mut owners.decode)
                .map_err(|_| "saved report decode refused")?;
            if saved.revision != report_revision::ReportRevision::Legacy30 {
                return Err(
                    "consumer report revision requires explicit operation selection".into(),
                );
            }
            if saved.corpus_hash != source.digest() {
                return Err("corpus fullfile digest differs".into());
            }
            if saved.records.len() != compiled.len() {
                return Err("inventory record count differs".into());
            }
            if saved.capabilities.is_some() || saved.negotiation.is_some() {
                return Err("native report cannot claim external negotiation".into());
            }
            for (row, case) in saved.records.iter().zip(compiled) {
                owners
                    .decode
                    .bytes(
                        row.case_id
                            .len()
                            .checked_add(case.case().id().len())
                            .ok_or("inventory overflow")?,
                    )
                    .map_err(|_| "inventory work refused")?;
                if row.case_id != case.case().id()
                    || !row
                        .execution
                        .matches_compiled(case, &mut owners.decode)
                        .map_err(|_| "inventory work refused")?
                {
                    return Err("inventory execution key/order differs".into());
                }
            }
            let mut attempt = Attempt { fault: None };
            for (row, case) in saved.records.iter().zip(compiled) {
                if attempt.ready().is_err() {
                    if !matches!(
                        row.evidence,
                        Evidence::NotAttempted {
                            prior_failure_index: 0
                        }
                    ) {
                        return Err("inventory contains evidence after first fault".into());
                    }
                    continue;
                }
                match (&row.evidence, case) {
                    (
                        Evidence::NativeMeasured {
                            measurement,
                            verdict,
                        },
                        CompiledExecution::Native(native),
                    ) => {
                        ready(owners).map_err(|_| "replay owner refused")?;
                        let bytes = crate::workbench::contract::encoded_size(
                            measurement.value(),
                            MAX_REPORT_BYTES,
                        )?;
                        owners
                            .capture
                            .retain(0, bytes)
                            .map_err(|_| "capture aggregate refused")?;
                        match super::observation_check::server::compare_declaration_data(
                            native.plan(),
                            measurement.value(),
                            &mut owners.comparison,
                        ) {
                            Ok(_) if matches!(verdict, Verdict::Checked) => {}
                            Err(error)
                                if matches!(verdict, Verdict::Failed { failure_index: 0 }) =>
                            {
                                attempt
                                    .fail(RunFault::Record(WorkflowRecordError::Observation(error)))
                            }
                            _ => return Err("forged native factual verdict".into()),
                        }
                    }
                    (
                        Evidence::AttemptFailed { failure_index: 0 },
                        CompiledExecution::Native(_),
                    ) => {
                        // Saved incomplete attempts establish no actual SDK/host
                        // outcome. Only their closed unqualified record structure
                        // is accepted; they cannot issue a live invocation.
                        // This is closed saved failure DATA, not reconstruction
                        // of a live failure or SDK owner. Keep its category while
                        // checking factual report structure only.
                        use super::native::NativeAdapterError;
                        let category = [
                            NativeAdapterError::Startup,
                            NativeAdapterError::Fixture,
                            NativeAdapterError::Authentication,
                            NativeAdapterError::Discovery,
                            NativeAdapterError::Selection,
                            NativeAdapterError::Exchange,
                            NativeAdapterError::ObservationIncomplete,
                            NativeAdapterError::Cleanup,
                            NativeAdapterError::Cancelled,
                            NativeAdapterError::UnsupportedAction,
                        ]
                        .into_iter()
                        .find(|error| {
                            saved
                                .errors
                                .first()
                                .is_some_and(|row| row.matches(RunFault::Native(*error).summary()))
                        })
                        .ok_or("saved native failure category differs")?;
                        attempt.fail(RunFault::Native(category));
                    }
                    (
                        Evidence::AttemptFailed { failure_index: 0 },
                        CompiledExecution::Current(_),
                    ) => attempt.fail(RunFault::UnsupportedRole),
                    _ => return Err("native evidence/source kind differs".into()),
                }
            }
            match &attempt.fault {
                Some(error)
                    if saved.errors.len() == 1 && saved.errors[0].matches(error.summary()) => {}
                None if saved.errors.is_empty() => {}
                _ => return Err("saved first failure differs".into()),
            }
            if saved.qualified {
                return Err("forged qualified claim for partial/unproven source set".into());
            }
            Ok(())
        },
    )
}

pub(in crate::workbench) fn replay(
    source: &Source,
    policy: &Policy,
    report: &StoredReport,
) -> Result<(), String> {
    prepared(
        source,
        policy,
        ReviewedSources::selected(),
        |compiled, owners| {
            ready(owners).map_err(|_| "source owners refused before replay".to_owned())?;
            let document =
                Document::parse_exact_with_work(report.text().as_bytes(), &mut owners.saved)
                    .map_err(|_| "saved report decode refused".to_owned())?;
            let saved = wire::saved(document, &mut owners.decode).map_err(|error| {
                match error {
                    wire::SavedError::Negotiation(_) => "saved negotiation decode refused",
                    wire::SavedError::Report(_) => "saved report decode refused",
                }
                .to_owned()
            })?;
            if saved.revision != report_revision::ReportRevision::Legacy30 {
                return Err(
                    "consumer report revision requires explicit operation selection".into(),
                );
            }
            if saved.corpus_hash != source.digest() {
                return Err("corpus fullfile digest differs".into());
            }
            if saved.records.len() != compiled.len() {
                return Err("inventory record count differs".into());
            }
            // Check ALL source-derived keys/order before decoding any observation.
            for (record, case) in saved.records.iter().zip(compiled) {
                let case = case
                    .current()
                    .ok_or("external replay cannot use native source")?;
                let context = case.report_context();
                owners
                    .decode
                    .bytes(
                        record
                            .case_id
                            .len()
                            .saturating_add(context.case().id().len()),
                    )
                    .map_err(|_| "inventory work refused".to_owned())?;
                if record.case_id != context.case().id()
                    || !record
                        .execution
                        .matches(context.paired(), &mut owners.decode)
                        .map_err(|_| "inventory work refused".to_owned())?
                {
                    return Err("inventory execution key/order differs".into());
                }
            }
            let negotiation = saved
                .negotiation
                .as_ref()
                .ok_or("negotiation evidence missing")?;
            owners
                .capture
                .retain(
                    negotiation.sent_payload().len(),
                    negotiation.received_payload().len(),
                )
                .map_err(|_| "negotiation capture aggregate refused".to_owned())?;
            let caps = check_negotiation(negotiation, &mut owners.decode)
                .map_err(|_| "negotiation request/reply refused".to_owned())?;
            let Some(summary) = &saved.capabilities else {
                return Err("unverified negotiation capabilities failure report".into());
            };
            if !caps
                .matches(summary, &mut owners.decode)
                .map_err(|_| "negotiation summary comparison refused".to_owned())?
            {
                return Err("negotiation capabilities summary differs".into());
            }
            let mut attempt = Attempt { fault: None };
            for (index, (record, case)) in saved.records.iter().zip(compiled).enumerate() {
                let case = case
                    .current()
                    .ok_or("external replay cannot use native source")?;
                let context = case.report_context();
                if attempt.ready().is_err() {
                    if !matches!(
                        record.evidence,
                        Evidence::NotAttempted {
                            prior_failure_index: 0
                        }
                    ) {
                        return Err("inventory contains evidence after first fault".into());
                    }
                    continue;
                }
                if !caps.supports(Role::of(context.paired().run())) {
                    return Err("capabilities omit selected source role".into());
                }
                match &record.evidence {
                    Evidence::ConsumerAttemptFailed { .. }
                    | Evidence::StoredConsumerAttemptFailed { .. } => {
                        return Err("consumer partial evidence requires installed selection".into());
                    }
                    Evidence::Captured { exchange, verdict } => {
                        owners
                            .capture
                            .retain(
                                exchange.sent_payload().len(),
                                exchange.received_payload().len(),
                            )
                            .map_err(|_| "capture aggregate refused".to_owned())?;
                        check_sequence(exchange, index, &mut owners.decode)
                            .map_err(|_| "session outer request sequence differs".to_owned())?;
                        match context.check_record(
                            exchange,
                            &mut owners.decode,
                            &mut owners.comparison,
                        ) {
                            Ok(_) => {
                                if !matches!(verdict, Verdict::Checked) {
                                    return Err("forged record verdict".into());
                                }
                            }
                            Err(error) => {
                                if !matches!(verdict, Verdict::Failed { failure_index: 0 }) {
                                    return Err("forged record verdict".into());
                                }
                                attempt.fail(RunFault::Record(error));
                            }
                        }
                    }
                    // Incomplete transport/capture has no recorded complete reply
                    // from which replay could recompute the actual typed cause.
                    Evidence::AttemptFailed { .. } => {
                        return Err("unverified incomplete actual attempt".into());
                    }
                    Evidence::NotAttempted { .. } => {
                        return Err("inventory omits required actual attempt".into());
                    }
                    Evidence::NativeMeasured { .. } | Evidence::ClientProcessMeasured { .. } => {
                        return Err("native measurements require native configuration".into());
                    }
                }
            }
            match &attempt.fault {
                Some(error)
                    if saved.errors.len() == 1 && saved.errors[0].matches(error.summary()) => {}
                None if saved.errors.is_empty() => {}
                _ => return Err("saved first failure differs".into()),
            }
            if saved.qualified {
                return Err("forged qualified claim for partial/unproven source set".into());
            }
            Ok(())
        },
    )
}

#[cfg(test)]
mod installed_client_tests;

#[cfg(test)]
mod installed_observation_tests;

#[cfg(test)]
mod typed_preparation_tests;

#[cfg(target_os = "macos")]
pub use browser::{BrowserControllerBusinessCredit, BrowserControllerBusinessFundingFault};

#[cfg(target_os = "macos")]
pub use browser::{
    BrowserConnectedObservation, BrowserContinuingController, BrowserControllerContinueFailure,
    BrowserControllerFile, BrowserControllerFiles, BrowserControllerFinished,
    BrowserControllerLaunchFailure, BrowserControllerLaunchStage,
    BrowserControllerPreparationFailure, BrowserControllerPreparationFinished,
    BrowserControllerPreparationStage, BrowserControllerRetirement, BrowserFixedController,
    BrowserInspectionPreparationFailure, BrowserInspectionSettlementFailure,
    BrowserMaterializedController, BrowserStoppedController, BrowserUnlaunchedControllerFinished,
};
