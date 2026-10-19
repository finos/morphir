//! One staged source-binding entry for actual and reloaded literal evidence.
//! This candidate envelope is not registered as a supported Workbench draft.
use super::ingress::BoundCase;
use super::observation_check::{CompareOwner, ObservationError};
use super::pairing::PairedRun;
use super::source_compile::WorkflowReportContext;
use super::{Decode, DecodeError, Decoder, Fields, observed, string};
use crate::json::strict::Document;
use crate::workbench::model_originals::RequestId;
use crate::workbench::report::WorkflowExchangeRecord;
use serde_json::value::RawValue;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum WorkflowEnvelopeFault {
    RequestId,
    ReplyId,
    Correlation,
    Suite,
    Version,
    Format,
    Role,
    RunIndex,
    Input,
    Status,
    SizeOverflow,
}
#[derive(Debug)]
pub(super) enum WorkflowRecordError {
    Decode(DecodeError),
    Envelope(WorkflowEnvelopeFault),
    Observation(ObservationError),
}
impl From<DecodeError> for WorkflowRecordError {
    fn from(error: DecodeError) -> Self {
        Self::Decode(error)
    }
}

/// Factual comparison result only. It borrows the genuine case and immutable
/// raw evidence rather than returning a reference into the local decoded AST.
/// No constructor, Clone, qualification state or authority is exposed.
pub(super) struct WorkflowRecordComparison<'source, 'record, 'raw> {
    case: &'source BoundCase<'raw>,
    record: &'record WorkflowExchangeRecord,
    checked_predicates: usize,
}

/// One explicitly issued record-check attempt. Its context stays borrowed
/// from the genuine compiler result, and its first error moves into stable
/// state. It neither clones nor replaces the caller's cumulative owners.
///
/// This post-receive component does not itself govern request serialization,
/// exchanges or report inventory. The selected runner must retain an attempt
/// across those effects and check failure before starting subsequent work.
pub(super) struct WorkflowRecordCheckAttempt<'context, 'compiled, 'case, 'sources, 'raw, 'supplied>
{
    context: &'context WorkflowReportContext<'compiled, 'case, 'sources, 'raw, 'supplied>,
    fault: Option<WorkflowRecordError>,
}

impl<'compiled, 'case, 'sources, 'raw, 'supplied>
    WorkflowReportContext<'compiled, 'case, 'sources, 'raw, 'supplied>
{
    pub(super) fn record_attempt(
        &self,
    ) -> WorkflowRecordCheckAttempt<'_, 'compiled, 'case, 'sources, 'raw, 'supplied> {
        WorkflowRecordCheckAttempt {
            context: self,
            fault: None,
        }
    }
}

impl<'case, 'raw> WorkflowRecordCheckAttempt<'_, '_, 'case, '_, 'raw, '_> {
    pub(super) fn check_record<'attempt, 'record>(
        &'attempt mut self,
        record: &'record WorkflowExchangeRecord,
        decoder: &mut Decoder,
        comparison: &mut CompareOwner,
    ) -> Result<WorkflowRecordComparison<'case, 'record, 'raw>, &'attempt WorkflowRecordError> {
        if self.fault.is_none() {
            match self.context.check_record(record, decoder, comparison) {
                Ok(compared) => return Ok(compared),
                Err(error) => self.fault = Some(error),
            }
        }
        // Already-failed attempts return the same borrowed value without
        // consulting a Decoder, comparison owner, source or record payload.
        Err(self
            .fault
            .as_ref()
            .expect("failed record attempt retains its first error"))
    }
}

fn envelope<T>(fault: WorkflowEnvelopeFault) -> Result<T, WorkflowRecordError> {
    Err(WorkflowRecordError::Envelope(fault))
}

fn equal_text(left: &str, right: &str, decoder: &mut Decoder) -> Result<bool, WorkflowRecordError> {
    let Some(bytes) = left.len().checked_add(right.len()) else {
        return envelope(WorkflowEnvelopeFault::SizeOverflow);
    };
    decoder.bytes(bytes)?;
    Ok(left == right)
}

fn request_id(
    document: &Document,
    decoder: &mut Decoder,
    fault: WorkflowEnvelopeFault,
) -> Result<RequestId, WorkflowRecordError> {
    decoder.ready()?;
    let Document::Number(number) = document else {
        return envelope(fault);
    };
    // Reuse the actual ID domain's digit-only checked u64 parser, with the
    // selected transport's stricter positive constraint. Exponents, signs and
    // negative zero cannot become a correlated canonical ID through rounding.
    decoder.bytes(number.as_str().len())?;
    let id = RequestId::parse(number.as_str()).map_err(|_| WorkflowRecordError::Envelope(fault))?;
    if id.get() == 0 {
        return envelope(fault);
    }
    Ok(id)
}

fn raw_input<'raw>(
    request: &'raw RawValue,
    decoder: &mut Decoder,
) -> Result<&'raw RawValue, WorkflowRecordError> {
    for (key, value) in decoder.raw_members(request)? {
        if equal_text(&key, "input", decoder)? {
            return Ok(value);
        }
    }
    envelope(WorkflowEnvelopeFault::Input)
}

impl<'case, 'raw> WorkflowReportContext<'_, 'case, '_, 'raw, '_> {
    pub(super) fn check_record<'record>(
        &self,
        record: &'record WorkflowExchangeRecord,
        decoder: &mut Decoder,
        comparison: &mut CompareOwner,
    ) -> Result<WorkflowRecordComparison<'case, 'record, 'raw>, WorkflowRecordError> {
        // Existing caller comparison faults precede ALL new Decoder work.
        // Decoder retains its own policy/error semantics; no owner is reset,
        // cloned, replaced or constructed from saved limits/peer metadata.
        comparison
            .ready()
            .map_err(WorkflowRecordError::Observation)?;
        decoder.ready()?;
        let (request, request_raw) = decoder.literal_with_raw(record.sent_payload())?;
        let fields = Fields::new(
            &request,
            &[
                "id",
                "op",
                "suite",
                "contractVersion",
                "format",
                "runIndex",
                "input",
            ],
            decoder,
        )?;
        let id = request_id(
            fields.document("id", decoder)?,
            decoder,
            WorkflowEnvelopeFault::RequestId,
        )?;
        for (field, expected, fault) in [
            ("suite", "workbench", WorkflowEnvelopeFault::Suite),
            (
                "contractVersion",
                "0.1.0-draft.30",
                WorkflowEnvelopeFault::Version,
            ),
            ("format", "json", WorkflowEnvelopeFault::Format),
        ] {
            let actual = string(fields.document(field, decoder)?, decoder)?;
            if !equal_text(actual, expected, decoder)? {
                return envelope(fault);
            }
        }
        let role = match self.paired().run() {
            PairedRun::Client { .. } => "model-originals-client",
            PairedRun::Server { .. } => "model-originals-server",
        };
        let actual_role = string(fields.document("op", decoder)?, decoder)?;
        if !equal_text(actual_role, role, decoder)? {
            return envelope(WorkflowEnvelopeFault::Role);
        }
        let run = fields.field::<super::input::Count>("runIndex", decoder)?;
        if usize::try_from(run.0).ok() != Some(self.paired().run_index()) {
            return envelope(WorkflowEnvelopeFault::RunIndex);
        }
        if !equal_text(
            raw_input(request_raw, decoder)?.get(),
            self.input_raw().get(),
            decoder,
        )? {
            return envelope(WorkflowEnvelopeFault::Input);
        }

        let (reply, _) = decoder.literal_with_raw(record.received_payload())?;
        let fields = Fields::new(&reply, &["id", "status", "value"], decoder)?;
        let reply_id = request_id(
            fields.document("id", decoder)?,
            decoder,
            WorkflowEnvelopeFault::ReplyId,
        )?;
        if reply_id != id {
            return envelope(WorkflowEnvelopeFault::Correlation);
        }
        let status = string(fields.document("status", decoder)?, decoder)?;
        if !equal_text(status, "ok", decoder)? {
            return envelope(WorkflowEnvelopeFault::Status);
        }
        let actual = observed::Observation::decode(fields.document("value", decoder)?, decoder)?;
        let compared = self
            .check_observation(&actual, comparison)
            .map_err(WorkflowRecordError::Observation)?;
        Ok(WorkflowRecordComparison {
            case: self.case(),
            record,
            checked_predicates: compared.checked_predicates(),
        })
    }
}
