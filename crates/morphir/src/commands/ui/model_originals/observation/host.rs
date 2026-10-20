//! One actual native-host source owner. Labels and snapshots issue no grants.
use super::{WorkerObservationLimits, WorkerObservationScope, WorkerSnapshot};
use cap_std::fs::Dir;
use morphir_common::config::observation::{ReadLimits, ReadSnapshot, SourceReadScope};
use std::{
    path::Path,
    sync::{Arc, Mutex, MutexGuard, Weak},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HostCall {
    InitialDiscovery,
    PlaygroundStartup,
    WorkspaceOpen,
    OriginalsResolution,
    FrozenHeaderProbe,
    LegacyModelOpen,
    Compile,
}
impl HostCall {
    const COUNT: usize = 7;
    fn index(self) -> usize {
        match self {
            Self::InitialDiscovery => 0,
            Self::PlaygroundStartup => 1,
            Self::WorkspaceOpen => 2,
            Self::OriginalsResolution => 3,
            Self::FrozenHeaderProbe => 4,
            Self::LegacyModelOpen => 5,
            Self::Compile => 6,
        }
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum HostObservationError {
    #[error("native host source observation is incomplete")]
    Incomplete,
    #[error("native host observation capacity was exceeded")]
    Capacity,
    #[error("native host observation belongs to another source owner")]
    ForeignScope,
    #[error("native host observation root could not be bound")]
    RootIdentity,
}
#[derive(Clone, Copy)]
pub struct HostObservationLimits {
    updates: u64,
}
impl HostObservationLimits {
    pub fn new(updates: u64) -> Result<Self, HostObservationError> {
        Ok(Self { updates })
    }
}
#[derive(Clone, Copy)]
enum HostBinding {
    Unbound,
    Bound,
}
struct HostState {
    calls: [u64; HostCall::COUNT],
    updates: u64,
    active: u64,
    binding: HostBinding,
    fault: Option<HostObservationError>,
}
struct HostShared {
    source: SourceReadScope,
    workers: WorkerObservationScope,
    limits: HostObservationLimits,
    state: Mutex<HostState>,
}
impl HostShared {
    fn state(&self) -> MutexGuard<'_, HostState> {
        self.state.lock().unwrap_or_else(|poison| {
            let mut state = poison.into_inner();
            state.fault.get_or_insert(HostObservationError::Incomplete);
            state
        })
    }
}
/// The single final-seal owner. Writer leases retain the SAME allocation.
pub struct HostSourceObservationScope {
    shared: Arc<HostShared>,
}
/// Opaque identity-only view. A Weak reference never retains the writer owner.
#[derive(Clone)]
pub struct HostSourceIdentity {
    owner: Weak<HostShared>,
}
impl HostSourceIdentity {
    pub(in crate::commands::ui) fn matches(&self, other: &Self) -> bool {
        Weak::ptr_eq(&self.owner, &other.owner)
    }
}
/// Owned only by actual production providers, routes and socket owners.
#[derive(Clone)]
pub struct HostSourceLease {
    shared: Arc<HostShared>,
}
impl HostSourceObservationScope {
    pub fn bind_native_ui(
        held: &Dir,
        root: &Path,
        reads: ReadLimits,
        workers: WorkerObservationLimits,
        host: HostObservationLimits,
    ) -> Result<Self, HostObservationError> {
        let source = SourceReadScope::bind_workspace(held, root, reads)
            .map_err(|_| HostObservationError::RootIdentity)?;
        let workers = WorkerObservationScope::bind_workspace(held, root, workers)
            .map_err(|_| HostObservationError::RootIdentity)?;
        Ok(Self {
            shared: Arc::new(HostShared {
                source,
                workers,
                limits: host,
                state: Mutex::new(HostState {
                    calls: [0; HostCall::COUNT],
                    updates: 0,
                    active: 0,
                    binding: HostBinding::Unbound,
                    fault: None,
                }),
            }),
        })
    }
    pub fn source_scope(&self) -> &SourceReadScope {
        &self.shared.source
    }
    pub fn snapshot(&self) -> HostSourceSnapshot {
        let state = self.shared.state();
        HostSourceSnapshot {
            calls: state.calls,
            reads: self.shared.source.observation().snapshot(),
            workers: self.shared.workers.snapshot(),
            coverage: match state.fault {
                Some(error) => HostCoverage::Partial(error),
                None => HostCoverage::Unsealed,
            },
        }
    }
    pub(in crate::commands::ui) fn lease(&self) -> HostSourceLease {
        HostSourceLease {
            shared: self.shared.clone(),
        }
    }
    pub fn try_seal(self) -> Result<HostSourceSnapshot, PendingHostSourceSeal> {
        let shared = match Arc::try_unwrap(self.shared) {
            Ok(shared) => shared,
            Err(shared) => {
                return Err(PendingHostSourceSeal {
                    scope: Self { shared },
                });
            }
        };
        let state = shared.state();
        let calls = state.calls;
        let covered = state.fault.is_none()
            && state.active == 0
            && matches!(state.binding, HostBinding::Bound)
            && calls[HostCall::InitialDiscovery.index()] != 0
            && calls[HostCall::PlaygroundStartup.index()] != 0;
        let coverage = if covered {
            HostCoverage::Sealed
        } else {
            HostCoverage::Partial(state.fault.unwrap_or(HostObservationError::Incomplete))
        };
        drop(state);
        Ok(HostSourceSnapshot {
            calls,
            reads: shared.source.seal(),
            workers: shared.workers.snapshot(),
            coverage,
        })
    }
}
pub struct PendingHostSourceSeal {
    scope: HostSourceObservationScope,
}
impl PendingHostSourceSeal {
    pub fn into_scope(self) -> HostSourceObservationScope {
        self.scope
    }
}
enum HostCoverage {
    Unsealed,
    Partial(HostObservationError),
    Sealed,
}
pub struct HostSourceSnapshot {
    calls: [u64; HostCall::COUNT],
    reads: ReadSnapshot,
    workers: WorkerSnapshot,
    coverage: HostCoverage,
}
impl HostSourceSnapshot {
    pub fn calls(&self, call: HostCall) -> u64 {
        self.calls[call.index()]
    }
    pub fn reads(&self) -> &ReadSnapshot {
        &self.reads
    }
    pub fn workers(&self) -> WorkerSnapshot {
        self.workers
    }
    pub fn require_source_complete(&self) -> Result<(), HostObservationError> {
        match self.coverage {
            HostCoverage::Unsealed => return Err(HostObservationError::Incomplete),
            HostCoverage::Partial(error) => return Err(error),
            HostCoverage::Sealed => {}
        }
        self.reads
            .require_complete()
            .map_err(|_| HostObservationError::Incomplete)?;
        if self.workers.scheduled() != 0 {
            self.workers
                .require_joined_cleanup()
                .map_err(|_| HostObservationError::Incomplete)?;
        }
        Ok(())
    }
}
impl HostSourceLease {
    pub(in crate::commands::ui) fn identity(&self) -> HostSourceIdentity {
        HostSourceIdentity {
            owner: Arc::downgrade(&self.shared),
        }
    }
    pub(in crate::commands::ui) fn source_scope(&self) -> &SourceReadScope {
        &self.shared.source
    }
    pub(in crate::commands::ui) fn worker_scope(&self) -> &WorkerObservationScope {
        &self.shared.workers
    }
    pub(in crate::commands::ui) fn mark_incomplete(&self) {
        self.shared
            .state()
            .fault
            .get_or_insert(HostObservationError::Incomplete);
    }
    pub(in crate::commands::ui) fn bound(&self) {
        self.shared.state().binding = HostBinding::Bound;
    }
    pub(in crate::commands::ui) fn enter(&self, call: HostCall) -> HostRouteGuard {
        let mut state = self.shared.state();
        let next = state
            .updates
            .checked_add(1)
            .filter(|next| *next <= self.shared.limits.updates);
        let recording = match next {
            Some(next) => {
                let counts = state.calls[call.index()].checked_add(1);
                let active = state.active.checked_add(1);
                match (counts, active) {
                    (Some(counts), Some(active)) => {
                        state.updates = next;
                        state.calls[call.index()] = counts;
                        state.active = active;
                        RouteRecording::Recorded
                    }
                    _ => {
                        state.fault.get_or_insert(HostObservationError::Capacity);
                        RouteRecording::Omitted
                    }
                }
            }
            None => {
                state.fault.get_or_insert(HostObservationError::Capacity);
                RouteRecording::Omitted
            }
        };
        HostRouteGuard {
            lease: self.clone(),
            recording,
        }
    }
}
enum RouteRecording {
    Recorded,
    Omitted,
}
pub(in crate::commands::ui) struct HostRouteGuard {
    lease: HostSourceLease,
    recording: RouteRecording,
}
impl Drop for HostRouteGuard {
    fn drop(&mut self) {
        if matches!(self.recording, RouteRecording::Recorded) {
            let mut state = self.lease.shared.state();
            match state.active.checked_sub(1) {
                Some(next) => state.active = next,
                None => {
                    state.fault.get_or_insert(HostObservationError::Incomplete);
                }
            }
        }
    }
}
