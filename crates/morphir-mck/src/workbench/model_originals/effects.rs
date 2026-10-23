//! Pure consistency checks for measured pending-port evidence. This ledger
//! cannot create a production port, establish a worker's actual exit, verify
//! model ownership, or authorize delivery. The adapter and workflow checker
//! must bind these records to complete actual inputs, results and source.
use super::FixtureAlias;
use std::{fmt, mem::size_of, num::NonZeroUsize};

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
    /// Copy already nominal DATA after the caller's metadata debit. This
    /// creates no source identity, pending port or execution authority.
    pub(crate) fn try_from_alias(
        attempt: &FixtureAlias,
        kind: EffectKind,
        ordinal: usize,
    ) -> Result<Self, EffectLedgerError> {
        if ordinal >= MAX_EVENTS {
            return Err(EffectLedgerError::Ordinal);
        }
        let attempt = attempt.try_clone().map_err(|error| match error {
            super::fixture_alias::FixtureAliasCloneError::Allocation(_) => {
                EffectLedgerError::Allocation
            }
            super::fixture_alias::FixtureAliasCloneError::ExcessCapacity => {
                EffectLedgerError::Storage
            }
        })?;
        Ok(Self {
            attempt,
            kind,
            ordinal,
        })
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
    /// The caller has validated the complete non-textual/direct result. This
    /// transition cannot stand in for any owned invocation's produced result.
    PromiseResolvedWithoutCoreResult,
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
    Allocation,
    Storage,
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
    ports: Vec<(EffectRef, PortRecord<'a>)>,
    work_names: Vec<&'a FixtureAlias>,
    prepared: Option<(usize, usize)>,
    max_attempt_bytes: usize,
    max_work_bytes: usize,
    events: usize,
    held_bytes: usize,
    produced_bytes: usize,
    observer_bytes: usize,
}

/// Requested logical backing and a conservative source-visible operation
/// upper, never allocator-private capacity, tree nodes, VM or RSS.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct EffectLedgerStorageCost {
    pub(crate) bytes: usize,
    pub(crate) slots: usize,
    pub(crate) work_bytes: usize,
    pub(crate) visits: usize,
}
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum FundedEffectLedgerError<E> {
    Ledger(EffectLedgerError),
    Funding(E),
}
impl<'a> EffectLedger<'a> {
    pub fn new(limits: EffectLedgerLimits) -> Self {
        Self {
            limits,
            ports: Vec::new(),
            work_names: Vec::new(),
            prepared: None,
            max_attempt_bytes: 0,
            max_work_bytes: 0,
            events: 0,
            held_bytes: 0,
            produced_bytes: 0,
            observer_bytes: 0,
        }
    }
    pub(crate) fn storage_layout(
        ports: usize,
        work: usize,
    ) -> Result<EffectLedgerStorageCost, EffectLedgerError> {
        let bytes = ports
            .checked_mul(size_of::<(EffectRef, PortRecord<'a>)>())
            .and_then(|n| {
                work.checked_mul(size_of::<&FixtureAlias>())
                    .and_then(|w| n.checked_add(w))
            })
            .and_then(|n| n.checked_add(size_of::<Self>()))
            .filter(|n| *n <= isize::MAX as usize)
            .ok_or(EffectLedgerError::Storage)?;
        let slots = ports
            .checked_add(work)
            .and_then(|n| n.checked_add(1))
            .ok_or(EffectLedgerError::Storage)?;
        Ok(EffectLedgerStorageCost {
            bytes,
            slots,
            work_bytes: bytes,
            visits: 3,
        })
    }
    /// Prepare the complete measured trace's requested backing before retaining
    /// any registration. The callback must debit the same cumulative caller
    /// owners. This funding API issues no source or execution authority.
    pub(crate) fn prepare_funded_storage<E>(
        &mut self,
        ports: usize,
        work: usize,
        fund: impl FnOnce(EffectLedgerStorageCost) -> Result<(), E>,
    ) -> Result<(), FundedEffectLedgerError<E>> {
        use FundedEffectLedgerError::{Funding, Ledger};
        if self.prepared.is_some()
            || !self.ports.is_empty()
            || !self.work_names.is_empty()
            || ports > self.limits.effects.get()
            || work > self.limits.events.get()
        {
            return Err(Ledger(EffectLedgerError::Storage));
        }
        let layout = Self::storage_layout(ports, work).map_err(Ledger)?;
        fund(layout).map_err(Funding)?;
        let mut port_storage = Vec::new();
        let mut work_storage = Vec::new();
        port_storage
            .try_reserve_exact(ports)
            .map_err(|_| Ledger(EffectLedgerError::Allocation))?;
        work_storage
            .try_reserve_exact(work)
            .map_err(|_| Ledger(EffectLedgerError::Allocation))?;
        // Allocator-private rounding is outside the model. Even a larger
        // *reported* capacity must not silently become funded retained backing.
        if port_storage.capacity() != ports || work_storage.capacity() != work {
            return Err(Ledger(EffectLedgerError::Storage));
        }
        self.ports = port_storage;
        self.work_names = work_storage;
        self.prepared = Some((ports, work));
        Ok(())
    }
    fn port_index(&self, effect: &EffectRef) -> Result<usize, usize> {
        self.ports.binary_search_by(|(key, _)| key.cmp(effect))
    }
    fn record_storage_cost(
        &self,
        effect: &EffectRef,
        event: EffectEvent<'a, '_>,
    ) -> Result<EffectLedgerStorageCost, EffectLedgerError> {
        let add = |a: usize, b: usize| a.checked_add(b).ok_or(EffectLedgerError::Storage);
        let mul = |a: usize, b: usize| a.checked_mul(b).ok_or(EffectLedgerError::Storage);
        // Rust slice binary_search performs at most bit_length(len)+1
        // comparisons. Each comparison is bounded by both complete aliases
        // plus the fixed typed key. Insertion can move every existing element.
        let search = |len: usize| {
            if len == 0 {
                0
            } else {
                (usize::BITS - len.leading_zeros()) as usize + 1
            }
        };
        let pending = matches!(event, EffectEvent::Pending(_));
        let port_searches = mul(search(self.ports.len()), if pending { 2 } else { 1 })?;
        let key_bytes = add(
            add(effect.attempt.as_str().len(), self.max_attempt_bytes)?,
            size_of::<EffectRef>(),
        )?;
        let mut cost = EffectLedgerStorageCost {
            bytes: if pending {
                effect.attempt.as_str().len()
            } else {
                0
            },
            slots: usize::from(pending),
            work_bytes: add(
                mul(port_searches, key_bytes)?,
                size_of::<EffectEvent<'_, '_>>() + size_of::<PortRecord<'_>>(),
            )?,
            visits: add(port_searches, 1)?,
        };
        if pending {
            cost.work_bytes = add(
                cost.work_bytes,
                add(
                    cost.bytes,
                    mul(self.ports.len(), size_of::<(EffectRef, PortRecord<'_>)>())?,
                )?,
            )?;
        }
        if let EffectEvent::WorkStarted { work, .. } = event {
            let queries = mul(search(self.work_names.len()), 2)?;
            cost.visits = add(cost.visits, queries)?;
            cost.work_bytes = add(
                cost.work_bytes,
                add(
                    mul(queries, add(work.as_str().len(), self.max_work_bytes)?)?,
                    mul(self.work_names.len(), size_of::<&FixtureAlias>())?,
                )?,
            )?;
        }
        if let EffectEvent::WorkExited { work } | EffectEvent::ResultPrepared { work, .. } = event {
            cost.work_bytes = add(
                cost.work_bytes,
                add(work.as_str().len(), self.max_work_bytes)?,
            )?;
            cost.visits = add(cost.visits, 1)?;
        }
        if let EffectEvent::LateSignal {
            source: LateSignalSource::FileReadCompletion(read),
            ..
        } = event
        {
            let queries = search(self.ports.len());
            cost.visits = add(cost.visits, queries)?;
            cost.work_bytes = add(
                cost.work_bytes,
                add(
                    mul(
                        queries,
                        add(
                            add(read.attempt.as_str().len(), self.max_attempt_bytes)?,
                            size_of::<EffectRef>(),
                        )?,
                    )?,
                    add(read.attempt.as_str().len(), effect.attempt.as_str().len())?,
                )?,
            )?;
        }
        Ok(cost)
    }
    fn lookup_storage_cost(
        &self,
        effect: &EffectRef,
    ) -> Result<EffectLedgerStorageCost, EffectLedgerError> {
        // A non-mutating lookup needs the same single binary search as a
        // non-inserting event; its fixed copy upper is deliberately retained.
        self.record_storage_cost(effect, EffectEvent::PromiseRejected)
    }
    pub(crate) fn recorded_work_funded<E>(
        &self,
        effect: &EffectRef,
        fund: impl FnOnce(EffectLedgerStorageCost) -> Result<(), E>,
    ) -> Result<Option<WorkBinding<'a>>, FundedEffectLedgerError<E>> {
        use FundedEffectLedgerError::{Funding, Ledger};
        fund(self.lookup_storage_cost(effect).map_err(Ledger)?).map_err(Funding)?;
        self.recorded_work(effect).map_err(Ledger)
    }
    pub(crate) fn prepared_result_funded<E>(
        &self,
        effect: &EffectRef,
        fund: impl FnOnce(EffectLedgerStorageCost) -> Result<(), E>,
    ) -> Result<Option<&'a str>, FundedEffectLedgerError<E>> {
        use FundedEffectLedgerError::{Funding, Ledger};
        fund(self.lookup_storage_cost(effect).map_err(Ledger)?).map_err(Funding)?;
        let index = self
            .port_index(effect)
            .map_err(|_| Ledger(EffectLedgerError::UnknownPort))?;
        Ok(match self.ports[index].1.result {
            ResultState::Retained { raw, .. } => Some(raw),
            _ => None,
        })
    }
    pub(crate) fn record_funded<E>(
        &mut self,
        effect: &EffectRef,
        event: EffectEvent<'a, '_>,
        fund: impl FnOnce(EffectLedgerStorageCost) -> Result<(), E>,
    ) -> Result<(), FundedEffectLedgerError<E>> {
        use FundedEffectLedgerError::{Funding, Ledger};
        let Some((ports, work)) = self.prepared else {
            return Err(Ledger(EffectLedgerError::Storage));
        };
        if matches!(event, EffectEvent::Pending(_)) && self.ports.len() >= ports
            || matches!(event, EffectEvent::WorkStarted { .. }) && self.work_names.len() >= work
        {
            return Err(Ledger(EffectLedgerError::Storage));
        }
        let cost = self.record_storage_cost(effect, event).map_err(Ledger)?;
        fund(cost).map_err(Funding)?;
        self.record_inner(effect, event).map_err(Ledger)
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
    /// Borrow exact currently unresolved ports, not all historical registrations.
    pub fn pending_effects(&self) -> impl Iterator<Item = &EffectRef> + Clone {
        self.ports
            .iter()
            .filter_map(|(effect, record)| record.state.pending().then_some(effect))
    }
    /// Borrow actual still-held produced results independently of port/work exit.
    pub fn prepared_effects(&self) -> impl Iterator<Item = (&EffectRef, &'a str)> + Clone {
        self.ports
            .iter()
            .filter_map(|(effect, record)| match record.result {
                ResultState::Retained { raw, .. } => Some((effect, raw)),
                ResultState::NotProduced | ResultState::Retired => None,
            })
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
        let record = &self.ports[self
            .port_index(effect)
            .map_err(|_| EffectLedgerError::UnknownPort)?]
        .1;
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
        if self.prepared.is_some() {
            return Err(EffectLedgerError::Storage);
        }
        self.record_inner(effect, event)
    }
    fn record_inner(
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
        let port_index = self
            .port_index(effect)
            .map_err(|_| EffectLedgerError::UnknownPort)?;
        let mut record = self.ports[port_index].1;
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
            EffectEvent::PromiseResolvedWithoutCoreResult => {
                if !matches!(record.state, PortState::PromisePending) {
                    return Err(EffectLedgerError::Settlement);
                }
                if !matches!(record.work, WorkState::NotStarted)
                    || !matches!(record.result, ResultState::NotProduced)
                {
                    return Err(EffectLedgerError::Work);
                }
                record.state = PortState::PromiseResolved;
            }
            EffectEvent::WorkStarted { work, owner } => {
                if !matches!(
                    effect.kind,
                    EffectKind::Inspection | EffectKind::LocalEvaluation
                ) || !matches!(record.state, PortState::PromisePending)
                    || !matches!(record.work, WorkState::NotStarted)
                    || self.work_names.binary_search(&work).is_ok()
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
                            .port_index(read)
                            .ok()
                            .and_then(|index| self.ports.get(index))
                            .is_some_and(|(_, p)| p.state.promise_terminal())
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
            let index = self
                .work_names
                .binary_search(&work)
                .expect_err("new measured work name");
            if self.prepared.is_none() {
                self.work_names
                    .try_reserve_exact(1)
                    .map_err(|_| EffectLedgerError::Allocation)?;
            }
            self.work_names.insert(index, work);
            self.max_work_bytes = self.max_work_bytes.max(work.as_str().len());
        }
        self.ports[port_index].1 = record;
        self.events += 1;
        self.held_bytes = held_bytes;
        self.produced_bytes = produced_bytes;
        Ok(())
    }

    fn compare_actual(&mut self, prepared: &str, actual: &str) -> Result<(), EffectLedgerError> {
        self.preflight_payload_comparison(prepared.len(), actual.len())?;
        if prepared == actual {
            Ok(())
        } else {
            Err(EffectLedgerError::ResultMismatch)
        }
    }
    /// Charge both complete operands before caller-side payload equality.
    /// This is DATA work on this SAME observer budget, not a port transition,
    /// successful comparison, source grant or refundable reservation.
    pub(crate) fn preflight_payload_comparison(
        &mut self,
        actual_bytes: usize,
        source_bytes: usize,
    ) -> Result<(), EffectLedgerError> {
        let visits = actual_bytes
            .checked_add(source_bytes)
            .ok_or(EffectLedgerError::Resource(
                EffectLedgerResource::ObserverBytes,
            ))?;
        self.observer_bytes = charge(
            self.observer_bytes,
            visits,
            self.limits.observer_bytes,
            EffectLedgerResource::ObserverBytes,
        )?;
        Ok(())
    }

    fn register(&mut self, effect: &EffectRef, port: EffectPort) -> Result<(), EffectLedgerError> {
        let index = self
            .port_index(effect)
            .map_or_else(Ok, |_| Err(EffectLedgerError::Duplicate))?;
        let state = match (effect.kind, port) {
            (EffectKind::Picker, EffectPort::PickerReceiveCallback) => PortState::CallbackPending,
            (EffectKind::Picker, _) | (_, EffectPort::PickerReceiveCallback) => {
                return Err(EffectLedgerError::PortKind);
            }
            (_, EffectPort::Promise) => PortState::PromisePending,
        };
        // By induction all prior ordinals for this exact attempt/kind were
        // gap-free. A new nonzero ordinal must have its immediate predecessor.
        if effect.ordinal > 0 {
            let previous = self.ports.binary_search_by(|(key, _)| {
                key.attempt
                    .cmp(&effect.attempt)
                    .then(key.kind.cmp(&effect.kind))
                    .then(key.ordinal.cmp(&(effect.ordinal - 1)))
            });
            if previous.is_err() {
                return Err(EffectLedgerError::Ordinal);
            }
        }
        if self.ports.len() == self.limits.effects.get() {
            return Err(EffectLedgerError::Resource(EffectLedgerResource::Effects));
        }
        if self.prepared.is_none() {
            self.ports
                .try_reserve_exact(1)
                .map_err(|_| EffectLedgerError::Allocation)?;
        }
        let attempt = effect.attempt.try_clone().map_err(|error| match error {
            super::fixture_alias::FixtureAliasCloneError::Allocation(_) => {
                EffectLedgerError::Allocation
            }
            super::fixture_alias::FixtureAliasCloneError::ExcessCapacity => {
                EffectLedgerError::Storage
            }
        })?;
        self.ports.insert(
            index,
            (
                EffectRef {
                    attempt,
                    kind: effect.kind,
                    ordinal: effect.ordinal,
                },
                PortRecord {
                    state,
                    work: WorkState::NotStarted,
                    result: ResultState::NotProduced,
                    publication: None,
                },
            ),
        );
        self.max_attempt_bytes = self.max_attempt_bytes.max(effect.attempt.as_str().len());
        self.events += 1;
        Ok(())
    }

    /// Establish only that this complete ledger has no unclosed ports, held
    /// results or running work records. Product retention/release, raw evidence
    /// completeness and actual worker exit require their independent checks.
    pub fn finish(&self) -> Result<(), EffectLedgerError> {
        if self.prepared.is_some() {
            return Err(EffectLedgerError::Storage);
        }
        self.finish_inner()
    }
    /// All three independent terminal scans use the SAME caller's cumulative
    /// work owner. A prior checkpoint scan does not pay these later reads.
    pub(crate) fn finish_funded<E>(
        &self,
        fund: impl FnOnce(EffectLedgerStorageCost) -> Result<(), E>,
    ) -> Result<(), FundedEffectLedgerError<E>> {
        use FundedEffectLedgerError::{Funding, Ledger};
        if self.prepared.is_none() {
            return Err(Ledger(EffectLedgerError::Storage));
        }
        let visits = self
            .ports
            .len()
            .checked_mul(3)
            .ok_or(Ledger(EffectLedgerError::Storage))?;
        let work_bytes = visits
            .checked_mul(size_of::<PortRecord<'_>>())
            .ok_or(Ledger(EffectLedgerError::Storage))?;
        fund(EffectLedgerStorageCost {
            bytes: 0,
            slots: 0,
            work_bytes,
            visits,
        })
        .map_err(Funding)?;
        self.finish_inner().map_err(Ledger)
    }
    fn finish_inner(&self) -> Result<(), EffectLedgerError> {
        if self.ports.iter().any(|(_, p)| p.state.pending()) {
            return Err(EffectLedgerError::PendingPorts);
        }
        if self
            .ports
            .iter()
            .any(|(_, p)| matches!(p.result, ResultState::Retained { .. }))
        {
            return Err(EffectLedgerError::HeldResults);
        }
        if self
            .ports
            .iter()
            .any(|(_, p)| matches!(p.work, WorkState::Running { .. }))
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
