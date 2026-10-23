//! Source-bound factual lifecycle comparison inside the shared checker.
//! This proves consistency of literal evidence, never actual producer execution,
//! protocol transfer, semantic ownership or discharge of blocked obligations.
use super::{CompareOwner, CompareResource, ObservationError};
use crate::workbench::model_originals::effects::{
    EffectLedgerStorageCost, FundedEffectLedgerError,
};
use crate::workbench::model_originals::workflow::{
    Decoder, UniqueKey,
    compile::DefinitionOrigin,
    domain,
    expansion::{ExpansionError, ExpansionOwner},
    input, observed,
    pairing::PairedRun,
    scope::{RunKey, ScopeKey, SourcePosition, SubjectRoles},
    source_compile::CompiledSourceCase,
};
use crate::workbench::model_originals::{
    self as protocol, EffectEvent, EffectKind, EffectLedger, EffectLedgerError, EffectLedgerLimits,
    EffectPort, WorkOwner,
};
use std::{borrow::Cow, mem::size_of};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum LifecycleFault {
    Role,
    Source,
    Phase,
    Input,
    Reply,
    RawJson,
    Length,
    Prefix,
    Pending,
    Prepared,
    HeldBytes,
    Action,
    Work,
    Counts,
    Limits,
    Allocation,
    Decode,
    DecodeWork(super::super::OperandResource),
    UnjoinedInput,
    UnjoinedReply,
    UnjoinedPublication,
    Expansion(ExpansionError),
    Ledger(EffectLedgerError),
}
fn fail<T>(
    owner: &mut CompareOwner,
    event: usize,
    kind: LifecycleFault,
) -> Result<T, ObservationError> {
    owner.refuse(ObservationError::Lifecycle { event, kind })
}
fn require(
    owner: &mut CompareOwner,
    index: usize,
    yes: bool,
    kind: LifecycleFault,
) -> Result<(), ObservationError> {
    if yes {
        Ok(())
    } else {
        fail(owner, index, kind)
    }
}
fn expansion<T>(
    owner: &mut CompareOwner,
    result: Result<T, ExpansionError>,
) -> Result<T, ObservationError> {
    result.map_err(|kind| {
        *owner.fault.get_or_insert(ObservationError::Lifecycle {
            event: 0,
            kind: LifecycleFault::Expansion(kind),
        })
    })
}
fn decoding<T>(
    owner: &mut CompareOwner,
    result: Result<T, super::super::DecodeError>,
) -> Result<T, ObservationError> {
    result.map_err(|error| {
        let kind = match error {
            super::super::DecodeError::Work(kind) => LifecycleFault::DecodeWork(kind),
            _ => LifecycleFault::Decode,
        };
        *owner
            .fault
            .get_or_insert(ObservationError::Lifecycle { event: 0, kind })
    })
}
struct LifecycleMetadata {
    limit: usize,
    used: usize,
}
impl LifecycleMetadata {
    fn charge(
        &mut self,
        cost: EffectLedgerStorageCost,
        decoder: &mut Decoder,
        expanded: &mut ExpansionOwner,
        owner: &mut CompareOwner,
    ) -> Result<(), ObservationError> {
        owner.ready()?;
        let next = self
            .used
            .checked_add(cost.bytes)
            .ok_or(ObservationError::SizeOverflow)?;
        require(owner, 0, next <= self.limit, LifecycleFault::Limits)?;
        decoding(owner, decoder.bytes(cost.work_bytes))?;
        decoding(owner, decoder.slots(cost.slots))?;
        expansion(owner, expanded.measure_metadata(cost.bytes, cost.slots))?;
        expansion(owner, expanded.measure_metadata_work(cost.visits))?;
        owner.charge(CompareResource::StructuralVisits, cost.visits)?;
        self.used = next;
        Ok(())
    }
}
fn funded<T>(
    result: Result<T, FundedEffectLedgerError<ObservationError>>,
    owner: &mut CompareOwner,
    index: usize,
) -> Result<T, ObservationError> {
    match result {
        Ok(value) => Ok(value),
        Err(FundedEffectLedgerError::Funding(error)) => owner.refuse(error),
        Err(FundedEffectLedgerError::Ledger(error)) => {
            fail(owner, index, LifecycleFault::Ledger(error))
        }
    }
}
fn length(frame: &input::Frame, owner: &mut CompareOwner) -> Result<usize, ObservationError> {
    owner.visit()?;
    let mut total = 0usize;
    let mut add = |text: &str, count: u64| {
        let count = usize::try_from(count).map_err(|_| ObservationError::SizeOverflow)?;
        total = text
            .len()
            .checked_mul(count)
            .and_then(|n| total.checked_add(n))
            .filter(|n| *n <= isize::MAX as usize)
            .ok_or(ObservationError::SizeOverflow)?;
        Ok::<_, ObservationError>(())
    };
    match frame {
        input::Frame::Literal { text } => add(&text.0, 1)?,
        input::Frame::Segments { parts } => {
            for part in &parts.0 {
                owner.visit()?;
                match part {
                    input::FramePart::Literal { text } => add(&text.0, 1)?,
                    input::FramePart::Repeat { text, count } => add(&text.0, count.0)?,
                }
            }
        }
    }
    owner.ready()?;
    Ok(total)
}
fn materialize<'a>(
    frame: &'a input::Frame,
    decoder: &mut Decoder,
    expanded: &mut ExpansionOwner,
    owner: &mut CompareOwner,
) -> Result<Cow<'a, str>, ObservationError> {
    let size = length(frame, owner)?;
    expansion(owner, expanded.measure_materialization_frame(frame))?;
    decoding(owner, decoder.bytes(size))?;
    match frame {
        input::Frame::Literal { text } => Ok(Cow::Borrowed(&text.0)),
        input::Frame::Segments { parts } => {
            let mut text = String::new();
            if text.try_reserve_exact(size).is_err() {
                return fail(owner, 0, LifecycleFault::Allocation);
            }
            for part in &parts.0 {
                match part {
                    input::FramePart::Literal { text: part } => text.push_str(&part.0),
                    input::FramePart::Repeat { text: part, count } => {
                        if !part.0.is_empty() {
                            for _ in 0..count.0 {
                                text.push_str(&part.0);
                            }
                        }
                    }
                }
            }
            Ok(Cow::Owned(text))
        }
    }
}
fn effect(record: &observed::EffectRecord) -> &observed::EffectRef {
    use observed::EffectRecord::*;
    match record {
        Pending { effect, .. }
        | PickerInputSignal { effect, .. }
        | CancellationRequested { effect, .. }
        | WorkStarted { effect, .. }
        | WorkExited { effect, .. }
        | PreparedCoreResult { effect, .. }
        | PromiseResolved { effect, .. }
        | PromiseRejected { effect, .. }
        | CallbackDelivered { effect, .. }
        | CallbackRetired { effect, .. }
        | LateSignal { effect, .. }
        | PublicationDisposition { effect, .. }
        | HeldResultRetired { effect, .. } => effect,
    }
}
fn kind(value: &observed::EffectKind) -> EffectKind {
    use observed::EffectKind as O;
    match value {
        O::Picker => EffectKind::Picker,
        O::FileRead => EffectKind::FileRead,
        O::NativeCapture => EffectKind::NativeCapture,
        O::Initialize => EffectKind::Initialize,
        O::Capture => EffectKind::Capture,
        O::Inventory => EffectKind::Inventory,
        O::ReadOriginal => EffectKind::ReadOriginal,
        O::ReadProjection => EffectKind::ReadProjection,
        O::Release => EffectKind::Release,
        O::Digest => EffectKind::Digest,
        O::Inspection => EffectKind::Inspection,
        O::ExecutionSubmit => EffectKind::ExecutionSubmit,
        O::ExecutionObserve => EffectKind::ExecutionObserve,
        O::ExecutionRelease => EffectKind::ExecutionRelease,
        O::LocalEvaluation => EffectKind::LocalEvaluation,
        O::Catalog => EffectKind::Catalog,
        O::NativeInvoke => EffectKind::NativeInvoke,
        O::ManifestFetch => EffectKind::ManifestFetch,
        O::WorkspaceOpen => EffectKind::WorkspaceOpen,
    }
}
fn roles(value: &observed::EffectKind) -> SubjectRoles {
    use observed::EffectKind as O;
    match value {
        O::Catalog => SubjectRoles::CatalogRuntime,
        O::Initialize => SubjectRoles::Initialize,
        O::NativeInvoke => SubjectRoles::NativeRuntime,
        O::ExecutionSubmit | O::ExecutionObserve | O::ExecutionRelease => SubjectRoles::Execution,
        O::LocalEvaluation => SubjectRoles::LocalEvaluation,
        O::Picker
        | O::FileRead
        | O::NativeCapture
        | O::Capture
        | O::Inventory
        | O::ReadOriginal
        | O::ReadProjection
        | O::Release
        | O::Digest
        | O::Inspection
        | O::ManifestFetch
        | O::WorkspaceOpen => SubjectRoles::Opening,
    }
}
fn input_ref(
    expected: &input::EffectRef,
    actual: &observed::EffectRef,
    owner: &mut CompareOwner,
) -> Result<bool, ObservationError> {
    Ok(owner.same(&expected.attempt, &actual.attempt)?
        && expected.kind.key() == actual.kind.key()
        && expected.ordinal.0 == actual.ordinal.0)
}
fn selected_route(
    actions: &[input::ClientAction],
    effect: &observed::EffectRef,
    owner: &mut CompareOwner,
) -> Result<bool, ObservationError> {
    use input::ClientAction as A;
    use observed::EffectKind as K;
    for action in actions {
        owner.visit()?;
        let issuer = match (&effect.kind, action) {
            (
                K::Picker | K::FileRead,
                A::StartImport {
                    attempt,
                    via: input::ClientActionStartImportVia::Browser,
                    ..
                },
            ) => Some(attempt),
            (
                K::NativeCapture,
                A::StartImport {
                    attempt,
                    via: input::ClientActionStartImportVia::Native,
                    ..
                }
                | A::BeginNativeOpenProject { attempt, .. },
            ) => Some(attempt),
            (
                K::Digest | K::Inspection,
                A::StartImport { attempt, .. } | A::BeginNativeOpenProject { attempt, .. },
            ) => Some(attempt),
            (
                K::ManifestFetch
                | K::Initialize
                | K::WorkspaceOpen
                | K::Capture
                | K::Inventory
                | K::ReadOriginal
                | K::ReadProjection
                | K::Release
                | K::Digest
                | K::Inspection,
                A::StartConnected { attempt, .. } | A::BeginConnectedOpening { attempt, .. },
            ) => Some(attempt),
            (K::Initialize | K::Catalog, A::InitializeExecutionRuntime { attempt }) => {
                Some(attempt)
            }
            (K::Catalog, A::BeginNativeChoose { runtime, .. }) => Some(runtime),
            (
                K::NativeInvoke,
                A::BeginNativeInitialize { runtime, .. }
                | A::BeginNativeChoose { runtime, .. }
                | A::BeginNativeOpenProject { runtime, .. }
                | A::DisposeNativeRuntime { runtime },
            ) => Some(runtime),
            (
                K::ExecutionSubmit | K::ExecutionObserve | K::ExecutionRelease,
                A::SubmitExecution { execution, .. },
            ) => Some(execution),
            (K::LocalEvaluation, A::BeginLocalEvaluation { attempt, .. }) => Some(attempt),
            _ => None,
        };
        if let Some(issuer) = issuer {
            if owner.same(issuer, &effect.attempt)? {
                return Ok(true);
            }
        }
    }
    Ok(false)
}
fn cause(value: &observed::CancellationCause) -> protocol::CancellationCause {
    use observed::CancellationCause as O;
    match value {
        O::CancelOpening => protocol::CancellationCause::CancelOpening,
        O::CloseCurrentModel => protocol::CancellationCause::CloseCurrentModel,
        O::CloseModel => protocol::CancellationCause::CloseModel,
        O::Replacement => protocol::CancellationCause::Replacement,
        O::Teardown => protocol::CancellationCause::Teardown,
    }
}
fn record_frame(record: &observed::EffectRecord) -> Option<&input::Frame> {
    match record {
        observed::EffectRecord::PreparedCoreResult { raw_reply, .. } => Some(raw_reply),
        observed::EffectRecord::CallbackDelivered {
            actual_raw_callback_argument,
            ..
        } => Some(actual_raw_callback_argument),
        observed::EffectRecord::PromiseResolved {
            reply: input::DeliveredReply::Frame { value },
            ..
        } => Some(value),
        observed::EffectRecord::LateSignal {
            actual_signal: input::DeliveredReply::Frame { value },
            ..
        } => Some(value),
        _ => None,
    }
}

/// Closed factual result, borrowing the genuine source and immutable observed
/// stream. Expanded raw replies remain owned/borrowed here after replay.
/// No constructor/Clone, runtime authority or case-complete status is exposed.
pub(in crate::workbench::model_originals::workflow) struct CheckedClientLifecycle<'source, 'actual>
{
    expected: &'source domain::ExpectedWorkflow,
    actual: &'actual observed::Observation,
    _expanded: Vec<Option<Cow<'actual, str>>>,
    observer_bytes: usize,
}
impl CheckedClientLifecycle<'_, '_> {
    #[cfg(test)]
    fn payload_comparison_bytes(&self) -> usize {
        self.observer_bytes
    }
    pub(in crate::workbench::model_originals::workflow) fn check_port_counts(
        &self,
        check: &domain::ExpectedClientCheck,
        owner: &mut CompareOwner,
    ) -> Result<(), ObservationError> {
        let observed::Observation::ModelOriginalsClient { checkpoints, .. } = self.actual else {
            unreachable!()
        };
        super::predicate(0, check, &[], &checkpoints.0, None, Some(self), owner)
    }
    pub(super) fn compare_port_counts(
        &self,
        check: &domain::ExpectedClientCheck,
        owner: &mut CompareOwner,
    ) -> Result<(), ObservationError> {
        owner.ready()?;
        let domain::ExpectedWorkflow::ModelOriginalsClient { checks, .. } = self.expected else {
            return fail(owner, 0, LifecycleFault::Role);
        };
        let mut original = false;
        for candidate in &checks.0 {
            owner.visit()?;
            if std::ptr::eq(candidate, check) {
                original = true;
            }
        }
        require(owner, 0, original, LifecycleFault::Source)?;
        let domain::ExpectedClientCheck::PortCounts {
            attempts,
            effect_kind,
            expected,
            ..
        } = check
        else {
            return fail(owner, 0, LifecycleFault::Counts);
        };
        let observed::Observation::ModelOriginalsClient { effects, .. } = self.actual else {
            unreachable!()
        };
        let mut count = 0u64;
        for record in &effects.0 {
            owner.visit()?;
            if let observed::EffectRecord::Pending { effect, .. } = record {
                if effect.kind.key() == effect_kind.key() {
                    let mut selected = false;
                    for attempt in &attempts.0 {
                        owner.visit()?;
                        if owner.same(attempt, &effect.attempt)? {
                            require(owner, 0, !selected, LifecycleFault::Counts)?;
                            selected = true;
                        }
                    }
                    if selected {
                        count = count.checked_add(1).ok_or(ObservationError::SizeOverflow)?;
                    }
                }
            }
        }
        let matched = super::number(expected, count, owner)?;
        require(owner, 0, matched, LifecycleFault::Counts)
    }
}

pub(in crate::workbench::model_originals::workflow) fn check<'source, 'actual>(
    compiled: &CompiledSourceCase<'source, '_, '_, '_>,
    actual: &'actual observed::Observation,
    decoder: &mut Decoder,
    expanded: &mut ExpansionOwner,
    owner: &mut CompareOwner,
) -> Result<CheckedClientLifecycle<'source, 'actual>, ObservationError> {
    owner.ready()?;
    match check_inner(compiled, actual, decoder, expanded, owner) {
        Ok(checked) => Ok(checked),
        Err(error) => owner.refuse(error),
    }
}
fn check_inner<'source, 'actual>(
    compiled: &CompiledSourceCase<'source, '_, '_, '_>,
    actual: &'actual observed::Observation,
    decoder: &mut Decoder,
    expanded: &mut ExpansionOwner,
    owner: &mut CompareOwner,
) -> Result<CheckedClientLifecycle<'source, 'actual>, ObservationError> {
    owner.ready()?;
    decoding(owner, decoder.ready())?;
    expansion(owner, expanded.ready())?;
    let paired = compiled.source().paired();
    let PairedRun::Client { actions, fixture } = paired.run() else {
        return fail(owner, 0, LifecycleFault::Role);
    };
    let observed::Observation::ModelOriginalsClient {
        checkpoints,
        effects,
        outbound,
        teardown,
        ..
    } = actual
    else {
        return fail(owner, 0, LifecycleFault::Role);
    };
    super::correlate_checkpoints(actions, &checkpoints.0, owner)?;
    let limits = &paired.scenario().limits;
    let convert = |n: u64| usize::try_from(n).map_err(|_| ObservationError::SizeOverflow);
    let bounds = EffectLedgerLimits::new(
        convert(limits.ledger_effect_history_entries.0)?,
        convert(limits.ledger_event_history_entries.0)?,
        convert(limits.ledger_held_result_bytes.0)?,
        convert(limits.ledger_produced_result_bytes.0)?,
        convert(limits.ledger_payload_comparison_byte_visits.0)?,
    )
    .map_err(|_| ObservationError::Lifecycle {
        event: 0,
        kind: LifecycleFault::Limits,
    })?;
    require(
        owner,
        0,
        effects.0.len() <= convert(limits.ledger_event_history_entries.0)?,
        LifecycleFault::Limits,
    )?;
    let metadata = effects
        .0
        .len()
        .checked_mul(size_of::<protocol::EffectRef>() + size_of::<Option<Cow<'_, str>>>())
        .and_then(|n| n.checked_add(size_of::<CheckedClientLifecycle<'_, '_>>()))
        .ok_or(ObservationError::SizeOverflow)?;
    let mut key_bytes = 0usize;
    for record in &effects.0 {
        owner.visit()?;
        key_bytes = key_bytes
            .checked_add(effect(record).attempt.as_str().len())
            .ok_or(ObservationError::SizeOverflow)?;
    }
    let metadata = metadata
        .checked_add(key_bytes)
        .ok_or(ObservationError::SizeOverflow)?;
    let mut metadata_owner = LifecycleMetadata {
        limit: convert(limits.metadata_bytes.0)?,
        used: 0,
    };
    metadata_owner.charge(
        EffectLedgerStorageCost {
            bytes: metadata,
            slots: effects
                .0
                .len()
                // Two vector elements plus each key's owned alias payload.
                .checked_mul(3)
                .and_then(|n| n.checked_add(1))
                .ok_or(ObservationError::SizeOverflow)?,
            work_bytes: metadata,
            visits: 1,
        },
        decoder,
        expanded,
        owner,
    )?;
    let mut keys = Vec::new();
    let mut raw = Vec::new();
    if keys.try_reserve_exact(effects.0.len()).is_err()
        || raw.try_reserve_exact(effects.0.len()).is_err()
        || keys.capacity() != effects.0.len()
        || raw.capacity() != effects.0.len()
    {
        return fail(owner, 0, LifecycleFault::Allocation);
    }
    // Bound compact Frame expansion before allocating any actual reply. These
    // are the original scenario's wire/read allowances, not fresh defaults.
    let mut wire = 0usize;
    for frame in outbound
        .0
        .iter()
        .chain(effects.0.iter().filter_map(record_frame))
    {
        wire = wire
            .checked_add(length(frame, owner)?)
            .ok_or(ObservationError::SizeOverflow)?;
        require(
            owner,
            0,
            wire <= convert(limits.expanded_wire_bytes.0)?
                && wire <= convert(limits.expanded_decoded_and_read_bytes.0)?,
            LifecycleFault::Limits,
        )?;
    }
    let mut ledger = EffectLedger::new(bounds);
    let mut port_capacity = 0usize;
    let mut work_capacity = 0usize;
    for record in &effects.0 {
        owner.visit()?;
        if matches!(record, observed::EffectRecord::Pending { .. }) {
            port_capacity += 1;
        }
        if matches!(record, observed::EffectRecord::WorkStarted { .. }) {
            work_capacity += 1;
        }
    }
    let preparation = ledger.prepare_funded_storage(port_capacity, work_capacity, |cost| {
        metadata_owner.charge(cost, decoder, expanded, owner)
    });
    funded(preparation, owner, 0)?;
    for (index, record) in effects.0.iter().enumerate() {
        owner.visit()?;
        let effect = effect(record);
        // Match the exact canonical issuer roles already used by the source
        // compiler; expected aliases and observation claims cannot issue ports.
        let mut source = None;
        for definition in compiled.aliases().definitions() {
            owner.visit()?;
            let same_run = matches!(definition.scope, ScopeKey::Run(RunKey::First))
                && paired.run_index() == 0
                || matches!(definition.scope, ScopeKey::Run(RunKey::Second))
                    && paired.run_index() == 1;
            if definition.origin == DefinitionOrigin::Input
                && same_run
                && roles(&effect.kind).candidates().contains(&definition.role)
                && owner.same(definition.alias, &effect.attempt)?
            {
                require(owner, index, source.is_none(), LifecycleFault::Source)?;
                source = Some(definition.position);
            }
        }
        let position = source.ok_or_else(|| {
            *owner.fault.get_or_insert(ObservationError::Lifecycle {
                event: index,
                kind: LifecycleFault::Source,
            })
        })?;
        let cut = checkpoint_action_cut(actions, &checkpoints.0, index, owner)?;
        require(
            owner,
            index,
            !matches!(position,SourcePosition::Action(action) if action>=cut),
            LifecycleFault::Phase,
        )?;
        let selected = selected_route(&actions[..cut], effect, owner)?;
        require(owner, index, selected, LifecycleFault::Source)?;
        keys.push(
            protocol::EffectRef::try_from_alias(
                &effect.attempt,
                kind(&effect.kind),
                convert(effect.ordinal.0)?,
            )
            .map_err(|kind| ObservationError::Lifecycle {
                event: index,
                kind: LifecycleFault::Ledger(kind),
            })?,
        );
        raw.push(match record_frame(record) {
            Some(frame) => Some(materialize(frame, decoder, expanded, owner)?),
            None => None,
        });
        if let Some(text) = raw.last().and_then(Option::as_deref) {
            if matches!(
                record,
                observed::EffectRecord::PreparedCoreResult { .. }
                    | observed::EffectRecord::CallbackDelivered { .. }
            ) {
                decoding(owner, decoder.literal_with_raw(text))?;
            }
        }
        if let observed::EffectRecord::Pending { input, port, .. } = record {
            require(
                owner,
                index,
                matches!(
                    (&effect.kind, port),
                    (
                        observed::EffectKind::Picker,
                        observed::EffectRecordPendingPort::PickerReceiveCallback
                    )
                ) || effect.kind != observed::EffectKind::Picker
                    && matches!(port, observed::EffectRecordPendingPort::Promise),
                LifecycleFault::Input,
            )?;
            match input {
                observed::EffectInput::None {} => {
                    require(
                        owner,
                        index,
                        rpc_method(&effect.kind).is_none(),
                        LifecycleFault::UnjoinedInput,
                    )?;
                }
                observed::EffectInput::OutboundFrame { index: frame } => {
                    // Outbound is one actual selected request stream. Its
                    // positions cannot be reissued as new gap-free ports.
                    for earlier in &effects.0[..index] {
                        owner.visit()?;
                        if let observed::EffectRecord::Pending {
                            input: observed::EffectInput::OutboundFrame { index: used },
                            ..
                        } = earlier
                        {
                            require(owner, index, used.0 != frame.0, LifecycleFault::Input)?;
                        }
                    }
                    let frame_index = convert(frame.0)?;
                    let frame = outbound
                        .0
                        .get(frame_index)
                        .ok_or(ObservationError::Lifecycle {
                            event: index,
                            kind: LifecycleFault::Input,
                        })?;
                    validate_rpc_input(
                        frame,
                        frame_index,
                        &effect.kind,
                        fixture,
                        decoder,
                        expanded,
                        owner,
                        index,
                        &mut ledger,
                    )?;
                }
                // These need their actual input/fixture/result correspondence;
                // a valid recipe or arbitrary JSON cannot create an issuer.
                _ => return fail(owner, index, LifecycleFault::UnjoinedInput),
            }
        }
        if let observed::EffectRecord::WorkStarted { .. } = record {
            let mut issued = false;
            for action in &actions[..cut] {
                owner.visit()?;
                match action {
                    input::ClientAction::ExecutePendingCore { effect: expected }
                    | input::ClientAction::PreparePendingCore { effect: expected } => {
                        if input_ref(expected, effect, owner)? {
                            issued = true;
                        }
                    }
                    input::ClientAction::BeginLocalEvaluation { attempt, .. } => {
                        if effect.kind == observed::EffectKind::LocalEvaluation
                            && owner.same(attempt, &effect.attempt)?
                        {
                            issued = true;
                        }
                    }
                    _ => {}
                }
            }
            require(owner, index, issued, LifecycleFault::Work)?;
        }
        validate_action(record, actions, cut, index, owner)?;
    }
    let mut next = 0usize;
    for checkpoint in &checkpoints.0 {
        let end = convert(checkpoint.event_count.0)?;
        require(
            owner,
            next,
            end >= next && end <= effects.0.len(),
            LifecycleFault::Prefix,
        )?;
        while next < end {
            let cut = checkpoint_action_cut(actions, &checkpoints.0, next, owner)?;
            replay(
                next,
                &effects.0,
                &keys,
                &raw,
                fixture,
                &actions[..cut],
                decoder,
                expanded,
                owner,
                &mut ledger,
                &mut metadata_owner,
            )?;
            next += 1;
        }
        require(
            owner,
            next,
            ledger.event_count() == end,
            LifecycleFault::Prefix,
        )?;
        compare_membership(
            checkpoint.pending_effects.0.iter(),
            ledger.pending_effects(),
            ledger.port_count(),
            owner,
            next,
            LifecycleFault::Pending,
        )?;
        compare_membership(
            checkpoint.prepared_core_effects.0.iter(),
            ledger.prepared_effects().map(|(effect, _)| effect),
            ledger.port_count(),
            owner,
            next,
            LifecycleFault::Prepared,
        )?;
        require(
            owner,
            next,
            checkpoint.held_core_result_bytes.0 == ledger.held_result_bytes() as u64,
            LifecycleFault::HeldBytes,
        )?;
    }
    require(owner, next, next == effects.0.len(), LifecycleFault::Prefix)?;
    if matches!(teardown, observed::HarnessTeardown::Confirmed { .. }) {
        let finished =
            ledger.finish_funded(|cost| metadata_owner.charge(cost, decoder, expanded, owner));
        funded(finished, owner, next)?;
    }
    let observer_bytes = ledger.observer_bytes();
    Ok(CheckedClientLifecycle {
        expected: paired.expected(),
        actual,
        _expanded: raw,
        observer_bytes,
    })
}
fn checkpoint_action_cut(
    actions: &[input::ClientAction],
    checkpoints: &[observed::ClientCheckpoint],
    event: usize,
    owner: &mut CompareOwner,
) -> Result<usize, ObservationError> {
    for checkpoint in checkpoints {
        owner.visit()?;
        if checkpoint.event_count.0 > event as u64 {
            for (index, action) in actions.iter().enumerate() {
                owner.visit()?;
                if let input::ClientAction::Checkpoint { name } = action {
                    if owner.same(name, &checkpoint.name)? {
                        return Ok(index);
                    }
                }
            }
        }
    }
    fail(owner, event, LifecycleFault::Prefix)
}
fn compare_membership<'a, 'b>(
    actual: impl Iterator<Item = &'a observed::EffectRef> + Clone,
    expected: impl Iterator<Item = &'b protocol::EffectRef> + Clone,
    scanned: usize,
    owner: &mut CompareOwner,
    event: usize,
    fault: LifecycleFault,
) -> Result<(), ObservationError> {
    owner.charge(CompareResource::StructuralVisits, scanned)?;
    require(
        owner,
        event,
        actual.clone().count() == expected.clone().count(),
        fault,
    )?;
    for (index, a) in actual.clone().enumerate() {
        for earlier in actual.clone().take(index) {
            owner.visit()?;
            let duplicate = owner.same(&a.attempt, &earlier.attempt)?
                && a.kind == earlier.kind
                && a.ordinal.0 == earlier.ordinal.0;
            require(owner, event, !duplicate, fault)?;
        }
        let mut found = false;
        owner.charge(CompareResource::StructuralVisits, scanned)?;
        for b in expected.clone() {
            owner.visit()?;
            if owner.same(&a.attempt, b.attempt())?
                && kind(&a.kind) == b.kind()
                && a.ordinal.0 == b.ordinal() as u64
            {
                found = true;
            }
        }
        require(owner, event, found, fault)?;
    }
    Ok(())
}

fn validate_action(
    record: &observed::EffectRecord,
    actions: &[input::ClientAction],
    cut: usize,
    index: usize,
    owner: &mut CompareOwner,
) -> Result<(), ObservationError> {
    let (action_index, why) = match record {
        observed::EffectRecord::CancellationRequested {
            action_index,
            cause,
            ..
        }
        | observed::EffectRecord::CallbackRetired {
            action_index,
            cause,
            ..
        } => (action_index.0, cause),
        _ => return Ok(()),
    };
    let action_index = usize::try_from(action_index).map_err(|_| ObservationError::SizeOverflow)?;
    require(owner, index, action_index < cut, LifecycleFault::Action)?;
    let action = actions
        .get(action_index)
        .ok_or(ObservationError::Lifecycle {
            event: index,
            kind: LifecycleFault::Action,
        })?;
    let target = &effect(record).attempt;
    use input::ClientAction as A;
    use observed::CancellationCause as C;
    let valid = match (why, action) {
        (C::CancelOpening, A::CancelOpening { attempt }) => owner.same(attempt, target)?,
        (C::CloseCurrentModel, A::CloseCurrentModel {}) => true,
        (C::CloseModel, A::CloseModel { model })
        | (C::Replacement, A::ReplaceModel { model, .. }) => {
            let mut bound = false;
            for action in &actions[..action_index] {
                owner.visit()?;
                if let A::BindModelOwner {
                    attempt,
                    model: bound_model,
                } = action
                {
                    if owner.same(attempt, target)? && owner.same(model, bound_model)? {
                        bound = true;
                    }
                }
            }
            bound
        }
        (C::Teardown, A::DisposeConnectedOpening { pending }) => {
            let mut bound = false;
            for action in &actions[..action_index] {
                owner.visit()?;
                if let A::BeginConnectedOpening {
                    attempt,
                    pending: bound_pending,
                    ..
                } = action
                {
                    if owner.same(attempt, target)? && owner.same(pending, bound_pending)? {
                        bound = true;
                    }
                }
            }
            bound
        }
        (C::Teardown, A::DisposeNativeRuntime { runtime }) => owner.same(runtime, target)?,
        _ => false,
    };
    require(owner, index, valid, LifecycleFault::Action)
}

fn raw_json<'a>(
    source: &'a input::RawJsonSource,
    decoder: &mut Decoder,
    expanded: &mut ExpansionOwner,
    owner: &mut CompareOwner,
) -> Result<Cow<'a, str>, ObservationError> {
    let text = match source {
        input::RawJsonSource::String(raw) => {
            decoding(owner, decoder.bytes(raw.0.len()))?;
            Cow::Borrowed(raw.0.as_str())
        }
        input::RawJsonSource::Object(frame) => materialize(frame, decoder, expanded, owner)?,
    };
    decoding(owner, decoder.literal_with_raw(&text))?;
    Ok(text)
}
fn payload_credit(
    ledger: &mut EffectLedger<'_>,
    actual: usize,
    source: usize,
    owner: &mut CompareOwner,
    index: usize,
) -> Result<(), ObservationError> {
    ledger
        .preflight_payload_comparison(actual, source)
        .map_err(|kind| {
            *owner.fault.get_or_insert(ObservationError::Lifecycle {
                event: index,
                kind: LifecycleFault::Ledger(kind),
            })
        })
}
fn same_bytes(
    a: &input::Bytes,
    b: &input::Bytes,
    decoder: &mut Decoder,
    expanded: &mut ExpansionOwner,
    owner: &mut CompareOwner,
    ledger: &mut EffectLedger<'_>,
    index: usize,
) -> Result<bool, ObservationError> {
    expansion(owner, expanded.measure_materialization_bytes(a))?;
    expansion(owner, expanded.measure_materialization_bytes(b))?;
    decoding(owner, decoder.slots(2))?;
    let a = super::server::recipe(a, owner)?;
    let b = super::server::recipe(b, owner)?;
    payload_credit(ledger, a.byte_length(), b.byte_length(), owner, index)?;
    if a.byte_length() != b.byte_length() {
        return Ok(false);
    }
    // Fixed existing protocol window, reused throughout the complete stream.
    expansion(owner, expanded.measure_metadata(2 * 65536, 2))?;
    let mut left = [0u8; 65536];
    let mut right = [0u8; 65536];
    let mut offset = 0usize;
    while offset < a.byte_length() {
        owner.visit()?;
        let count = (a.byte_length() - offset).min(left.len());
        decoding(
            owner,
            decoder.bytes(count.checked_mul(2).ok_or(ObservationError::SizeOverflow)?),
        )?;
        owner.charge(
            CompareResource::ComparisonBytes,
            count.checked_mul(2).ok_or(ObservationError::SizeOverflow)?,
        )?;
        a.fill_window(offset, &mut left[..count])
            .map_err(|_| ObservationError::Lifecycle {
                event: 0,
                kind: LifecycleFault::Input,
            })?;
        b.fill_window(offset, &mut right[..count])
            .map_err(|_| ObservationError::Lifecycle {
                event: 0,
                kind: LifecycleFault::Input,
            })?;
        if left[..count] != right[..count] {
            return Ok(false);
        }
        offset += count;
    }
    Ok(true)
}
fn validate_non_core_reply(
    actual: &input::DeliveredReply,
    effect: &observed::EffectRef,
    actions: &[input::ClientAction],
    fixture: &input::ClientFixture,
    decoder: &mut Decoder,
    expanded: &mut ExpansionOwner,
    owner: &mut CompareOwner,
    index: usize,
    ledger: &mut EffectLedger<'_>,
) -> Result<(), ObservationError> {
    for action in actions {
        owner.visit()?;
        let input::ClientAction::Deliver {
            effect: source,
            reply: expected,
        } = action
        else {
            continue;
        };
        if !input_ref(source, effect, owner)? {
            continue;
        }
        use input::DeliveredReply as D;
        let same = match (expected, actual) {
            (D::Bytes { value: a }, D::Bytes { value: b }) => {
                same_bytes(a, b, decoder, expanded, owner, ledger, index)?
            }
            (D::Sha256 { value: a }, D::Sha256 { value: b }) => {
                payload_credit(ledger, a.0.len(), b.0.len(), owner, index)?;
                owner.charge(CompareResource::ComparisonBytes, 64)?;
                a == b
            }
            (D::FileSelection { file: a }, D::FileSelection { file: b }) => {
                payload_credit(ledger, a.as_str().len(), b.as_str().len(), owner, index)?;
                let mut known = false;
                for file in &fixture.files.0 {
                    owner.visit()?;
                    if owner.same(&file.alias, b)? {
                        known = true;
                    }
                }
                known && owner.same(a, b)?
            }
            (D::PickerCancelled {}, D::PickerCancelled {}) => true,
            (D::Void { operation: a }, D::Void { operation: b }) => a == b,
            (
                D::Json {
                    operation: a,
                    source: sa,
                },
                D::Json {
                    operation: b,
                    source: sb,
                },
            ) => {
                let a_raw = raw_json(sa, decoder, expanded, owner)?;
                let b_raw = raw_json(sb, decoder, expanded, owner)?;
                payload_credit(ledger, a_raw.len(), b_raw.len(), owner, index)?;
                a == b && owner.same_text(&a_raw, &b_raw)?
            }
            (
                D::Text {
                    operation: a,
                    source: sa,
                },
                D::Text {
                    operation: b,
                    source: sb,
                },
            ) => {
                let a_raw = raw_json(sa, decoder, expanded, owner)?;
                let b_raw = raw_json(sb, decoder, expanded, owner)?;
                payload_credit(ledger, a_raw.len(), b_raw.len(), owner, index)?;
                a == b && owner.same_text(&a_raw, &b_raw)?
            }
            (D::Frame { value: a }, D::Frame { value: b }) => {
                let a = materialize(a, decoder, expanded, owner)?;
                let b = materialize(b, decoder, expanded, owner)?;
                payload_credit(ledger, a.len(), b.len(), owner, index)?;
                owner.same_text(&a, &b)?
            }
            _ => false,
        };
        return require(owner, index, same, LifecycleFault::Reply);
    }
    fail(owner, index, LifecycleFault::Reply)
}

fn rpc_method(kind: &observed::EffectKind) -> Option<&'static str> {
    use observed::EffectKind as K;
    match kind {
        K::Initialize => Some("morphir.session.initialize"),
        K::WorkspaceOpen => Some("morphir.workspace.open"),
        K::Capture => Some("morphir.model-originals.capture"),
        K::Inventory => Some("morphir.model-originals.inventory"),
        K::ReadOriginal | K::ReadProjection => Some("morphir.model-originals.read"),
        K::Release => Some("morphir.model-originals.release"),
        _ => None,
    }
}
fn selected_peer<'a>(
    fixture: &'a input::ClientFixture,
    owner: &mut CompareOwner,
    index: usize,
) -> Result<&'a input::ClientFixtureLiteralPeersItem, ObservationError> {
    let input::ClientFixtureMode::Runtime { runtime } = &fixture.mode else {
        return fail(owner, index, LifecycleFault::UnjoinedInput);
    };
    let alias = match runtime {
        input::ClientRuntime::ControlledHttpExecutions { peer, .. }
        | input::ClientRuntime::ControlledModelOriginalsHttpV1 { peer, .. }
        | input::ClientRuntime::ControlledNativeWorkspaceV1 { peer, .. } => peer,
    };
    let mut found = None;
    for peer in &fixture.literal_peers.0 {
        owner.visit()?;
        if owner.same(alias, &peer.alias)? {
            require(owner, index, found.is_none(), LifecycleFault::Source)?;
            found = Some(peer);
        }
    }
    found.ok_or(ObservationError::Lifecycle {
        event: index,
        kind: LifecycleFault::UnjoinedInput,
    })
}
fn validate_rpc_input(
    frame: &input::Frame,
    frame_index: usize,
    kind: &observed::EffectKind,
    fixture: &input::ClientFixture,
    decoder: &mut Decoder,
    expanded: &mut ExpansionOwner,
    owner: &mut CompareOwner,
    index: usize,
    ledger: &mut EffectLedger<'_>,
) -> Result<(), ObservationError> {
    use super::super::{Fields, Presence, string};
    let method = rpc_method(kind).ok_or(ObservationError::Lifecycle {
        event: index,
        kind: LifecycleFault::UnjoinedInput,
    })?;
    let peer = selected_peer(fixture, owner, index)?;
    let Presence::Present(requests) = &peer.requests else {
        return fail(owner, index, LifecycleFault::UnjoinedInput);
    };
    let configured = requests
        .0
        .get(frame_index)
        .ok_or(ObservationError::Lifecycle {
            event: index,
            kind: LifecycleFault::Input,
        })?;
    let actual = materialize(frame, decoder, expanded, owner)?;
    let configured = materialize(configured, decoder, expanded, owner)?;
    payload_credit(ledger, actual.len(), configured.len(), owner, index)?;
    let same = owner.same_text(&actual, &configured)?;
    require(owner, index, same, LifecycleFault::Input)?;
    let (document, _) = decoding(owner, decoder.literal_with_raw(&actual))?;
    let fields = decoding(
        owner,
        Fields::new(&document, &["jsonrpc", "id", "method", "params"], decoder),
    )?;
    let field = decoding(owner, fields.document("method", decoder))?;
    let actual_method = decoding(owner, string(field, decoder))?;
    payload_credit(ledger, method.len(), actual_method.len(), owner, index)?;
    let same = owner.same_text(method, actual_method)?;
    require(owner, index, same, LifecycleFault::Input)?;
    let id = decoding(owner, fields.document("id", decoder))?;
    let crate::json::strict::Document::Number(id) = id else {
        return fail(owner, index, LifecycleFault::Input);
    };
    decoding(owner, decoder.bytes(id.as_str().len()))?;
    let id = protocol::RequestId::parse(id.as_str()).map_err(|_| ObservationError::Lifecycle {
        event: index,
        kind: LifecycleFault::Input,
    })?;
    require(owner, index, id.get() != 0, LifecycleFault::Input)?;
    if matches!(
        kind,
        observed::EffectKind::ReadOriginal | observed::EffectKind::ReadProjection
    ) {
        let params = decoding(owner, fields.document("params", decoder))?;
        let params = decoding(
            owner,
            Fields::new(
                params,
                &[
                    "contractVersion",
                    "captureId",
                    "target",
                    "offset",
                    "maxBytes",
                ],
                decoder,
            ),
        )?;
        let target = decoding(owner, params.document("target", decoder))?;
        let target = decoding(
            owner,
            Fields::with_optional(target, &["kind"], &["entryId"], decoder),
        )?;
        let target = decoding(owner, target.document("kind", decoder))?;
        let target = decoding(owner, string(target, decoder))?;
        let expected = if matches!(kind, observed::EffectKind::ReadOriginal) {
            "original"
        } else {
            "semantic-projection"
        };
        payload_credit(ledger, expected.len(), target.len(), owner, index)?;
        let same = owner.same_text(expected, target)?;
        require(owner, index, same, LifecycleFault::Input)?;
    }
    Ok(())
}

fn replay<'a>(
    index: usize,
    records: &'a [observed::EffectRecord],
    keys: &[protocol::EffectRef],
    raw: &'a [Option<Cow<'a, str>>],
    fixture: &input::ClientFixture,
    actions: &[input::ClientAction],
    decoder: &mut Decoder,
    expanded: &mut ExpansionOwner,
    owner: &mut CompareOwner,
    ledger: &mut EffectLedger<'a>,
    metadata: &mut LifecycleMetadata,
) -> Result<(), ObservationError> {
    use observed::EffectRecord as R;
    let text = raw[index].as_deref();
    let event = match &records[index] {
        R::Pending { port, .. } => EffectEvent::Pending(match port {
            observed::EffectRecordPendingPort::Promise => EffectPort::Promise,
            observed::EffectRecordPendingPort::PickerReceiveCallback => {
                EffectPort::PickerReceiveCallback
            }
        }),
        R::PickerInputSignal { signal, .. } => EffectEvent::PickerInput(match signal {
            input::PickerSignal::FileSelection { .. } => protocol::PickerSignal::FileSelection,
            input::PickerSignal::PickerCancelEvent {} => protocol::PickerSignal::CancelEvent,
            input::PickerSignal::EmptySelection {} => protocol::PickerSignal::EmptySelection,
        }),
        R::CancellationRequested {
            action_index,
            cause: why,
            ..
        } => EffectEvent::CancellationRequested {
            action_index: action_index.0 as usize,
            cause: cause(why),
        },
        R::WorkStarted {
            work, owner: who, ..
        } => EffectEvent::WorkStarted {
            work,
            owner: match who {
                observed::WorkOwner::InlineProductionInvocation {} => WorkOwner::Inline,
                observed::WorkOwner::ActualWorker { worker } => WorkOwner::Worker(worker),
            },
        },
        R::WorkExited { work, .. } => EffectEvent::WorkExited { work },
        R::PreparedCoreResult {
            work,
            actual_result_byte_length,
            ..
        } => {
            require(
                owner,
                index,
                actual_result_byte_length.0 == text.expect("materialized result").len() as u64,
                LifecycleFault::Length,
            )?;
            EffectEvent::ResultPrepared {
                work,
                raw_reply: text.unwrap(),
            }
        }
        R::PromiseResolved { effect, reply, .. } => {
            let measured_work = ledger.recorded_work_funded(&keys[index], |cost| {
                metadata.charge(cost, decoder, expanded, owner)
            });
            let work = funded(measured_work, owner, index)?;
            require(
                owner,
                index,
                !matches!(
                    effect.kind,
                    observed::EffectKind::Inspection | observed::EffectKind::LocalEvaluation
                ) || work.is_some(),
                LifecycleFault::Work,
            )?;
            if !matches!(reply, input::DeliveredReply::Frame { .. }) {
                require(owner, index, work.is_none(), LifecycleFault::Work)?;
                validate_non_core_reply(
                    reply, effect, actions, fixture, decoder, expanded, owner, index, ledger,
                )?;
                let recorded = ledger.record_funded(
                    &keys[index],
                    EffectEvent::PromiseResolvedWithoutCoreResult,
                    |cost| metadata.charge(cost, decoder, expanded, owner),
                );
                return funded(recorded, owner, index);
            }
            let text = text.expect("materialized actual reply");
            decoding(owner, decoder.literal_with_raw(text))?;
            let measured_result = ledger.prepared_result_funded(&keys[index], |cost| {
                metadata.charge(cost, decoder, expanded, owner)
            });
            if let Some(held) = funded(measured_result, owner, index)? {
                owner.charge(
                    CompareResource::ComparisonBytes,
                    held.len()
                        .checked_add(text.len())
                        .ok_or(ObservationError::SizeOverflow)?,
                )?;
            }
            if effect.kind == observed::EffectKind::ManifestFetch {
                let input::ClientFixtureMode::Runtime {
                    runtime: input::ClientRuntime::ControlledModelOriginalsHttpV1 { manifest, .. },
                } = &fixture.mode
                else {
                    return fail(owner, index, LifecycleFault::Reply);
                };
                let configured = materialize(&manifest.body, decoder, expanded, owner)?;
                payload_credit(ledger, text.len(), configured.len(), owner, index)?;
                let same = owner.same_text(&configured, text)?;
                require(owner, index, same, LifecycleFault::Reply)?;
            } else if rpc_method(&effect.kind).is_some() {
                let mut pending = None;
                for record in &records[..index] {
                    owner.visit()?;
                    if let R::Pending {
                        effect: bound,
                        input: observed::EffectInput::OutboundFrame { index: frame },
                        ..
                    } = record
                    {
                        if owner.same(&bound.attempt, &effect.attempt)?
                            && bound.kind == effect.kind
                            && bound.ordinal.0 == effect.ordinal.0
                        {
                            pending = Some(frame.0 as usize);
                        }
                    }
                }
                let frame = pending.ok_or(ObservationError::Lifecycle {
                    event: index,
                    kind: LifecycleFault::UnjoinedReply,
                })?;
                let configured = selected_peer(fixture, owner, index)?
                    .frames
                    .0
                    .get(frame)
                    .ok_or(ObservationError::Lifecycle {
                        event: index,
                        kind: LifecycleFault::Reply,
                    })?;
                let configured = materialize(configured, decoder, expanded, owner)?;
                payload_credit(ledger, text.len(), configured.len(), owner, index)?;
                let same = owner.same_text(&configured, text)?;
                require(owner, index, same, LifecycleFault::Reply)?;
            } else if work.is_none() {
                validate_non_core_reply(
                    reply, effect, actions, fixture, decoder, expanded, owner, index, ledger,
                )?;
            }
            EffectEvent::PromiseResolved { actual_reply: text }
        }
        R::PromiseRejected { .. } => EffectEvent::PromiseRejected,
        R::CallbackDelivered { .. } => EffectEvent::CallbackDelivered,
        R::CallbackRetired {
            action_index,
            cause: why,
            ..
        } => EffectEvent::CallbackRetired {
            action_index: action_index.0 as usize,
            cause: cause(why),
        },
        R::LateSignal {
            disposition,
            causal_source,
            ..
        } => {
            let source=match causal_source{
                observed::LateSignalSource::FileReadCompletion{effect:source}=>{
                    let mut found=None;
                    for (i,record) in records[..index].iter().enumerate(){if let R::Pending{effect,..}=record{if owner.same(&effect.attempt,&source.attempt)?&&effect.kind==source.kind&&effect.ordinal.0==source.ordinal.0{found=Some(&keys[i]);}}}
                    protocol::LateSignalSource::FileReadCompletion(found.ok_or(ObservationError::Lifecycle{event:index,kind:LifecycleFault::Source})?)
                },
                observed::LateSignalSource::HeldWorkerResult{}=>protocol::LateSignalSource::HeldCoreResult,
                observed::LateSignalSource::PickerCancelEvent{}=>protocol::LateSignalSource::CancelEvent,
                observed::LateSignalSource::EmptySelectionEvent{}=>protocol::LateSignalSource::EmptySelectionEvent,
                observed::LateSignalSource::SelectionValidation{reason}=>protocol::LateSignalSource::SelectionValidation(match reason{observed::LateSignalSourceActualSelectionValidationReason::InvalidName=>protocol::SelectionRefusal::InvalidName,observed::LateSignalSourceActualSelectionValidationReason::UnsupportedCodec=>protocol::SelectionRefusal::UnsupportedCodec,observed::LateSignalSourceActualSelectionValidationReason::Oversized=>protocol::SelectionRefusal::Oversized}),
            };
            if matches!(
                causal_source,
                observed::LateSignalSource::HeldWorkerResult {}
            ) {
                let measured_result = ledger.prepared_result_funded(&keys[index], |cost| {
                    metadata.charge(cost, decoder, expanded, owner)
                });
                if let Some(held) = funded(measured_result, owner, index)? {
                    let actual = text.ok_or(ObservationError::Lifecycle {
                        event: index,
                        kind: LifecycleFault::Reply,
                    })?;
                    owner.charge(
                        CompareResource::ComparisonBytes,
                        held.len()
                            .checked_add(actual.len())
                            .ok_or(ObservationError::SizeOverflow)?,
                    )?;
                }
            }
            EffectEvent::LateSignal {
                actual_signal: text.ok_or(ObservationError::Lifecycle {
                    event: index,
                    kind: LifecycleFault::Reply,
                })?,
                source,
                disposition: match disposition {
                    observed::EffectRecordLateSignalDisposition::RetiredCallback => {
                        protocol::LateDisposition::RetiredCallback
                    }
                    observed::EffectRecordLateSignalDisposition::ConsumedCallback => {
                        protocol::LateDisposition::ConsumedCallback
                    }
                    observed::EffectRecordLateSignalDisposition::SettledPort => {
                        protocol::LateDisposition::SettledPort
                    }
                },
            }
        }
        // A matching alias or null is not an actual opening/currentness owner.
        // Keep this record unavailable until that separate source join exists.
        R::PublicationDisposition { .. } => {
            return fail(owner, index, LifecycleFault::UnjoinedPublication);
        }
        R::HeldResultRetired {
            byte_length,
            disposition,
            ..
        } => {
            let measured_result = ledger.prepared_result_funded(&keys[index], |cost| {
                metadata.charge(cost, decoder, expanded, owner)
            });
            let held = funded(measured_result, owner, index)?.map(str::len);
            require(
                owner,
                index,
                held == usize::try_from(byte_length.0).ok(),
                LifecycleFault::Length,
            )?;
            EffectEvent::ResultRetired(match disposition{observed::EffectRecordHeldResultRetiredDisposition::DeliveredToProductionPort=>protocol::ResultRetirement::DeliveredToPort,observed::EffectRecordHeldResultRetiredDisposition::DiscardedAfterProductionGuard=>protocol::ResultRetirement::DiscardedAfterGuard,observed::EffectRecordHeldResultRetiredDisposition::DiscardedOnOwnedTeardown=>protocol::ResultRetirement::DiscardedOnTeardown})
        }
    };
    let recorded = ledger.record_funded(&keys[index], event, |cost| {
        metadata.charge(cost, decoder, expanded, owner)
    });
    funded(recorded, owner, index)
}

#[cfg(test)]
mod tests;
