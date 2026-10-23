//! Pure consistency checks for measured pending-port evidence. This ledger
//! cannot create a production port, establish a worker's actual exit, verify
//! model ownership, or authorize delivery. The adapter and workflow checker
//! must bind these records to complete actual inputs, results and source.
use super::FixtureAlias;
use std::{
    collections::{BTreeMap, BTreeSet},
    fmt,
    num::NonZeroUsize,
};

const MAX_EVENTS: usize = 8192;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum EffectKind {
    Picker,
    FileRead,
    NativeCapture,
    Initialize,
    Capture,
    Inventory,
    ReadOriginal,
    ReadProjection,
    Release,
    Catalog,
    NativeInvoke,
    Digest,
    Inspection,
    LocalEvaluation,
    ExecutionSubmit,
    ExecutionObserve,
    ExecutionRelease,
    ManifestFetch,
    WorkspaceOpen,
}

/// A measured effect reference, not a token granting access to a pending port.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct EffectRef {
    attempt: FixtureAlias,
    kind: EffectKind,
    ordinal: usize,
}
impl EffectRef {
    pub fn new(attempt: &str, kind: EffectKind, ordinal: usize) -> Result<Self, EffectLedgerError> {
        if ordinal >= MAX_EVENTS {
            return Err(EffectLedgerError::Ordinal);
        }
        Ok(Self {
            attempt: FixtureAlias::new(attempt).map_err(|_| EffectLedgerError::Alias)?,
            kind,
            ordinal,
        })
    }
    pub fn attempt(&self) -> &FixtureAlias {
        &self.attempt
    }
    pub fn kind(&self) -> EffectKind {
        self.kind
    }
    pub fn ordinal(&self) -> usize {
        self.ordinal
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EffectPort {
    Promise,
    PickerReceiveCallback,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CancellationCause {
    CancelOpening,
    CloseCurrentModel,
    CloseModel,
    Replacement,
    Teardown,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PickerSignal {
    FileSelection,
    CancelEvent,
    EmptySelection,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkOwner<'a> {
    Inline,
    Worker(&'a FixtureAlias),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WorkBinding<'a> {
    invocation: &'a FixtureAlias,
    owner: WorkOwner<'a>,
}
impl<'a> WorkBinding<'a> {
    pub fn invocation(self) -> &'a FixtureAlias {
        self.invocation
    }
    pub fn owner(self) -> WorkOwner<'a> {
        self.owner
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LateDisposition {
    RetiredCallback,
    ConsumedCallback,
    SettledPort,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LateSignalSource<'a> {
    FileReadCompletion(&'a EffectRef),
    HeldCoreResult,
    CancelEvent,
    EmptySelectionEvent,
    SelectionValidation(SelectionRefusal),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SelectionRefusal {
    InvalidName,
    UnsupportedCodec,
    Oversized,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PublicationDisposition {
    Forwarded,
    Ignored,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResultRetirement {
    DeliveredToPort,
    DiscardedAfterGuard,
    DiscardedOnTeardown,
}

/// Borrow complete actual result text. No digest, expected value, or reparsed
/// JSON value substitutes for exact prepared-result equality. Other evidence,
/// including raw errors, inputs and guard ownership, is checked by the caller.
#[derive(Debug, Clone, Copy)]
pub enum EffectEvent<'a, 'e> {
    Pending(EffectPort),
    PickerInput(PickerSignal),
    CancellationRequested {
        action_index: usize,
        cause: CancellationCause,
    },
    WorkStarted {
        work: &'a FixtureAlias,
        owner: WorkOwner<'a>,
    },
    WorkExited {
        work: &'e FixtureAlias,
    },
    ResultPrepared {
        work: &'e FixtureAlias,
        raw_reply: &'a str,
    },
    PromiseResolved {
        actual_reply: &'e str,
    },
    PromiseRejected,
    CallbackDelivered,
    CallbackRetired {
        action_index: usize,
        cause: CancellationCause,
    },
    LateSignal {
        actual_signal: &'e str,
        disposition: LateDisposition,
        source: LateSignalSource<'e>,
    },
    Publication(PublicationDisposition),
    ResultRetired(ResultRetirement),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EffectLedgerResource {
    Effects,
    Events,
    HeldResultBytes,
    ProducedResultBytes,
    ObserverBytes,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EffectLedgerError {
    Limits,
    Alias,
    Ordinal,
    Duplicate,
    UnknownPort,
    PortKind,
    Settlement,
    Work,
    ResultMismatch,
    LateSignal,
    Publication,
    PendingPorts,
    HeldResults,
    RunningWork,
    Resource(EffectLedgerResource),
}
impl fmt::Display for EffectLedgerError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "invalid measured effect lifecycle: {self:?}")
    }
}
impl std::error::Error for EffectLedgerError {}

/// Explicit checker bounds. Zero byte credit is a valid refusal policy.
/// Held storage is reusable after explicit retirement. Cumulative produced
/// bytes never refund. Observer credit counts the conservative byte-visit upper
/// bound of payload equality, including rejected comparisons. These are not
/// runtime quotas, total parser/metadata work or RSS bounds.
#[derive(Debug, Clone, Copy)]
pub struct EffectLedgerLimits {
    effects: NonZeroUsize,
    events: NonZeroUsize,
    held_bytes: usize,
    produced_bytes: usize,
    observer_bytes: usize,
}
impl EffectLedgerLimits {
    pub fn new(
        effects: usize,
        events: usize,
        held_bytes: usize,
        produced_bytes: usize,
        observer_bytes: usize,
    ) -> Result<Self, EffectLedgerError> {
        if effects > isize::MAX as usize
            || events > isize::MAX as usize
            || held_bytes > isize::MAX as usize
            || produced_bytes > isize::MAX as usize
            || observer_bytes > isize::MAX as usize
        {
            return Err(EffectLedgerError::Limits);
        }
        Ok(Self {
            effects: NonZeroUsize::new(effects).ok_or(EffectLedgerError::Limits)?,
            events: NonZeroUsize::new(events).ok_or(EffectLedgerError::Limits)?,
            held_bytes,
            produced_bytes,
            observer_bytes,
        })
    }
}

#[derive(Debug, Clone, Copy)]
enum PortState {
    PromisePending,
    PromiseResolved,
    PromiseRejected,
    CallbackPending,
    CallbackConsumed,
    CallbackRetired,
}
impl PortState {
    fn pending(self) -> bool {
        matches!(self, Self::PromisePending | Self::CallbackPending)
    }
    fn promise_terminal(self) -> bool {
        matches!(self, Self::PromiseResolved | Self::PromiseRejected)
    }
}
#[derive(Debug, Clone, Copy)]
enum WorkState<'a> {
    NotStarted,
    Running {
        work: &'a FixtureAlias,
        owner: WorkOwner<'a>,
    },
    Exited {
        work: &'a FixtureAlias,
        owner: WorkOwner<'a>,
    },
}
#[derive(Debug, Clone, Copy)]
enum Delivery {
    NotDelivered,
    ResolvedPort,
    IgnoredSettledGuard,
}
#[derive(Debug, Clone, Copy)]
enum ResultState<'a> {
    NotProduced,
    Retained { raw: &'a str, delivery: Delivery },
    Retired,
}
#[derive(Debug, Clone, Copy)]
struct PortRecord<'a> {
    state: PortState,
    work: WorkState<'a>,
    result: ResultState<'a>,
    publication: Option<PublicationDisposition>,
}

pub struct EffectLedger<'a> {
    limits: EffectLedgerLimits,
    ports: BTreeMap<EffectRef, PortRecord<'a>>,
    ordinals: BTreeMap<FixtureAlias, BTreeMap<EffectKind, usize>>,
    work_names: BTreeSet<&'a FixtureAlias>,
    events: usize,
    held_bytes: usize,
    produced_bytes: usize,
    observer_bytes: usize,
}
impl<'a> EffectLedger<'a> {
    pub fn new(limits: EffectLedgerLimits) -> Self {
        Self {
            limits,
            ports: BTreeMap::new(),
            ordinals: BTreeMap::new(),
            work_names: BTreeSet::new(),
            events: 0,
            held_bytes: 0,
            produced_bytes: 0,
            observer_bytes: 0,
        }
    }
    pub fn event_count(&self) -> usize {
        self.events
    }
    pub fn port_count(&self) -> usize {
        self.ports.len()
    }
    pub fn held_result_bytes(&self) -> usize {
        self.held_bytes
    }
    pub fn produced_result_bytes(&self) -> usize {
        self.produced_bytes
    }
    pub fn observer_bytes(&self) -> usize {
        self.observer_bytes
    }
    /// The recorded work binding survives exit for independent source/worker
    /// correspondence checks. This accessor establishes no execution authority.
    pub fn recorded_work(
        &self,
        effect: &EffectRef,
    ) -> Result<Option<WorkBinding<'a>>, EffectLedgerError> {
        let record = self
            .ports
            .get(effect)
            .ok_or(EffectLedgerError::UnknownPort)?;
        Ok(match record.work {
            WorkState::NotStarted => None,
            WorkState::Running { work, owner } | WorkState::Exited { work, owner } => {
                Some(WorkBinding {
                    invocation: work,
                    owner,
                })
            }
        })
    }

    /// Refused records preserve lifecycle and retained storage. Performed byte
    /// comparisons remain charged, including mismatches. Check the full saved trace
    /// and its expansion budgets before decoding or replaying its records.
    pub fn record(
        &mut self,
        effect: &EffectRef,
        event: EffectEvent<'a, '_>,
    ) -> Result<(), EffectLedgerError> {
        if self.events == self.limits.events.get() {
            return Err(EffectLedgerError::Resource(EffectLedgerResource::Events));
        }
        if let EffectEvent::Pending(port) = event {
            return self.register(effect, port);
        }
        let mut record = *self
            .ports
            .get(effect)
            .ok_or(EffectLedgerError::UnknownPort)?;
        let mut held_bytes = self.held_bytes;
        let mut produced_bytes = self.produced_bytes;
        match event {
            EffectEvent::Pending(_) => unreachable!(),
            EffectEvent::PickerInput(_) => {
                if !matches!(
                    record.state,
                    PortState::CallbackPending
                        | PortState::CallbackConsumed
                        | PortState::CallbackRetired
                ) {
                    return Err(EffectLedgerError::Settlement);
                }
            }
            EffectEvent::CancellationRequested { action_index, .. } => check_action(action_index)?,
            EffectEvent::CallbackRetired { action_index, .. } => {
                check_action(action_index)?;
                if !matches!(record.state, PortState::CallbackPending) {
                    return Err(EffectLedgerError::Settlement);
                }
                record.state = PortState::CallbackRetired;
            }
            EffectEvent::CallbackDelivered => {
                if !matches!(record.state, PortState::CallbackPending) {
                    return Err(EffectLedgerError::Settlement);
                }
                record.state = PortState::CallbackConsumed;
            }
            EffectEvent::PromiseRejected => {
                if !matches!(record.state, PortState::PromisePending) {
                    return Err(EffectLedgerError::Settlement);
                }
                record.state = PortState::PromiseRejected;
            }
            EffectEvent::PromiseResolved { actual_reply } => {
                if !matches!(record.state, PortState::PromisePending) {
                    return Err(EffectLedgerError::Settlement);
                }
                match record.result {
                    ResultState::Retained { raw, .. } => {
                        self.compare_actual(raw, actual_reply)?;
                        record.result = ResultState::Retained {
                            raw,
                            delivery: Delivery::ResolvedPort,
                        };
                    }
                    ResultState::Retired => return Err(EffectLedgerError::HeldResults),
                    ResultState::NotProduced => {
                        if !matches!(record.work, WorkState::NotStarted) {
                            return Err(EffectLedgerError::Work);
                        }
                    }
                }
                record.state = PortState::PromiseResolved;
            }
            EffectEvent::WorkStarted { work, owner } => {
                if !matches!(
                    effect.kind,
                    EffectKind::Inspection | EffectKind::LocalEvaluation
                ) || !matches!(record.state, PortState::PromisePending)
                    || !matches!(record.work, WorkState::NotStarted)
                    || self.work_names.contains(work)
                {
                    return Err(EffectLedgerError::Work);
                }
                record.work = WorkState::Running { work, owner };
            }
            EffectEvent::WorkExited { work } => {
                let WorkState::Running {
                    work: current,
                    owner,
                } = record.work
                else {
                    return Err(EffectLedgerError::Work);
                };
                if current != work {
                    return Err(EffectLedgerError::Work);
                }
                record.work = WorkState::Exited {
                    work: current,
                    owner,
                };
            }
            EffectEvent::ResultPrepared { work, raw_reply } => {
                if !matches!(record.work, WorkState::Running { work: current, .. } if current == work)
                    || !matches!(record.result, ResultState::NotProduced)
                    || matches!(record.state, PortState::PromiseResolved)
                {
                    return Err(EffectLedgerError::Work);
                }
                held_bytes = charge(
                    held_bytes,
                    raw_reply.len(),
                    self.limits.held_bytes,
                    EffectLedgerResource::HeldResultBytes,
                )?;
                produced_bytes = charge(
                    produced_bytes,
                    raw_reply.len(),
                    self.limits.produced_bytes,
                    EffectLedgerResource::ProducedResultBytes,
                )?;
                record.result = ResultState::Retained {
                    raw: raw_reply,
                    delivery: Delivery::NotDelivered,
                };
            }
            EffectEvent::LateSignal {
                actual_signal,
                disposition,
                source,
            } => match (record.state, disposition, source) {
                (
                    PortState::CallbackRetired,
                    LateDisposition::RetiredCallback,
                    LateSignalSource::CancelEvent
                    | LateSignalSource::EmptySelectionEvent
                    | LateSignalSource::SelectionValidation(_),
                )
                | (
                    PortState::CallbackConsumed,
                    LateDisposition::ConsumedCallback,
                    LateSignalSource::CancelEvent
                    | LateSignalSource::EmptySelectionEvent
                    | LateSignalSource::SelectionValidation(_),
                ) => {}
                (
                    PortState::CallbackRetired,
                    LateDisposition::RetiredCallback,
                    LateSignalSource::FileReadCompletion(read),
                )
                | (
                    PortState::CallbackConsumed,
                    LateDisposition::ConsumedCallback,
                    LateSignalSource::FileReadCompletion(read),
                ) => {
                    if read.attempt != effect.attempt
                        || read.kind != EffectKind::FileRead
                        || !self
                            .ports
                            .get(read)
                            .is_some_and(|p| p.state.promise_terminal())
                    {
                        return Err(EffectLedgerError::LateSignal);
                    }
                }
                (state, LateDisposition::SettledPort, LateSignalSource::HeldCoreResult)
                    if state.promise_terminal() =>
                {
                    let ResultState::Retained { raw, .. } = record.result else {
                        return Err(EffectLedgerError::HeldResults);
                    };
                    self.compare_actual(raw, actual_signal)?;
                    record.result = ResultState::Retained {
                        raw,
                        delivery: Delivery::IgnoredSettledGuard,
                    };
                }
                _ => return Err(EffectLedgerError::LateSignal),
            },
            EffectEvent::Publication(disposition) => {
                if record.state.pending()
                    || matches!(record.state, PortState::CallbackRetired)
                    || record.publication.is_some()
                {
                    return Err(EffectLedgerError::Publication);
                }
                record.publication = Some(disposition);
            }
            EffectEvent::ResultRetired(disposition) => {
                let ResultState::Retained { raw, delivery } = record.result else {
                    return Err(EffectLedgerError::HeldResults);
                };
                match (disposition, delivery) {
                    (ResultRetirement::DiscardedOnTeardown, _)
                    | (ResultRetirement::DeliveredToPort, Delivery::ResolvedPort)
                    | (ResultRetirement::DiscardedAfterGuard, Delivery::IgnoredSettledGuard) => {}
                    _ => return Err(EffectLedgerError::Settlement),
                }
                held_bytes -= raw.len();
                record.result = ResultState::Retired;
            }
        }
        if let EffectEvent::WorkStarted { work, .. } = event {
            self.work_names.insert(work);
        }
        *self.ports.get_mut(effect).expect("existing measured port") = record;
        self.events += 1;
        self.held_bytes = held_bytes;
        self.produced_bytes = produced_bytes;
        Ok(())
    }

    fn compare_actual(&mut self, prepared: &str, actual: &str) -> Result<(), EffectLedgerError> {
        let visits =
            prepared
                .len()
                .checked_add(actual.len())
                .ok_or(EffectLedgerError::Resource(
                    EffectLedgerResource::ObserverBytes,
                ))?;
        self.observer_bytes = charge(
            self.observer_bytes,
            visits,
            self.limits.observer_bytes,
            EffectLedgerResource::ObserverBytes,
        )?;
        if prepared == actual {
            Ok(())
        } else {
            Err(EffectLedgerError::ResultMismatch)
        }
    }

    fn register(&mut self, effect: &EffectRef, port: EffectPort) -> Result<(), EffectLedgerError> {
        if self.ports.contains_key(effect) {
            return Err(EffectLedgerError::Duplicate);
        }
        let state = match (effect.kind, port) {
            (EffectKind::Picker, EffectPort::PickerReceiveCallback) => PortState::CallbackPending,
            (EffectKind::Picker, _) | (_, EffectPort::PickerReceiveCallback) => {
                return Err(EffectLedgerError::PortKind);
            }
            (_, EffectPort::Promise) => PortState::PromisePending,
        };
        let next = self
            .ordinals
            .get(&effect.attempt)
            .and_then(|kinds| kinds.get(&effect.kind))
            .copied()
            .unwrap_or(0);
        if effect.ordinal != next {
            return Err(EffectLedgerError::Ordinal);
        }
        if self.ports.len() == self.limits.effects.get() {
            return Err(EffectLedgerError::Resource(EffectLedgerResource::Effects));
        }
        self.ports.insert(
            effect.clone(),
            PortRecord {
                state,
                work: WorkState::NotStarted,
                result: ResultState::NotProduced,
                publication: None,
            },
        );
        self.ordinals
            .entry(effect.attempt.clone())
            .or_default()
            .insert(effect.kind, next + 1);
        self.events += 1;
        Ok(())
    }

    /// Establish only that this complete ledger has no unclosed ports, held
    /// results or running work records. Product retention/release, raw evidence
    /// completeness and actual worker exit require their independent checks.
    pub fn finish(&self) -> Result<(), EffectLedgerError> {
        if self.ports.values().any(|p| p.state.pending()) {
            return Err(EffectLedgerError::PendingPorts);
        }
        if self
            .ports
            .values()
            .any(|p| matches!(p.result, ResultState::Retained { .. }))
        {
            return Err(EffectLedgerError::HeldResults);
        }
        if self
            .ports
            .values()
            .any(|p| matches!(p.work, WorkState::Running { .. }))
        {
            return Err(EffectLedgerError::RunningWork);
        }
        Ok(())
    }
}
fn check_action(index: usize) -> Result<(), EffectLedgerError> {
    if index < MAX_EVENTS {
        Ok(())
    } else {
        Err(EffectLedgerError::Ordinal)
    }
}
fn charge(
    total: usize,
    amount: usize,
    limit: usize,
    resource: EffectLedgerResource,
) -> Result<usize, EffectLedgerError> {
    total
        .checked_add(amount)
        .filter(|value| *value <= limit)
        .ok_or(EffectLedgerError::Resource(resource))
}
