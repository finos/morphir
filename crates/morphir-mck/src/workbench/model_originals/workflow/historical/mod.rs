//! Strict historical client operands, separate from current workflow schemas.
//! Preserved schema receipts identify the exact v10/v11 vocabulary. Common
//! children remain typed; no current root/version/ledger policy is invented.
use super::pairing::{ClientPairView, PairError};
use super::*;
use serde_json::value::RawValue;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum HistoricalExpectedVersion {
    AuthorCandidate10,
    AuthorCandidate11,
}
impl HistoricalExpectedVersion {
    pub(super) fn as_str(self) -> &'static str {
        match self {
            Self::AuthorCandidate10 => "author-candidate-10",
            Self::AuthorCandidate11 => "author-candidate-11",
        }
    }
}
impl Decode for HistoricalExpectedVersion {
    fn decode(
        value: &crate::json::strict::Document,
        owner: &mut Decoder,
    ) -> Result<Self, DecodeError> {
        match string(value, owner)? {
            "author-candidate-10" => Ok(Self::AuthorCandidate10),
            "author-candidate-11" => Ok(Self::AuthorCandidate11),
            _ => Err(DecodeError::Shape("supported historical expected version")),
        }
    }
}
#[derive(Debug)]
pub(super) enum HistoricalError {
    Decode(DecodeError),
    Pair(PairError),
}
impl From<DecodeError> for HistoricalError {
    fn from(e: DecodeError) -> Self {
        Self::Decode(e)
    }
}
impl From<PairError> for HistoricalError {
    fn from(e: PairError) -> Self {
        Self::Pair(e)
    }
}

use input::{
    LimitsCorpusBytes, LimitsEvents, LimitsEvidenceBytes, LimitsInputBytes,
    LimitsObservationsBytes, LimitsReportBytes,
};
record! { HistoricalLimits11 {
        actions: Count => "actions",
        corpus_bytes: LimitsCorpusBytes => "corpusBytes",
        events: LimitsEvents => "events",
        evidence_bytes: LimitsEvidenceBytes => "evidenceBytes",
        expanded_decoded_and_read_bytes: Count => "expandedDecodedAndReadBytes",
        expanded_wire_bytes: Count => "expandedWireBytes",
        input_bytes: LimitsInputBytes => "inputBytes",
        metadata_bytes: Count => "metadataBytes",
        observations_bytes: LimitsObservationsBytes => "observationsBytes",
        observer_byte_visits: Count => "observerByteVisits",
        report_bytes: LimitsReportBytes => "reportBytes",
} }
record! { HistoricalClientScenario { limits:HistoricalLimits11=>"limits", origin:input::PacketRef=>"origin", runs:Items<input::Run,1,2> =>"runs" } }
use domain::*;
literal! { HistoricalClientRole => "model-originals-client" }
record! { HistoricalClientExpected {
        bindings: Items<ExpectedBinding, 0, 8192> => "bindings",
        byte_sources: Items<ExpectedByteSource, 0, 4096> => "byteSources",
        checks: Items<ExpectedClientCheck, 1, 8192> => "checks",
        commentary: Items<Text<0, 16384>, 0, 8192> => "commentary",
        lineage: Items<ExpectedLineage, 0, 100000> => "lineage",
        origin: PacketRef => "origin",
        outcome: ExpectedWorkflowModelOriginalsClientOutcome => "outcome",
        qualification: ExpectedWorkflowModelOriginalsClientQualification => "qualification",
        rich_sources: Items<ExpectedWorkflowModelOriginalsClientRichSourcesItem, 0, 256> => "richSources",
        run_index: Natural<0, 1> => "runIndex",
        teardown: ExpectedWorkflowModelOriginalsClientTeardown => "teardown",
        trace_sources: Items<ExpectedWorkflowModelOriginalsClientTraceSourcesItem, 0, 8192> => "traceSources",

        version: HistoricalExpectedVersion => "version",
        role: HistoricalClientRole => "role",
} }

/// Raw operands borrow the caller's immutable source. Typed children own their
/// decoded backing under the SAME Decoder; no provenance is issued here.
pub(super) struct HistoricalClientOperands<'source> {
    input_raw: &'source RawValue,
    expected_raw: &'source RawValue,
    pub(super) scenario: HistoricalClientScenario,
    pub(super) expected: HistoricalClientExpected,
}
impl<'source> HistoricalClientOperands<'source> {
    pub(super) fn decode(
        input: &'source str,
        expected: &'source str,
        owner: &mut Decoder,
    ) -> Result<Self, HistoricalError> {
        let (input_document, input_raw) = owner.literal_with_raw(input)?;
        let scenario = HistoricalClientScenario::decode(&input_document, owner)?;
        let (expected_document, expected_raw) = owner.literal_with_raw(expected)?;
        let expected = HistoricalClientExpected::decode(&expected_document, owner)?;
        validate_vocabulary(&expected, owner)?;
        let operands = Self {
            input_raw,
            expected_raw,
            scenario,
            expected,
        };
        operands.paired(owner)?;
        Ok(operands)
    }
    pub(super) fn input_raw(&self) -> &'source RawValue {
        self.input_raw
    }
    pub(super) fn expected_raw(&self) -> &'source RawValue {
        self.expected_raw
    }
    pub(super) fn paired(
        &self,
        owner: &mut Decoder,
    ) -> Result<ClientPairView<'_>, HistoricalError> {
        ClientPairView::historical(&self.scenario, &self.expected, owner).map_err(Into::into)
    }
}

/// These restrictions apply only at typed historical vocabulary positions.
/// RawJson is never traversed or interpreted by this validation.
fn validate_vocabulary(
    e: &HistoricalClientExpected,
    owner: &mut Decoder,
) -> Result<(), DecodeError> {
    let version = e.version;
    for check in &e.checks.0 {
        owner.bytes(std::mem::size_of::<ExpectedClientCheck>())?;
        match check {
            ExpectedClientCheck::PortCounts { effect_kind, .. } => {
                validate_effect(effect_kind, version, owner)?
            }
            ExpectedClientCheck::CoreResult {
                effect, projection, ..
            } => {
                validate_effect(&effect.kind, version, owner)?;
                owner.bytes(std::mem::size_of::<ExpectedCoreProjection>())?;
                if version == HistoricalExpectedVersion::AuthorCandidate10
                    && matches!(projection, ExpectedCoreProjection::LocalEvaluation { .. })
                {
                    return Err(DecodeError::Shape("historical core projection"));
                }
            }
            ExpectedClientCheck::ExecutionReceipt { effect, .. } => {
                validate_effect(&effect.kind, version, owner)?
            }
            ExpectedClientCheck::LocalExplorerState { inspection, .. } => {
                if let ExpectedClientCheckLocalExplorerStateInspection::ActualInspectionResult {
                    effect,
                    ..
                } = inspection
                {
                    validate_effect(&effect.kind, version, owner)?
                }
            }
            ExpectedClientCheck::LocalEvaluationState { result, .. }
                if version == HistoricalExpectedVersion::AuthorCandidate11 =>
            {
                if let ExpectedClientCheckLocalEvaluationStateResult::ActualCoreResult {
                    effect,
                    ..
                } = result
                {
                    validate_effect(&effect.kind, version, owner)?
                }
            }
            ExpectedClientCheck::ModelOutputCleared { .. }
                if version == HistoricalExpectedVersion::AuthorCandidate11 => {}
            ExpectedClientCheck::PortTrace { .. }
            | ExpectedClientCheck::OwnerAbsent { .. }
            | ExpectedClientCheck::VerifiedOwner { .. }
            | ExpectedClientCheck::CurrentOpening { .. }
            | ExpectedClientCheck::CurrentModel { .. }
            | ExpectedClientCheck::Download { .. }
            | ExpectedClientCheck::Archive { .. }
            | ExpectedClientCheck::RichOwner { .. }
            | ExpectedClientCheck::Navigation { .. }
            | ExpectedClientCheck::CaptureCleanup { .. }
            | ExpectedClientCheck::ExecutionOwner { .. } => {}
            _ => return Err(DecodeError::Shape("historical client check")),
        }
    }
    for trace in &e.trace_sources.0 {
        owner.bytes(std::mem::size_of_val(trace))?;
        for event in &trace.events.0 {
            owner.bytes(std::mem::size_of::<ExpectedTraceEvent>())?;
            let effect = match event {
                ExpectedTraceEvent::Pending { effect, .. }
                | ExpectedTraceEvent::PickerInputSignal { effect, .. }
                | ExpectedTraceEvent::CancellationRequested { effect, .. }
                | ExpectedTraceEvent::PreparedCoreResult { effect, .. }
                | ExpectedTraceEvent::PromiseResolved { effect, .. }
                | ExpectedTraceEvent::PromiseRejected { effect, .. }
                | ExpectedTraceEvent::CallbackDelivered { effect, .. }
                | ExpectedTraceEvent::CallbackRetired { effect, .. }
                | ExpectedTraceEvent::PublicationDisposition { effect, .. }
                | ExpectedTraceEvent::HeldResultRetired { effect, .. }
                | ExpectedTraceEvent::WorkStarted { effect, .. }
                | ExpectedTraceEvent::WorkExited { effect, .. } => effect,
                ExpectedTraceEvent::LateSignal {
                    effect,
                    causal_source,
                    ..
                } => {
                    owner.bytes(std::mem::size_of_val(causal_source))?;
                    if let LateSignalSource::FileReadCompletion { effect } = causal_source {
                        validate_effect(&effect.kind, version, owner)?
                    }
                    effect
                }
            };
            validate_effect(&effect.kind, version, owner)?;
        }
    }
    for lineage in &e.lineage.0 {
        owner.bytes(std::mem::size_of::<ExpectedLineageTreatment>())?;
        match &lineage.treatment {
            ExpectedLineageTreatment::Compared { .. }
            | ExpectedLineageTreatment::Commentary { .. }
            | ExpectedLineageTreatment::Unresolved { .. }
            | ExpectedLineageTreatment::ComparedByDecision {
                decision: ExpectedLineageTreatmentComparedByDecisionDecision::MorphirU3f6,
                ..
            } => {}
            _ => return Err(DecodeError::Shape("historical lineage treatment")),
        }
    }
    Ok(())
}
fn validate_effect(
    kind: &EffectKind,
    version: HistoricalExpectedVersion,
    owner: &mut Decoder,
) -> Result<(), DecodeError> {
    owner.bytes(std::mem::size_of::<EffectKind>())?;
    match kind {
        EffectKind::Picker
        | EffectKind::FileRead
        | EffectKind::NativeCapture
        | EffectKind::Initialize
        | EffectKind::Capture
        | EffectKind::Inventory
        | EffectKind::ReadOriginal
        | EffectKind::ReadProjection
        | EffectKind::Release
        | EffectKind::Digest
        | EffectKind::Inspection
        | EffectKind::ExecutionSubmit
        | EffectKind::ExecutionObserve
        | EffectKind::ExecutionRelease => Ok(()),
        EffectKind::LocalEvaluation if version == HistoricalExpectedVersion::AuthorCandidate11 => {
            Ok(())
        }
        _ => Err(DecodeError::Shape("historical effect kind")),
    }
}

#[derive(Debug, Clone, Copy)]
pub(super) enum LedgerAllowancesRef<'a> {
    Present(&'a input::Limits),
    AbsentHistorical(HistoricalExpectedVersion),
}
#[derive(Debug, Clone, Copy)]
pub(super) enum ScenarioRef<'a> {
    Current(&'a input::Scenario),
    Historical(&'a HistoricalClientScenario, HistoricalExpectedVersion),
}
impl<'a> ScenarioRef<'a> {
    pub(super) fn same_owner(self, other: Self) -> bool {
        match (self, other) {
            (Self::Current(a), Self::Current(b)) => std::ptr::eq(a, b),
            (Self::Historical(a, av), Self::Historical(b, bv)) => av == bv && std::ptr::eq(a, b),
            _ => false,
        }
    }
    pub(super) fn origin(self) -> &'a input::PacketRef {
        match self {
            Self::Current(s) => &s.origin,
            Self::Historical(s, _) => &s.origin,
        }
    }
    pub(super) fn runs(self) -> &'a [input::Run] {
        match self {
            Self::Current(s) => &s.runs.0,
            Self::Historical(s, _) => &s.runs.0,
        }
    }
    pub(super) fn current(self) -> Option<&'a input::Scenario> {
        match self {
            Self::Current(s) => Some(s),
            Self::Historical(..) => None,
        }
    }
    pub(super) fn ledger_allowances(self) -> LedgerAllowancesRef<'a> {
        match self {
            Self::Current(s) => LedgerAllowancesRef::Present(&s.limits),
            Self::Historical(_, v) => LedgerAllowancesRef::AbsentHistorical(v),
        }
    }
}

/// Shared child borrows, never a manufactured current ExpectedWorkflow root.
pub(super) struct ClientExpectedBody<'a> {
    pub(super) bindings: &'a Items<ExpectedBinding, 0, 8192>,
    pub(super) byte_sources: &'a Items<ExpectedByteSource, 0, 4096>,
    pub(super) checks: &'a Items<ExpectedClientCheck, 1, 8192>,
    pub(super) commentary: &'a Items<Text<0, 16384>, 0, 8192>,
    pub(super) lineage: &'a Items<ExpectedLineage, 0, 100000>,
    pub(super) origin: &'a PacketRef,
    pub(super) outcome: &'a ExpectedWorkflowModelOriginalsClientOutcome,
    pub(super) qualification: &'a ExpectedWorkflowModelOriginalsClientQualification,
    pub(super) rich_sources: &'a Items<ExpectedWorkflowModelOriginalsClientRichSourcesItem, 0, 256>,
    pub(super) run_index: &'a Natural<0, 1>,
    pub(super) teardown: &'a ExpectedWorkflowModelOriginalsClientTeardown,
    pub(super) trace_sources:
        &'a Items<ExpectedWorkflowModelOriginalsClientTraceSourcesItem, 0, 8192>,
}
pub(super) struct ClientExpectedRef<'a> {
    body: ClientExpectedBody<'a>,
    version: &'static str,
}
impl<'a> ClientExpectedRef<'a> {
    pub(super) fn historical(e: &'a HistoricalClientExpected) -> Self {
        Self {
            body: ClientExpectedBody {
                bindings: &e.bindings,
                byte_sources: &e.byte_sources,
                checks: &e.checks,
                commentary: &e.commentary,
                lineage: &e.lineage,
                origin: &e.origin,
                outcome: &e.outcome,
                qualification: &e.qualification,
                rich_sources: &e.rich_sources,
                run_index: &e.run_index,
                teardown: &e.teardown,
                trace_sources: &e.trace_sources,
            },
            version: e.version.as_str(),
        }
    }
    pub(super) fn current(e: &'a domain::ExpectedWorkflow) -> Result<Self, PairError> {
        match e {
            domain::ExpectedWorkflow::ModelOriginalsClient {
                bindings,
                byte_sources,
                checks,
                commentary,
                lineage,
                origin,
                outcome,
                qualification,
                rich_sources,
                run_index,
                teardown,
                trace_sources,
                ..
            } => Ok(Self {
                body: ClientExpectedBody {
                    bindings,
                    byte_sources,
                    checks,
                    commentary,
                    lineage,
                    origin,
                    outcome,
                    qualification,
                    rich_sources,
                    run_index,
                    teardown,
                    trace_sources,
                },
                version: "author-candidate-17",
            }),
            _ => Err(PairError::Role),
        }
    }
    pub(super) fn body(&self) -> &ClientExpectedBody<'a> {
        &self.body
    }
    pub(super) fn version(&self) -> &'static str {
        self.version
    }
}

/// Eleven authored values borrowed from their actual owning operand.
pub(super) struct CommonLimitsRef<'a> {
    pub(super) actions: &'a Count,
    pub(super) corpus_bytes: &'a LimitsCorpusBytes,
    pub(super) events: &'a LimitsEvents,
    pub(super) evidence_bytes: &'a LimitsEvidenceBytes,
    pub(super) expanded_decoded_and_read_bytes: &'a Count,
    pub(super) expanded_wire_bytes: &'a Count,
    pub(super) input_bytes: &'a LimitsInputBytes,
    pub(super) metadata_bytes: &'a Count,
    pub(super) observations_bytes: &'a LimitsObservationsBytes,
    pub(super) observer_byte_visits: &'a Count,
    pub(super) report_bytes: &'a LimitsReportBytes,
}
impl<'a> ScenarioRef<'a> {
    pub(super) fn common_limits(self) -> CommonLimitsRef<'a> {
        match self {
            Self::Current(s) => CommonLimitsRef {
                actions: &s.limits.actions,
                corpus_bytes: &s.limits.corpus_bytes,
                events: &s.limits.events,
                evidence_bytes: &s.limits.evidence_bytes,
                expanded_decoded_and_read_bytes: &s.limits.expanded_decoded_and_read_bytes,
                expanded_wire_bytes: &s.limits.expanded_wire_bytes,
                input_bytes: &s.limits.input_bytes,
                metadata_bytes: &s.limits.metadata_bytes,
                observations_bytes: &s.limits.observations_bytes,
                observer_byte_visits: &s.limits.observer_byte_visits,
                report_bytes: &s.limits.report_bytes,
            },
            Self::Historical(s, _) => CommonLimitsRef {
                actions: &s.limits.actions,
                corpus_bytes: &s.limits.corpus_bytes,
                events: &s.limits.events,
                evidence_bytes: &s.limits.evidence_bytes,
                expanded_decoded_and_read_bytes: &s.limits.expanded_decoded_and_read_bytes,
                expanded_wire_bytes: &s.limits.expanded_wire_bytes,
                input_bytes: &s.limits.input_bytes,
                metadata_bytes: &s.limits.metadata_bytes,
                observations_bytes: &s.limits.observations_bytes,
                observer_byte_visits: &s.limits.observer_byte_visits,
                report_bytes: &s.limits.report_bytes,
            },
        }
    }
}

#[cfg(test)]
mod tests;

impl<'a> From<&'a input::Scenario> for ScenarioRef<'a> {
    fn from(s: &'a input::Scenario) -> Self {
        Self::Current(s)
    }
}
