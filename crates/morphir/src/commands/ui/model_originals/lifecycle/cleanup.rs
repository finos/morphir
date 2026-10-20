//! Actual provider join ownership for the explicitly observed native host.
//! No task is spawned here. A deadline returns the same retained handles.
use super::*;
use std::{
    future::Future,
    pin::Pin,
    task::{Context, Poll},
};

type ActualProviderJoin = TrackedJoin<Result<ModelCaptureCompletion, ProviderCaptureError>>;

enum JoinState {
    Prearmed,
    Awaited(ActualProviderJoin),
    Retained(ActualProviderJoin),
    Draining,
    Joined,
    Abandoned,
}
pub(super) struct CleanupSlot {
    join: Mutex<JoinState>,
    owner: Weak<Mutex<ConnectionOwner>>,
    registry: Option<Weak<Mutex<CleanupEntries>>>,
    control: CaptureControl,
    attempt: AttemptKey,
    // These are distinct from the actual worker's WorkPermit. The body can
    // return, releasing work, while this exact unjoined attempt remains owned.
    _slot: Arc<CaptureSlotCredit>,
    _credit: RetainedEvidenceCredit,
}
impl CleanupSlot {
    pub(super) fn prepare(
        reservation: &mut Reservation,
        owner: &Arc<Mutex<ConnectionOwner>>,
        attempt: AttemptKey,
        control: &CaptureControl,
        registry: Option<&CleanupRegistry>,
    ) -> Result<Arc<Self>, CaptureError> {
        // Before either Arc allocation or the actual spawn, charge the same
        // host metadata ledger for both allocations and their Arc headers.
        let credit = reservation.host.reserve_evidence(
            std::mem::size_of::<Self>()
                .checked_add(std::mem::size_of::<CaptureSlotCredit>())
                .and_then(|n| n.checked_add(4 * std::mem::size_of::<usize>()))
                .ok_or(CaptureError::Capacity)?,
        )?;
        let held_slot = Arc::new(CaptureSlotCredit(reservation.host.clone()));
        reservation.slot = Some(held_slot.clone());
        let slot = Arc::new(Self {
            join: Mutex::new(JoinState::Prearmed),
            owner: Arc::downgrade(owner),
            registry: registry.map(|r| Arc::downgrade(&r.0)),
            control: control.clone(),
            attempt,
            _slot: held_slot,
            _credit: credit,
        });
        if let Some(registry) = registry {
            registry.insert(&slot)?;
        }
        Ok(slot)
    }
    pub(super) fn install(&self, actual: ActualProviderJoin) {
        let mut state = self.join.lock().expect("capture cleanup");
        assert!(matches!(*state, JoinState::Prearmed));
        *state = JoinState::Awaited(actual);
    }
    pub(super) fn pending(&self) -> bool {
        matches!(
            *self.join.lock().expect("capture cleanup"),
            JoinState::Prearmed
                | JoinState::Awaited(_)
                | JoinState::Retained(_)
                | JoinState::Draining
        )
    }
    fn retained(&self) -> bool {
        matches!(
            *self.join.lock().expect("capture cleanup"),
            JoinState::Retained(_) | JoinState::Draining
        )
    }
    fn owns_handle(&self) -> bool {
        matches!(
            *self.join.lock().expect("capture cleanup"),
            JoinState::Awaited(_) | JoinState::Retained(_) | JoinState::Draining
        )
    }
    fn is_finished(&self) -> bool {
        match &*self.join.lock().expect("capture cleanup") {
            JoinState::Awaited(join) | JoinState::Retained(join) => join.is_finished(),
            JoinState::Joined | JoinState::Abandoned => true,
            JoinState::Prearmed | JoinState::Draining => false,
        }
    }
    pub(super) fn retain(&self) {
        {
            let mut state = self.join.lock().expect("capture cleanup");
            let prior = std::mem::replace(&mut *state, JoinState::Prearmed);
            *state = match prior {
                JoinState::Awaited(join) => JoinState::Retained(join),
                prior => prior,
            };
        }
        // Signal cancellation only AFTER the actual handle's ownership changes.
        abandon(&self.owner, self.attempt, &self.control);
    }
    fn retire(&self) {
        if let Some(owner) = self.owner.upgrade() {
            let mut owner = owner.lock().expect("model capture connection");
            if owner
                .cleanup
                .as_ref()
                .is_some_and(|slot| std::ptr::eq(slot.as_ref(), self))
            {
                owner.cleanup = None;
            }
        }
        if let Some(registry) = self.registry.as_ref().and_then(Weak::upgrade) {
            let mut entries = registry.lock().expect("host capture cleanup");
            for entry in &mut entries.0 {
                if entry
                    .as_ref()
                    .is_some_and(|slot| std::ptr::eq(slot.as_ref(), self))
                {
                    *entry = None;
                }
            }
        }
    }
    pub(super) fn abandon_waiter(&self) {
        let prior = {
            let mut state = self.join.lock().expect("capture cleanup");
            if !matches!(*state, JoinState::Awaited(_)) {
                return;
            }
            std::mem::replace(&mut *state, JoinState::Abandoned)
        };
        // TrackedJoin's real Drop records abandonment. No joined event is made.
        drop(prior);
        self.retire();
    }
    fn poll_wait(
        &self,
        cx: &mut Context<'_>,
    ) -> Poll<Result<Result<ModelCaptureCompletion, ProviderCaptureError>, tokio::task::JoinError>>
    {
        let outcome = {
            let mut state = self.join.lock().expect("capture cleanup");
            match &mut *state {
                JoinState::Awaited(join) => match Pin::new(join).poll(cx) {
                    Poll::Ready(result) => {
                        *state = JoinState::Joined;
                        Poll::Ready(result)
                    }
                    Poll::Pending => Poll::Pending,
                },
                // A socket handoff is followed by dropping this dispatch future.
                // Only the explicit cleanup owner may now poll the handle.
                JoinState::Retained(_) | JoinState::Draining => Poll::Pending,
                _ => panic!("capture waiter polled after completion"),
            }
        };
        if outcome.is_ready() {
            self.retire();
        }
        outcome
    }
    async fn drain(self: &Arc<Self>, deadline: tokio::time::Instant) -> bool {
        self.retain();
        let actual = {
            let mut state = self.join.lock().expect("capture cleanup");
            match std::mem::replace(&mut *state, JoinState::Draining) {
                JoinState::Retained(join) => join,
                prior => {
                    let done = matches!(prior, JoinState::Joined | JoinState::Abandoned);
                    *state = prior;
                    return done;
                }
            }
        };
        let mut guard = DrainGuard {
            slot: self.clone(),
            actual: Some(actual),
        };
        let result =
            tokio::time::timeout_at(deadline, guard.actual.as_mut().expect("actual owned join"))
                .await;
        if result.is_err() {
            // Guard puts the SAME actual join back before returning Pending.
            return false;
        }
        // Both Ok(body result) and Err(real JoinError) are resolved joins.
        guard.actual = None;
        *self.join.lock().expect("capture cleanup") = JoinState::Joined;
        self.retire();
        true
    }
}
struct DrainGuard {
    slot: Arc<CleanupSlot>,
    actual: Option<ActualProviderJoin>,
}
impl Drop for DrainGuard {
    fn drop(&mut self) {
        if let Some(actual) = self.actual.take() {
            let mut state = self.slot.join.lock().expect("capture cleanup");
            assert!(matches!(*state, JoinState::Draining));
            *state = JoinState::Retained(actual);
        }
    }
}
// Setup can unwind after the real spawn but before TrackedJoin installation.
// Existing WorkerIssuance marks that prefix incomplete; do not leak a slot.
pub(super) struct PrearmedCleanup(Option<Arc<CleanupSlot>>);
impl PrearmedCleanup {
    pub(super) fn new(slot: Option<Arc<CleanupSlot>>) -> Self {
        Self(slot)
    }
}
impl Drop for PrearmedCleanup {
    fn drop(&mut self) {
        if let Some(slot) = &self.0 {
            let prearmed = {
                let mut state = slot.join.lock().expect("capture cleanup");
                if matches!(*state, JoinState::Prearmed) {
                    *state = JoinState::Abandoned;
                    true
                } else {
                    false
                }
            };
            if prearmed {
                slot.retire();
            }
        }
    }
}

// Ordinary/storage connections keep their historical direct waiter ownership.
pub(super) enum ProviderJoin {
    Direct(ActualProviderJoin),
    Owned {
        slot: Arc<CleanupSlot>,
        observation: WorkerAttemptObservation,
    },
}
impl ProviderJoin {
    pub(super) fn observation(&self) -> WorkerAttemptObservation {
        match self {
            Self::Direct(join) => join.observation(),
            Self::Owned { observation, .. } => observation.clone(),
        }
    }
    pub(super) fn is_finished(&self) -> bool {
        match self {
            Self::Direct(join) => join.is_finished(),
            Self::Owned { slot, .. } => slot.is_finished(),
        }
    }
    pub(super) fn handoff(&self) {
        if let Self::Owned { slot, .. } = self {
            slot.retain();
        }
    }
}
impl Future for ProviderJoin {
    type Output =
        Result<Result<ModelCaptureCompletion, ProviderCaptureError>, tokio::task::JoinError>;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        match self.get_mut() {
            Self::Direct(join) => Pin::new(join).poll(cx),
            Self::Owned { slot, .. } => slot.poll_wait(cx),
        }
    }
}
impl Drop for ProviderJoin {
    fn drop(&mut self) {
        if let Self::Owned { slot, .. } = self {
            slot.abandon_waiter();
        }
    }
}

// This fixed table is host infrastructure. Entries are actual precharged
// attempt owners, not empty connection history or read-only observer records.
struct CleanupEntries([Option<Arc<CleanupSlot>>; MAX_HOST_CAPTURES]);
#[derive(Clone)]
pub(in crate::commands::ui) struct CleanupRegistry(Arc<Mutex<CleanupEntries>>);
impl CleanupRegistry {
    pub(in crate::commands::ui) fn new() -> Self {
        Self(Arc::new(Mutex::new(CleanupEntries(std::array::from_fn(
            |_| None,
        )))))
    }
    fn insert(&self, slot: &Arc<CleanupSlot>) -> Result<(), CaptureError> {
        let mut entries = self.0.lock().expect("host capture cleanup");
        let entry = entries
            .0
            .iter_mut()
            .find(|entry| entry.is_none())
            .ok_or(CaptureError::Capacity)?;
        *entry = Some(slot.clone());
        Ok(())
    }
    pub(in crate::commands::ui) fn control(&self) -> HostCaptureCleanupOwner {
        HostCaptureCleanupOwner(self.clone())
    }
}
pub(in crate::commands::ui) struct HostCaptureCleanupOwner(CleanupRegistry);
impl HostCaptureCleanupOwner {
    pub(in crate::commands::ui) fn retained_handles(&self) -> usize {
        self.0
            .0
            .lock()
            .expect("host capture cleanup")
            .0
            .iter()
            .flatten()
            .filter(|slot| slot.retained())
            .count()
    }
    pub(in crate::commands::ui) async fn drain(
        self,
        deadline: tokio::time::Instant,
    ) -> Result<(), PendingCaptureCleanup> {
        PendingCaptureCleanup {
            owner: CleanupOwner::Host(self.0),
        }
        .drain(deadline)
        .await
    }
}
#[must_use = "A pending cleanup token still owns real unjoined workers"]
pub(in crate::commands::ui) struct PendingCaptureCleanup {
    owner: CleanupOwner,
}
enum CleanupOwner {
    Single(Option<Arc<CleanupSlot>>),
    Host(CleanupRegistry),
}
impl PendingCaptureCleanup {
    pub(super) fn single(slot: Option<Arc<CleanupSlot>>) -> Self {
        Self {
            owner: CleanupOwner::Single(slot),
        }
    }
    pub(in crate::commands::ui) fn retained_handles(&self) -> usize {
        match &self.owner {
            CleanupOwner::Single(slot) => {
                usize::from(slot.as_ref().is_some_and(|slot| slot.owns_handle()))
            }
            CleanupOwner::Host(registry) => registry
                .0
                .lock()
                .expect("host capture cleanup")
                .0
                .iter()
                .flatten()
                .filter(|slot| slot.owns_handle())
                .count(),
        }
    }
    pub(in crate::commands::ui) async fn drain(
        mut self,
        deadline: tokio::time::Instant,
    ) -> Result<(), Self> {
        // The Host variant retains the SAME fixed table, not a separately
        // allocated snapshot or new task. Caller must quiesce new dispatch.
        for index in 0..MAX_HOST_CAPTURES {
            let slot = match &self.owner {
                CleanupOwner::Single(slot) if index == 0 => slot.clone(),
                CleanupOwner::Single(_) => None,
                CleanupOwner::Host(registry) => {
                    registry.0.lock().expect("host capture cleanup").0[index].clone()
                }
            };
            if let Some(slot) = slot {
                if !slot.drain(deadline).await {
                    return Err(self);
                }
                if let CleanupOwner::Single(entry) = &mut self.owner {
                    *entry = None;
                }
            }
        }
        Ok(())
    }
}
pub(in crate::commands::ui) struct CaptureDisconnect(Weak<Mutex<ConnectionOwner>>);
impl CaptureDisconnect {
    pub(super) fn issued(owner: &Arc<Mutex<ConnectionOwner>>) -> Self {
        Self(Arc::downgrade(owner))
    }
    pub(in crate::commands::ui) fn handoff(&self) {
        let slot = self.0.upgrade().and_then(|owner| {
            owner
                .lock()
                .expect("model capture connection")
                .cleanup
                .clone()
        });
        if let Some(slot) = slot {
            slot.retain();
        }
    }
}
