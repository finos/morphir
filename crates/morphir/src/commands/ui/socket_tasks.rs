//! Actual upgraded-task ownership, independent of socket events and captures.

use super::model_originals::{HostModelCaptureCapacity, RetainedEvidenceCredit};
use std::{
    future::Future,
    pin::Pin,
    sync::{Arc, Mutex, MutexGuard},
    task::{Context, Poll, Waker},
};
use tokio::{
    task::{JoinError, JoinHandle},
    time::Instant,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands::ui) enum SocketCleanupError {
    Capacity,
    Allocation,
    SizeOverflow,
    Closed,
    Poisoned,
    TaskPanicked,
    TaskCancelled,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands::ui) enum SocketDrainOutcome {
    Joined,
    JoinedWithFault(SocketCleanupError),
    Pending {
        first_fault: Option<SocketCleanupError>,
    },
}
/// The one actual cleanup owner stays in Pending through any interrupted await.
pub(in crate::commands::ui) enum SocketCleanup {
    Pending(HostSocketCleanupOwner),
    Joined,
    JoinedWithFault(SocketCleanupError),
}
impl SocketCleanup {
    pub(in crate::commands::ui) async fn join(&mut self) -> SocketDrainOutcome {
        let outcome = match self {
            Self::Pending(owner) => owner.join().await,
            Self::Joined => SocketDrainOutcome::Joined,
            Self::JoinedWithFault(fault) => SocketDrainOutcome::JoinedWithFault(*fault),
        };
        self.record_outcome(outcome);
        outcome
    }
    fn record_outcome(&mut self, outcome: SocketDrainOutcome) {
        match outcome {
            SocketDrainOutcome::Joined => *self = Self::Joined,
            SocketDrainOutcome::JoinedWithFault(fault) => *self = Self::JoinedWithFault(fault),
            SocketDrainOutcome::Pending { .. } => {}
        }
    }
    #[cfg(test)]
    pub(in crate::commands::ui) fn retained_metadata_bytes(&self) -> usize {
        match self {
            Self::Pending(owner) => owner.retained_metadata_bytes(),
            _ => 0,
        }
    }
    pub(in crate::commands::ui) fn stop_accepting_upgrades(&mut self) {
        if let Self::Pending(owner) = self {
            owner.stop_accepting_upgrades();
        }
    }
    pub(in crate::commands::ui) async fn drain(&mut self, deadline: Instant) -> SocketDrainOutcome {
        let outcome = match self {
            Self::Pending(owner) => owner.drain(deadline).await,
            Self::Joined => SocketDrainOutcome::Joined,
            Self::JoinedWithFault(fault) => SocketDrainOutcome::JoinedWithFault(*fault),
        };
        self.record_outcome(outcome);
        outcome
    }
    #[cfg(test)]
    pub(in crate::commands::ui) fn owner_mut(&mut self) -> Option<&mut HostSocketCleanupOwner> {
        match self {
            Self::Pending(owner) => Some(owner),
            _ => None,
        }
    }
}
enum Acceptance {
    Open,
    Stopping,
    Abandoned,
}
#[derive(Clone, Copy)]
enum SocketStop {
    NotRequested,
    Requested,
}
struct SocketTask {
    actual: JoinHandle<()>,
    stop: SocketStop,
}
impl SocketTask {
    fn is_finished(&self) -> bool {
        self.actual.is_finished()
    }
    fn abort(&self) {
        self.actual.abort();
    }
    fn request_stop(&mut self) {
        // An already terminal, unexpectedly cancelled task keeps its original
        // classification. This mark travels with this SAME handle through any
        // checked-out guard and interrupted drain; global host state cannot
        // relabel a terminal join checked out by another reaper.
        if !self.actual.is_finished() {
            self.stop = SocketStop::Requested;
            self.actual.abort();
        }
    }
    #[cfg(test)]
    fn id(&self) -> tokio::task::Id {
        self.actual.id()
    }
}
enum TaskSlot {
    Vacant,
    Retained(SocketTask),
    Draining,
}
struct SocketTaskState {
    acceptance: Acceptance,
    slots: Vec<TaskSlot>,
    fault: Option<SocketCleanupError>,
    capacity: HostModelCaptureCapacity,
    _infrastructure_credit: RetainedEvidenceCredit,
    table_credit: Option<RetainedEvidenceCredit>,
    #[cfg(test)]
    panic_trigger: Arc<tokio::sync::Notify>,
}
impl SocketTaskState {
    fn fail(&mut self, fault: SocketCleanupError) {
        self.fault.get_or_insert(fault);
        if matches!(self.acceptance, Acceptance::Open) {
            self.acceptance = Acceptance::Stopping;
        }
    }
    fn vacant_slot(&mut self) -> Result<usize, SocketCleanupError> {
        if let Some(index) = self
            .slots
            .iter()
            .position(|slot| matches!(slot, TaskSlot::Vacant))
        {
            return Ok(index);
        }
        if self.slots.len() == self.slots.capacity() {
            let old = self.slots.capacity();
            let requested = if old == 0 {
                1
            } else {
                old.checked_mul(2).ok_or(SocketCleanupError::SizeOverflow)?
            };
            let bytes = requested
                .checked_mul(std::mem::size_of::<TaskSlot>())
                .ok_or(SocketCleanupError::SizeOverflow)?;
            // Fund the WHOLE replacement before allocation while the old table
            // and its credit remain held. A refused excess destroys only the
            // empty replacement; existing actual handles never move or detach.
            let mut credit = self
                .capacity
                .reserve_evidence(bytes)
                .map_err(|_| SocketCleanupError::Capacity)?;
            let mut replacement = Vec::new();
            replacement
                .try_reserve_exact(requested)
                .map_err(|_| SocketCleanupError::Allocation)?;
            let excess = replacement
                .capacity()
                .checked_sub(requested)
                .and_then(|count| count.checked_mul(std::mem::size_of::<TaskSlot>()))
                .ok_or(SocketCleanupError::SizeOverflow)?;
            credit
                .grow(excess)
                .map_err(|_| SocketCleanupError::Capacity)?;
            replacement.append(&mut self.slots);
            let old_table = std::mem::replace(&mut self.slots, replacement);
            drop(old_table);
            self.table_credit = Some(credit);
        }
        let index = self.slots.len();
        self.slots.push(TaskSlot::Vacant);
        Ok(index)
    }
}

#[derive(Clone)]
pub(in crate::commands::ui) struct SocketTaskRegistry(Arc<Mutex<SocketTaskState>>);
impl SocketTaskRegistry {
    pub(in crate::commands::ui) fn new(
        capacity: &HostModelCaptureCapacity,
    ) -> Result<(Self, HostSocketCleanupOwner), SocketCleanupError> {
        let bytes = std::mem::size_of::<Mutex<SocketTaskState>>()
            .checked_add(2 * std::mem::size_of::<usize>())
            .ok_or(SocketCleanupError::SizeOverflow)?;
        let credit = capacity
            .reserve_evidence(bytes)
            .map_err(|_| SocketCleanupError::Capacity)?;
        let registry = Self(Arc::new(Mutex::new(SocketTaskState {
            acceptance: Acceptance::Open,
            slots: Vec::new(),
            fault: None,
            capacity: capacity.clone(),
            _infrastructure_credit: credit,
            table_credit: None,
            #[cfg(test)]
            panic_trigger: Arc::new(tokio::sync::Notify::new()),
        })));
        let owner = HostSocketCleanupOwner {
            registry: registry.clone(),
        };
        Ok((registry, owner))
    }
    fn state(&self) -> MutexGuard<'_, SocketTaskState> {
        self.0.lock().unwrap_or_else(|poison| {
            let mut state = poison.into_inner();
            state.fail(SocketCleanupError::Poisoned);
            state
        })
    }
    pub(in crate::commands::ui) fn spawn_upgrade<F>(
        &self,
        actual: F,
    ) -> Result<(), SocketCleanupError>
    where
        F: Future<Output = ()> + Send + 'static,
    {
        self.reap_finished();
        let mut state = self.state();
        if !matches!(state.acceptance, Acceptance::Open) {
            return Err(state.fault.unwrap_or(SocketCleanupError::Closed));
        }
        let index = state.vacant_slot()?;
        #[cfg(test)]
        let actual = {
            let trigger = state.panic_trigger.clone();
            async move {
                tokio::select! {
                    () = actual => {},
                    () = trigger.notified() => panic!("actual whole upgrade task test panic"),
                }
            }
        };
        // Closure and spawn/install are serialized by this SAME lock. The
        // spawned future never receives registry-lock authority.
        let actual = tokio::spawn(actual);
        state.slots[index] = TaskSlot::Retained(SocketTask {
            actual,
            stop: SocketStop::NotRequested,
        });
        Ok(())
    }
    fn checkout(&self, index: usize, only_finished: bool) -> Option<CheckedOut<'_>> {
        let mut state = self.state();
        let slot = state.slots.get_mut(index)?;
        if !matches!(slot, TaskSlot::Retained(actual) if !only_finished || actual.is_finished()) {
            return None;
        }
        match std::mem::replace(slot, TaskSlot::Draining) {
            TaskSlot::Retained(actual) => Some(CheckedOut {
                registry: self,
                index,
                actual: Some(actual),
            }),
            _ => unreachable!("checked retained task"),
        }
    }
    fn reap_finished(&self) {
        let length = self.state().slots.len();
        for index in 0..length {
            if let Some(mut checked) = self.checkout(index, true) {
                let mut context = Context::from_waker(Waker::noop());
                // is_finished is only a hint. Retirement consumes an ACTUAL
                // Ready join, including final future destruction and panic.
                if let Poll::Ready(result) =
                    Pin::new(&mut checked.actual.as_mut().unwrap().actual).poll(&mut context)
                {
                    checked.finish(result);
                }
            }
        }
    }
}

struct CheckedOut<'a> {
    registry: &'a SocketTaskRegistry,
    index: usize,
    actual: Option<SocketTask>,
}
impl CheckedOut<'_> {
    fn finish(mut self, result: Result<(), JoinError>) {
        let actual = self.actual.take().expect("same checked-out task");
        let mut state = self.registry.state();
        state.slots[self.index] = TaskSlot::Vacant;
        if let Err(error) = &result {
            if error.is_panic() {
                state.fail(SocketCleanupError::TaskPanicked);
            } else if matches!(actual.stop, SocketStop::NotRequested) {
                state.fail(SocketCleanupError::TaskCancelled);
            }
        }
        drop(state);
        drop(actual);
        drop(result);
    }
}
impl Drop for CheckedOut<'_> {
    fn drop(&mut self) {
        if let Some(actual) = self.actual.take() {
            let mut state = self.registry.state();
            if matches!(state.acceptance, Acceptance::Abandoned) {
                actual.abort();
                state.slots[self.index] = TaskSlot::Vacant;
                drop(state);
                drop(actual);
            } else {
                state.slots[self.index] = TaskSlot::Retained(actual);
            }
        }
    }
}

/// Issued once at construction. Registry clones cannot issue cleanup owners.
pub(in crate::commands::ui) struct HostSocketCleanupOwner {
    registry: SocketTaskRegistry,
}
impl HostSocketCleanupOwner {
    #[cfg(test)]
    pub(in crate::commands::ui) fn retained_metadata_bytes(&self) -> usize {
        let state = self.registry.state();
        state
            ._infrastructure_credit
            .retained_bytes()
            .checked_add(
                state
                    .table_credit
                    .as_ref()
                    .map_or(0, RetainedEvidenceCredit::retained_bytes),
            )
            .expect("held credit subset fits SAME finite host metadata ledger")
    }
    #[cfg(test)]
    pub(in crate::commands::ui) fn tasks_finished(&self) -> bool {
        self.registry.state().slots.iter().all(|slot| match slot {
            TaskSlot::Vacant => true,
            TaskSlot::Retained(task) => task.is_finished(),
            TaskSlot::Draining => false,
        })
    }
    #[cfg(test)]
    pub(in crate::commands::ui) fn panic_tasks(&self) {
        let trigger = self.registry.state().panic_trigger.clone();
        trigger.notify_waiters();
    }
    pub(in crate::commands::ui) fn stop_accepting_upgrades(&mut self) {
        let mut state = self.registry.state();
        if matches!(state.acceptance, Acceptance::Open) {
            state.acceptance = Acceptance::Stopping;
        }
    }
    pub(in crate::commands::ui) fn retained_tasks(&self) -> usize {
        self.registry
            .state()
            .slots
            .iter()
            .filter(|slot| !matches!(slot, TaskSlot::Vacant))
            .count()
    }
    pub(in crate::commands::ui) fn pending_drain(&mut self) -> PendingSocketDrain<'_> {
        self.stop_accepting_upgrades();
        PendingSocketDrain { owner: self }
    }
    pub(in crate::commands::ui) async fn drain(&mut self, deadline: Instant) -> SocketDrainOutcome {
        self.pending_drain().wait(deadline).await
    }
    pub(in crate::commands::ui) async fn join(&mut self) -> SocketDrainOutcome {
        loop {
            let outcome = self
                .pending_drain()
                .finish(SocketJoinWait::UntilJoined)
                .await;
            if !matches!(outcome, SocketDrainOutcome::Pending { .. }) {
                return outcome;
            }
            // Another synchronous reaper can still have a handle checked out.
            // It must restore or resolve that SAME handle before completion.
            tokio::task::yield_now().await;
        }
    }
}
impl Drop for HostSocketCleanupOwner {
    fn drop(&mut self) {
        let length = {
            let mut state = self.registry.state();
            state.acceptance = Acceptance::Abandoned;
            state.slots.len()
        };
        for index in 0..length {
            let actual = {
                let mut state = self.registry.state();
                match &mut state.slots[index] {
                    TaskSlot::Retained(_) => {
                        match std::mem::replace(&mut state.slots[index], TaskSlot::Vacant) {
                            TaskSlot::Retained(actual) => Some(actual),
                            _ => unreachable!("retained handle"),
                        }
                    }
                    _ => None,
                }
            };
            if let Some(actual) = actual {
                actual.abort();
                // Raw Drop is containment/abandonment, never a join result.
                drop(actual);
            }
        }
    }
}

/// Cancelling this borrowed drain restores every checked-out actual handle.
pub(in crate::commands::ui) struct PendingSocketDrain<'a> {
    owner: &'a mut HostSocketCleanupOwner,
}
#[derive(Clone, Copy)]
enum SocketJoinWait {
    Until(Instant),
    UntilJoined,
}
impl PendingSocketDrain<'_> {
    pub(in crate::commands::ui) async fn wait(self, deadline: Instant) -> SocketDrainOutcome {
        self.finish(SocketJoinWait::Until(deadline)).await
    }
    async fn finish(self, wait: SocketJoinWait) -> SocketDrainOutcome {
        let registry = &self.owner.registry;
        let length = {
            let mut state = registry.state();
            for slot in &mut state.slots {
                if let TaskSlot::Retained(actual) = slot {
                    actual.request_stop();
                }
            }
            state.slots.len()
        };
        for index in 0..length {
            if let Some(mut checked) = registry.checkout(index, false) {
                let actual = &mut checked.actual.as_mut().unwrap().actual;
                let outcome = match wait {
                    SocketJoinWait::Until(deadline) => {
                        tokio::time::timeout_at(deadline, actual).await.ok()
                    }
                    SocketJoinWait::UntilJoined => Some(actual.await),
                };
                if let Some(result) = outcome {
                    checked.finish(result);
                }
                // Deadline/cancellation drops the guard, restoring SAME join.
            }
        }
        let state = registry.state();
        if state
            .slots
            .iter()
            .any(|slot| !matches!(slot, TaskSlot::Vacant))
        {
            SocketDrainOutcome::Pending {
                first_fault: state.fault,
            }
        } else {
            match state.fault {
                Some(fault) => SocketDrainOutcome::JoinedWithFault(fault),
                None => SocketDrainOutcome::Joined,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::commands::ui::model_originals::HostModelCaptureCapacity;
    use std::sync::Arc;
    use tokio::{
        sync::Notify,
        time::{Duration, Instant},
    };

    #[tokio::test]
    async fn socket_tasks_close_joins_the_actual_pending_task() {
        let capacity = HostModelCaptureCapacity::default();
        let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
        let entered = Arc::new(Notify::new());
        let task_entered = entered.clone();
        registry
            .spawn_upgrade(async move {
                task_entered.notify_one();
                std::future::pending::<()>().await;
            })
            .unwrap();
        entered.notified().await;
        assert_eq!(owner.retained_tasks(), 1);
        assert_eq!(
            owner.drain(Instant::now() + Duration::from_secs(1)).await,
            SocketDrainOutcome::Joined
        );
        assert_eq!(owner.retained_tasks(), 0);
        assert!(matches!(
            registry.spawn_upgrade(async {}),
            Err(SocketCleanupError::Closed)
        ));
        assert!(capacity.usage().metadata_bytes() > 0);
        drop(owner);
        drop(registry);
        assert_eq!(capacity.usage().metadata_bytes(), 0);
    }

    struct Release(Arc<(std::sync::Mutex<bool>, std::sync::Condvar)>);
    impl Release {
        fn new() -> Self {
            Self(Arc::new((
                std::sync::Mutex::new(false),
                std::sync::Condvar::new(),
            )))
        }
        fn release(&self) {
            let (lock, changed) = &*self.0;
            *lock.lock().unwrap() = true;
            changed.notify_all();
        }
    }
    impl Drop for Release {
        fn drop(&mut self) {
            self.release();
        }
    }
    struct HeldFinalDrop {
        entered: Arc<Notify>,
        release: Arc<(std::sync::Mutex<bool>, std::sync::Condvar)>,
    }
    impl Drop for HeldFinalDrop {
        fn drop(&mut self) {
            self.entered.notify_one();
            let (lock, changed) = &*self.release;
            let mut released = lock.lock().unwrap();
            while !*released {
                released = changed.wait(released).unwrap();
            }
        }
    }
    fn held_task(registry: &SocketTaskRegistry, release: &Release, entered: Arc<Notify>) {
        let final_drop = HeldFinalDrop {
            entered,
            release: release.0.clone(),
        };
        registry
            .spawn_upgrade(async move {
                drop(final_drop);
            })
            .unwrap();
    }
    fn first_id(registry: &SocketTaskRegistry) -> tokio::task::Id {
        match &registry.state().slots[0] {
            TaskSlot::Retained(actual) => actual.id(),
            _ => panic!("expected the actual retained task"),
        }
    }
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn socket_tasks_deadline_preserves_handle_until_final_destruction() {
        let capacity = HostModelCaptureCapacity::default();
        let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
        let release = Release::new();
        let entered = Arc::new(Notify::new());
        held_task(&registry, &release, entered.clone());
        entered.notified().await;
        let id = first_id(&registry);
        assert_eq!(
            owner
                .drain(Instant::now() + Duration::from_millis(20))
                .await,
            SocketDrainOutcome::Pending { first_fault: None }
        );
        assert_eq!(owner.retained_tasks(), 1);
        assert_eq!(first_id(&registry), id);
        release.release();
        assert_eq!(
            owner.drain(Instant::now() + Duration::from_secs(1)).await,
            SocketDrainOutcome::Joined
        );
        assert_eq!(owner.retained_tasks(), 0);
    }
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn socket_tasks_cancelled_borrowed_drain_restores_same_handle() {
        let capacity = HostModelCaptureCapacity::default();
        let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
        let release = Release::new();
        let entered = Arc::new(Notify::new());
        held_task(&registry, &release, entered.clone());
        entered.notified().await;
        let id = first_id(&registry);
        {
            let drain = owner.drain(Instant::now() + Duration::from_secs(1));
            tokio::pin!(drain);
            std::future::poll_fn(|cx| {
                assert!(drain.as_mut().poll(cx).is_pending());
                Poll::Ready(())
            })
            .await;
        }
        assert_eq!(owner.retained_tasks(), 1);
        assert_eq!(first_id(&registry), id);
        release.release();
        assert_eq!(
            owner.drain(Instant::now() + Duration::from_secs(1)).await,
            SocketDrainOutcome::Joined
        );
    }
    struct Destroyed(Arc<std::sync::atomic::AtomicBool>);
    impl Drop for Destroyed {
        fn drop(&mut self) {
            self.0.store(true, std::sync::atomic::Ordering::SeqCst);
        }
    }
    #[tokio::test]
    async fn socket_tasks_panic_is_sticky_and_other_actual_tasks_are_joined() {
        let capacity = HostModelCaptureCapacity::default();
        let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
        let entered = Arc::new(Notify::new());
        let task_entered = entered.clone();
        let release_panic = Arc::new(Notify::new());
        let task_release = release_panic.clone();
        registry
            .spawn_upgrade(async move {
                task_release.notified().await;
                task_entered.notify_one();
                panic!("actual socket task panic");
            })
            .unwrap();
        let destroyed = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let guard = Destroyed(destroyed.clone());
        registry
            .spawn_upgrade(async move {
                let _guard = guard;
                std::future::pending::<()>().await;
            })
            .unwrap();
        assert_eq!(owner.retained_tasks(), 2);
        release_panic.notify_one();
        tokio::time::timeout(Duration::from_secs(1), entered.notified())
            .await
            .unwrap();
        assert_eq!(
            owner.drain(Instant::now() + Duration::from_secs(1)).await,
            SocketDrainOutcome::JoinedWithFault(SocketCleanupError::TaskPanicked)
        );
        assert!(destroyed.load(std::sync::atomic::Ordering::SeqCst));
        assert_eq!(owner.retained_tasks(), 0);
        assert_eq!(
            owner.drain(Instant::now() + Duration::from_secs(1)).await,
            SocketDrainOutcome::JoinedWithFault(SocketCleanupError::TaskPanicked)
        );
    }
    #[tokio::test]
    async fn socket_tasks_poison_stays_faulted_but_drains_actual_tasks() {
        let capacity = HostModelCaptureCapacity::default();
        let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
        registry.spawn_upgrade(std::future::pending()).unwrap();
        let poison = registry.clone();
        let actual = tokio::spawn(async move {
            let _held = poison.0.lock().unwrap();
            panic!("actual registry lock unwind");
        });
        assert!(actual.await.unwrap_err().is_panic());
        assert_eq!(
            owner.drain(Instant::now() + Duration::from_secs(1)).await,
            SocketDrainOutcome::JoinedWithFault(SocketCleanupError::Poisoned)
        );
        assert_eq!(owner.retained_tasks(), 0);
        assert_eq!(
            owner.drain(Instant::now() + Duration::from_secs(1)).await,
            SocketDrainOutcome::JoinedWithFault(SocketCleanupError::Poisoned)
        );
    }
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn socket_tasks_close_race_never_loses_an_accepted_handle() {
        let capacity = HostModelCaptureCapacity::default();
        let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
        let race = Arc::new(tokio::sync::Barrier::new(2));
        let task_race = race.clone();
        let admission = registry.clone();
        let destroyed = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let guard = Destroyed(destroyed.clone());
        let caller = tokio::spawn(async move {
            task_race.wait().await;
            admission.spawn_upgrade(async move {
                let _guard = guard;
                std::future::pending::<()>().await;
            })
        });
        race.wait().await;
        owner.stop_accepting_upgrades();
        let accepted = caller.await.unwrap();
        match accepted {
            Ok(()) => assert_eq!(owner.retained_tasks(), 1),
            Err(SocketCleanupError::Closed) => assert_eq!(owner.retained_tasks(), 0),
            other => panic!("unexpected admission result: {other:?}"),
        }
        assert_eq!(
            owner.drain(Instant::now() + Duration::from_secs(1)).await,
            SocketDrainOutcome::Joined
        );
        assert_eq!(owner.retained_tasks(), 0);
        assert!(destroyed.load(std::sync::atomic::Ordering::SeqCst));
    }
    #[tokio::test]
    async fn socket_tasks_failed_growth_keeps_existing_funded_handle() {
        let header =
            std::mem::size_of::<Mutex<SocketTaskState>>() + 2 * std::mem::size_of::<usize>();
        let bound = header + std::mem::size_of::<TaskSlot>();
        let capacity = HostModelCaptureCapacity::with_metadata_limit(bound);
        let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
        registry.spawn_upgrade(std::future::pending()).unwrap();
        let id = first_id(&registry);
        assert_eq!(
            registry.spawn_upgrade(async {}),
            Err(SocketCleanupError::Capacity)
        );
        assert_eq!(first_id(&registry), id);
        assert_eq!(owner.retained_tasks(), 1);
        assert!(capacity.usage().metadata_bytes() <= bound);
        assert_eq!(
            owner.drain(Instant::now() + Duration::from_secs(1)).await,
            SocketDrainOutcome::Joined
        );
        assert_eq!(owner.retained_tasks(), 0);
    }
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn socket_tasks_pending_panic_and_resolved_panic_are_distinct() {
        let capacity = HostModelCaptureCapacity::default();
        let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
        let panic_release = Arc::new(Notify::new());
        let actual_release = panic_release.clone();
        let panicking = Arc::new(Notify::new());
        let actual_panicking = panicking.clone();
        registry
            .spawn_upgrade(async move {
                actual_release.notified().await;
                actual_panicking.notify_one();
                panic!("actual sticky panic alongside unresolved task");
            })
            .unwrap();
        let release = Release::new();
        let entered = Arc::new(Notify::new());
        held_task(&registry, &release, entered.clone());
        entered.notified().await;
        panic_release.notify_one();
        panicking.notified().await;
        assert_eq!(
            owner
                .drain(Instant::now() + Duration::from_millis(20))
                .await,
            SocketDrainOutcome::Pending {
                first_fault: Some(SocketCleanupError::TaskPanicked)
            }
        );
        assert_eq!(owner.retained_tasks(), 1);
        release.release();
        assert_eq!(
            owner.drain(Instant::now() + Duration::from_secs(1)).await,
            SocketDrainOutcome::JoinedWithFault(SocketCleanupError::TaskPanicked)
        );
        assert_eq!(owner.retained_tasks(), 0);
    }
    #[tokio::test]
    async fn socket_tasks_zero_metadata_refuses_before_body() {
        let capacity = HostModelCaptureCapacity::with_metadata_limit(0);
        assert!(matches!(
            SocketTaskRegistry::new(&capacity),
            Err(SocketCleanupError::Capacity)
        ));
        assert_eq!(capacity.usage().metadata_bytes(), 0);
    }
    #[tokio::test]
    async fn socket_tasks_slot_metadata_refuses_before_actual_spawn() {
        let header =
            std::mem::size_of::<Mutex<SocketTaskState>>() + 2 * std::mem::size_of::<usize>();
        let capacity = HostModelCaptureCapacity::with_metadata_limit(header);
        let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
        let ran = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let task_ran = ran.clone();
        assert_eq!(
            registry.spawn_upgrade(async move {
                task_ran.store(true, std::sync::atomic::Ordering::SeqCst);
            }),
            Err(SocketCleanupError::Capacity)
        );
        tokio::task::yield_now().await;
        assert!(!ran.load(std::sync::atomic::Ordering::SeqCst));
        assert_eq!(owner.retained_tasks(), 0);
        assert_eq!(
            owner.drain(Instant::now() + Duration::from_secs(1)).await,
            SocketDrainOutcome::Joined
        );
    }
    #[tokio::test]
    async fn socket_tasks_completed_slots_are_reaped_and_reused_while_open() {
        let capacity = HostModelCaptureCapacity::default();
        let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
        registry.spawn_upgrade(async {}).unwrap();
        while !matches!(&registry.state().slots[0], TaskSlot::Retained(actual) if actual.is_finished())
        {
            tokio::task::yield_now().await;
        }
        let funded = capacity.usage().metadata_bytes();
        let next_entered = Arc::new(Notify::new());
        let entered = next_entered.clone();
        registry
            .spawn_upgrade(async move {
                entered.notify_one();
                std::future::pending::<()>().await;
            })
            .unwrap();
        next_entered.notified().await;
        assert_eq!(capacity.usage().metadata_bytes(), funded);
        assert_eq!(owner.retained_tasks(), 1);
        assert_eq!(registry.state().slots.len(), 1);
        assert_eq!(
            owner.drain(Instant::now() + Duration::from_secs(1)).await,
            SocketDrainOutcome::Joined
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn socket_tasks_interrupted_stop_preserves_task_cancellation_classification() {
        let capacity = HostModelCaptureCapacity::default();
        let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
        let release = Release::new();
        let destroying = Arc::new(Notify::new());
        let final_drop = HeldFinalDrop {
            entered: destroying.clone(),
            release: release.0.clone(),
        };
        let started = Arc::new(Notify::new());
        let task_started = started.clone();
        registry
            .spawn_upgrade(async move {
                let _held = final_drop;
                task_started.notify_one();
                std::future::pending::<()>().await;
            })
            .unwrap();
        tokio::time::timeout(Duration::from_secs(1), started.notified())
            .await
            .unwrap();
        let id = first_id(&registry);
        {
            let drain = owner.drain(Instant::now() + Duration::from_secs(1));
            tokio::pin!(drain);
            std::future::poll_fn(|cx| {
                assert!(drain.as_mut().poll(cx).is_pending());
                Poll::Ready(())
            })
            .await;
            // The real abort is now destroying this actual task's future.
            tokio::time::timeout(Duration::from_secs(1), destroying.notified())
                .await
                .unwrap();
        }
        let restored_id = first_id(&registry);
        release.release();
        tokio::time::timeout(Duration::from_secs(1), async {
            loop {
                if matches!(&registry.state().slots[0], TaskSlot::Retained(actual) if actual.is_finished()) { break; }
                tokio::task::yield_now().await;
            }
        }).await.unwrap();
        // Rejected ingress still opportunistically reaps the terminal handle.
        let refused = registry.spawn_upgrade(async {});
        let retried = owner.drain(Instant::now() + Duration::from_secs(1)).await;
        let remaining = owner.retained_tasks();
        drop(owner);
        drop(registry);
        assert_eq!(restored_id, id);
        assert_eq!(remaining, 0);
        assert_eq!(refused, Err(SocketCleanupError::Closed));
        assert_eq!(retried, SocketDrainOutcome::Joined);

        // A genuinely unexpected abort must remain distinguishable.
        let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
        registry.spawn_upgrade(std::future::pending()).unwrap();
        match &registry.state().slots[0] {
            TaskSlot::Retained(actual) => actual.abort(),
            _ => panic!("actual retained task"),
        }
        tokio::time::timeout(Duration::from_secs(1), async {
            loop {
                if matches!(&registry.state().slots[0], TaskSlot::Retained(actual) if actual.is_finished()) { break; }
                tokio::task::yield_now().await;
            }
        }).await.unwrap();
        let refused = registry.spawn_upgrade(async {});
        let retried = owner.drain(Instant::now() + Duration::from_secs(1)).await;
        let remaining = owner.retained_tasks();
        drop(owner);
        drop(registry);
        assert_eq!(remaining, 0);
        assert_eq!(refused, Err(SocketCleanupError::TaskCancelled));
        assert_eq!(
            retried,
            SocketDrainOutcome::JoinedWithFault(SocketCleanupError::TaskCancelled)
        );
        assert_eq!(capacity.usage().metadata_bytes(), 0);
    }
    mod unbounded_join_tests;
}
