//! Actual provider join ownership for hosts and opt-in component captures.
//! No task is spawned here. A deadline returns the same retained handles.
use super::*;
use std::{
    future::Future,
    pin::Pin,
    task::{Context, Poll},
};

type ActualProviderJoin = TrackedJoin<Result<ModelCaptureCompletion, ProviderCaptureError>>;

#[cfg(test)]
impl ModelCaptureConnection {
    pub(in crate::commands::ui::model_originals) fn poison_cleanup_join_for_test(&self) {
        let slot = self.state.lock().unwrap().cleanup.clone().unwrap();
        assert!(
            std::thread::spawn(move || {
                let _held = slot.join.lock().unwrap();
                panic!("actual cleanup join poison control");
            })
            .join()
            .is_err()
        );
    }
    pub(in crate::commands::ui::model_originals) fn poison_owner_for_test(&self) {
        let owner = self.state.clone();
        assert!(
            std::thread::spawn(move || {
                let _held = owner.lock().unwrap();
                panic!("actual capture owner poison control");
            })
            .join()
            .is_err()
        );
    }
}

enum JoinState {
    Prearmed,
    Awaited(ActualProviderJoin),
    Retained(ActualProviderJoin),
    Draining,
    Joined,
    Abandoned,
}
#[derive(Clone, Copy)]
enum CaptureJoinWait {
    Until(tokio::time::Instant),
    UntilJoined,
}
enum CaptureJoinProgress {
    // Disposal of a previously abandoned handle remains observation-incomplete.
    // This is ownership resolution, never a worker business-success assertion.
    Resolved,
    Pending,
}
pub(super) struct CleanupSlot {
    join: Mutex<JoinState>,
    observation: std::sync::OnceLock<WorkerAttemptObservation>,
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
    #[cfg(test)]
    fn actual_task_id(&self) -> Option<tokio::task::Id> {
        match &*self.join.lock().unwrap() {
            JoinState::Awaited(actual) | JoinState::Retained(actual) => actual.task_id(),
            _ => None,
        }
    }
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
            observation: std::sync::OnceLock::new(),
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
        let _ = self.observation.set(actual.observation());
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
        self.retained_for_drop()
    }
    fn mark_incomplete(&self) {
        if let Some(actual) = self.observation.get() {
            actual.mark_incomplete();
        }
    }
    // Only disposal/draining of this exact retained handle may recover poison.
    // Business polling/start/publication keeps its ordinary refusal boundary.
    fn cleanup_join<T>(&self, action: impl FnOnce(&mut JoinState) -> T) -> T {
        let (result, poisoned) = {
            let (mut state, poisoned) = match self.join.lock() {
                Ok(state) => (state, false),
                Err(poison) => (poison.into_inner(), true),
            };
            (action(&mut state), poisoned)
        };
        if poisoned {
            self.mark_incomplete();
        }
        result
    }
    fn retained_for_drop(&self) -> bool {
        let (retained, poisoned) = {
            let (state, poisoned) = match self.join.lock() {
                Ok(state) => (state, false),
                Err(poison) => (poison.into_inner(), true),
            };
            (
                matches!(*state, JoinState::Retained(_) | JoinState::Draining),
                poisoned,
            )
        };
        if poisoned {
            self.mark_incomplete();
        }
        retained
    }
    fn handoff_on_drop(&self, owner_poisoned: bool) {
        let (retained, join_poisoned) = {
            let (mut state, poisoned) = match self.join.lock() {
                Ok(state) => (state, false),
                Err(poison) => (poison.into_inner(), true),
            };
            if matches!(*state, JoinState::Awaited(_)) {
                let prior = std::mem::replace(&mut *state, JoinState::Prearmed);
                if let JoinState::Awaited(actual) = prior {
                    *state = JoinState::Retained(actual);
                }
            }
            (
                matches!(*state, JoinState::Retained(_) | JoinState::Draining),
                poisoned,
            )
        };
        if owner_poisoned || join_poisoned {
            self.mark_incomplete();
        }
        // Cancellation cannot destroy business payloads or relock a poisoned
        // connection during unwind. The genuine worker still holds its permit.
        if retained {
            self.control.cancel();
        }
    }
    fn owns_handle(&self) -> bool {
        self.cleanup_join(|state| {
            matches!(
                state,
                JoinState::Awaited(_) | JoinState::Retained(_) | JoinState::Draining
            )
        })
    }
    fn is_finished(&self) -> bool {
        match &*self.join.lock().expect("capture cleanup") {
            JoinState::Awaited(join) | JoinState::Retained(join) => join.is_finished(),
            JoinState::Joined | JoinState::Abandoned => true,
            JoinState::Prearmed | JoinState::Draining => false,
        }
    }
    pub(super) fn retain(&self) {
        if self.retained_for_drop() {
            self.control.cancel();
            return;
        }
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
            let (mut owner, poisoned) = match owner.lock() {
                Ok(owner) => (owner, false),
                Err(poison) => (poison.into_inner(), true),
            };
            if owner
                .cleanup
                .as_ref()
                .is_some_and(|slot| std::ptr::eq(slot.as_ref(), self))
            {
                owner.cleanup = None;
            }
            drop(owner);
            if poisoned {
                self.mark_incomplete();
            }
        }
        if let Some(registry) = self.registry.as_ref().and_then(Weak::upgrade) {
            let mut entries = registry.lock().expect("host capture cleanup");
            for entry in &mut entries.entries {
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
        if self.retained_for_drop() {
            return;
        }
        let prior = {
            let mut state = self
                .join
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
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
    async fn drain(self: &Arc<Self>, deadline: tokio::time::Instant) -> CaptureJoinProgress {
        self.wait(CaptureJoinWait::Until(deadline)).await
    }
    async fn wait(self: &Arc<Self>, wait: CaptureJoinWait) -> CaptureJoinProgress {
        self.retain();
        let actual =
            self.cleanup_join(
                |state| match std::mem::replace(state, JoinState::Draining) {
                    JoinState::Retained(join) => Ok(join),
                    prior => {
                        let done = matches!(prior, JoinState::Joined | JoinState::Abandoned);
                        *state = prior;
                        Err(done)
                    }
                },
            );
        let actual = match actual {
            Ok(actual) => actual,
            Err(done) => {
                return if done {
                    CaptureJoinProgress::Resolved
                } else {
                    CaptureJoinProgress::Pending
                };
            }
        };
        let mut guard = DrainGuard {
            slot: self.clone(),
            actual: Some(actual),
        };
        let actual = guard.actual.as_mut().expect("actual owned join");
        let joined = match wait {
            CaptureJoinWait::Until(deadline) => {
                tokio::time::timeout_at(deadline, actual).await.is_ok()
            }
            CaptureJoinWait::UntilJoined => {
                let _outcome = actual.await;
                true
            }
        };
        if !joined {
            // Guard puts the SAME actual join back before returning Pending.
            return CaptureJoinProgress::Pending;
        }
        // Both Ok(body result) and Err(real JoinError) are resolved joins.
        guard.actual = None;
        self.cleanup_join(|state| *state = JoinState::Joined);
        self.retire();
        CaptureJoinProgress::Resolved
    }
}
struct DrainGuard {
    slot: Arc<CleanupSlot>,
    actual: Option<ActualProviderJoin>,
}
impl Drop for DrainGuard {
    fn drop(&mut self) {
        if let Some(actual) = self.actual.take() {
            let unexpected = self.slot.cleanup_join(|state| {
                if matches!(state, JoinState::Draining) {
                    *state = JoinState::Retained(actual);
                    None
                } else {
                    Some(actual)
                }
            });
            if let Some(actual) = unexpected {
                self.slot.mark_incomplete();
                drop(actual); // Explicit abandonment, never a joined outcome.
            }
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

// Standalone/storage connections keep their historical direct waiter ownership.
// A host registry retains provider tasks independently of observation.
pub(super) enum ProviderJoin {
    Direct(ActualProviderJoin),
    Owned {
        slot: Arc<CleanupSlot>,
        observation: WorkerAttemptObservation,
    },
}
impl ProviderJoin {
    pub(super) fn retained_for_drop(&self) -> bool {
        match self {
            Self::Owned { slot, .. } => slot.retained_for_drop(),
            Self::Direct(_) => false,
        }
    }
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
// Entries drop before returning their backing table's metadata credit.
struct CleanupEntries {
    entries: [Option<Arc<CleanupSlot>>; MAX_HOST_CAPTURES],
    _infrastructure_credit: RetainedEvidenceCredit,
}
#[derive(Clone)]
pub(in crate::commands::ui) struct CleanupRegistry(Arc<Mutex<CleanupEntries>>);
impl CleanupRegistry {
    pub(in crate::commands::ui) fn new(
        capacity: &HostModelCaptureCapacity,
    ) -> Result<Self, CaptureError> {
        let bytes = std::mem::size_of::<Mutex<CleanupEntries>>()
            .checked_add(2 * std::mem::size_of::<usize>())
            .ok_or(CaptureError::Capacity)?;
        let credit = capacity.reserve_evidence(bytes)?;
        Ok(Self(Arc::new(Mutex::new(CleanupEntries {
            entries: std::array::from_fn(|_| None),
            _infrastructure_credit: credit,
        }))))
    }
    #[cfg(test)]
    pub(in crate::commands::ui) fn retained_metadata_bytes(&self) -> usize {
        self.0
            .lock()
            .expect("host capture cleanup")
            ._infrastructure_credit
            .retained_bytes()
    }
    fn insert(&self, slot: &Arc<CleanupSlot>) -> Result<(), CaptureError> {
        let mut entries = self.0.lock().expect("host capture cleanup");
        let entry = entries
            .entries
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
    #[cfg(test)]
    pub(in crate::commands::ui) fn retained_metadata_bytes(&self) -> usize {
        self.0.retained_metadata_bytes()
    }
    pub(in crate::commands::ui) fn retained_handles(&self) -> usize {
        self.0
            .0
            .lock()
            .expect("host capture cleanup")
            .entries
            .iter()
            .flatten()
            .filter(|slot| slot.retained())
            .count()
    }
    pub(in crate::commands::ui) async fn drain(
        self,
        deadline: tokio::time::Instant,
    ) -> Result<(), PendingCaptureCleanup> {
        self.into_pending().drain(deadline).await
    }
    pub(in crate::commands::ui) fn into_pending(self) -> PendingCaptureCleanup {
        PendingCaptureCleanup {
            owner: CleanupOwner::Host(self.0),
        }
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
    pub(in crate::commands::ui) async fn join_retained(&mut self) -> Result<(), CaptureError> {
        loop {
            if matches!(
                self.wait_retained(CaptureJoinWait::UntilJoined).await,
                CaptureJoinProgress::Resolved
            ) {
                return Ok(());
            }
            // Prearmed or concurrently Draining is still owned, never joined.
            tokio::task::yield_now().await;
        }
    }
    #[cfg(test)]
    pub(in crate::commands::ui) fn retained_metadata_bytes(&self) -> usize {
        match &self.owner {
            CleanupOwner::Single(_) => 0,
            CleanupOwner::Host(registry) => registry.retained_metadata_bytes(),
        }
    }
    #[cfg(test)]
    pub(in crate::commands::ui) fn actual_task_id(&self) -> Option<tokio::task::Id> {
        match &self.owner {
            CleanupOwner::Single(slot) => slot.as_ref().and_then(|slot| slot.actual_task_id()),
            CleanupOwner::Host(registry) => registry
                .0
                .lock()
                .unwrap()
                .entries
                .iter()
                .flatten()
                .find_map(|slot| slot.actual_task_id()),
        }
    }
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
                .entries
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
        match self.drain_retained(deadline).await {
            Ok(()) => Ok(()),
            Err(_) => Err(self),
        }
    }
    /// Borrow the same owner so dropping a caller future cannot drop its token.
    /// DrainGuard returns an interrupted actual join to this owner's slot.
    pub(in crate::commands::ui) async fn drain_retained(
        &mut self,
        deadline: tokio::time::Instant,
    ) -> Result<(), CaptureError> {
        match self.wait_retained(CaptureJoinWait::Until(deadline)).await {
            CaptureJoinProgress::Resolved => Ok(()),
            CaptureJoinProgress::Pending => Err(CaptureError::Timeout),
        }
    }
    async fn wait_retained(&mut self, wait: CaptureJoinWait) -> CaptureJoinProgress {
        // The Host variant retains the SAME fixed table, not a separately
        // allocated snapshot or new task. Caller must quiesce new dispatch.
        for index in 0..MAX_HOST_CAPTURES {
            let slot = match &self.owner {
                CleanupOwner::Single(slot) if index == 0 => slot.clone(),
                CleanupOwner::Single(_) => None,
                CleanupOwner::Host(registry) => {
                    registry.0.lock().expect("host capture cleanup").entries[index].clone()
                }
            };
            if let Some(slot) = slot {
                let joined = match wait {
                    CaptureJoinWait::Until(deadline) => slot.drain(deadline).await,
                    CaptureJoinWait::UntilJoined => slot.wait(wait).await,
                };
                if matches!(joined, CaptureJoinProgress::Pending) {
                    return CaptureJoinProgress::Pending;
                }
                if let CleanupOwner::Single(entry) = &mut self.owner {
                    *entry = None;
                }
            }
        }
        CaptureJoinProgress::Resolved
    }
}
pub(in crate::commands::ui) struct CaptureDisconnect {
    owner: Weak<Mutex<ConnectionOwner>>,
    observation: WorkerConnectionObservation,
}
impl CaptureDisconnect {
    fn slot_for_drop(&self) -> (Option<Arc<CleanupSlot>>, bool) {
        let Some(owner) = self.owner.upgrade() else {
            return (None, false);
        };
        let (slot, poisoned) = {
            let (state, poisoned) = match owner.lock() {
                Ok(state) => (state, false),
                Err(poison) => (poison.into_inner(), true),
            };
            (state.cleanup.clone(), poisoned)
        };
        if poisoned {
            self.observation.mark_incomplete();
        }
        (slot, poisoned)
    }
    pub(super) fn should_close_on_drop(&self) -> bool {
        let (slot, poisoned) = self.slot_for_drop();
        if poisoned {
            return false;
        }
        !slot.is_some_and(|slot| slot.retained_for_drop())
    }
    pub(in crate::commands::ui) fn handoff_on_drop(&self) {
        let (slot, poisoned) = self.slot_for_drop();
        if let Some(slot) = slot {
            slot.handoff_on_drop(poisoned);
        }
    }
    pub(super) fn issued(
        owner: &Arc<Mutex<ConnectionOwner>>,
        observation: &WorkerConnectionObservation,
    ) -> Self {
        Self {
            owner: Arc::downgrade(owner),
            observation: observation.clone(),
        }
    }
}

#[cfg(test)]
mod registry_funding_tests;
