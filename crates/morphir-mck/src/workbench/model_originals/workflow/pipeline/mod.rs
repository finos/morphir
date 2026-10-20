//! One selected branch of the existing Workbench pipeline. The fixed reviewed
//! source bundle is PARTIAL. No semantic lineage/runtime qualification is issued.
mod policy;
mod raw;
mod wire;
use super::ingress::BoundCorpus;
use super::observation_check::ObservationError;
use super::reviewed_sources::ReviewedSources;
use super::source_compile::{
    CaseCompiler, CompilationError, CompiledSourceCase, WorkflowRecordError,
};
use super::source_proof::{SourceError, SourceVerifier};
use super::{DecodeError, Decoder, Fields, string};
use crate::json::strict::Document;
use crate::transport::{Session, TransportError};
use crate::workbench::corpus::CorpusSource;
use crate::workbench::report::{MAX_REPORT_BYTES, WorkflowExchangeRecord};
pub(in crate::workbench) use policy::Policy;
use policy::{CaptureFault, Owners};
use raw::VERSION;
pub(in crate::workbench) use raw::{StoredReport, recognizes};
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

// Preparation locals own every operand and compiled view for the whole action.
// No self-reference or compiler/context borrow can escape the owned result R.
fn prepared<R>(
    source: &Source,
    policy: &Policy,
    action: impl FnOnce(&[CompiledSourceCase<'_, '_, '_, '_>], &mut Owners) -> Result<R, String>,
) -> Result<R, String> {
    let mut owners = policy.owners();
    let bound = BoundCorpus::decode_selected(source.raw.text(), &mut owners.decode)
        .map_err(|_| "source corpus decode refused".to_owned())?;
    owners
        .decode
        .slots(bound.cases().len())
        .map_err(|_| "source prepared inventory work refused".to_owned())?;
    let mut compiled = Vec::new();
    compiled
        .try_reserve_exact(bound.cases().len())
        .map_err(|_| "source prepared inventory allocation refused".to_owned())?;
    let sources = ReviewedSources::selected();
    let verifier = SourceVerifier::new(&sources, &mut owners.decode)
        .map_err(|_| "source anchors refused".to_owned())?;
    let mut compiler = CaseCompiler::new(verifier, &mut owners.closure, &mut owners.expansion);
    for case in bound.cases() {
        compiled.push(compiler.compile(case).map_err(compilation_message)?);
    }
    compiler
        .require_inventory(bound.cases())
        .map_err(compilation_message)?;
    drop(compiler);
    action(&compiled, &mut owners)
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
}
impl RunFault {
    fn summary(&self) -> FailureSummary {
        let (phase, code, message) = match self {
            Self::Record(WorkflowRecordError::Observation(ObservationError::ExpectedBlocked)) => (
                "observation",
                "expected-blocked",
                "expected workflow is explicitly blocked",
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
    prepared(source, policy, |compiled, owners| {
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
    })
}
fn execute_prepared<'a>(
    source: &'a Source,
    compiled: &'a [CompiledSourceCase<'_, '_, '_, '_>],
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

pub(in crate::workbench) fn replay(
    source: &Source,
    policy: &Policy,
    report: &StoredReport,
) -> Result<(), String> {
    prepared(source, policy, |compiled, owners| {
        ready(owners).map_err(|_| "source owners refused before replay".to_owned())?;
        let document = Document::parse_exact_with_work(report.text().as_bytes(), &mut owners.saved)
            .map_err(|_| "saved report decode refused".to_owned())?;
        let saved = wire::saved(document, &mut owners.decode).map_err(|error| {
            match error {
                wire::SavedError::Negotiation(_) => "saved negotiation decode refused",
                wire::SavedError::Report(_) => "saved report decode refused",
            }
            .to_owned()
        })?;
        if saved.corpus_hash != source.digest() {
            return Err("corpus fullfile digest differs".into());
        }
        if saved.records.len() != compiled.len() {
            return Err("inventory record count differs".into());
        }
        // Check ALL source-derived keys/order before decoding any observation.
        for (record, case) in saved.records.iter().zip(compiled) {
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
                    match context.check_record(exchange, &mut owners.decode, &mut owners.comparison)
                    {
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
            }
        }
        match &attempt.fault {
            Some(error) if saved.errors.len() == 1 && saved.errors[0].matches(error.summary()) => {}
            None if saved.errors.is_empty() => {}
            _ => return Err("saved first failure differs".into()),
        }
        if saved.qualified {
            return Err("forged qualified claim for partial/unproven source set".into());
        }
        Ok(())
    })
}
