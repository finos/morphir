//! Private bounded evidence about actual blocking workers and their join handles.
//! This is a worker prefix, never a source-read or whole-host coverage claim.
mod host;
use cap_std::fs::Dir;
pub use host::{
    HostCall, HostObservationError, HostObservationLimits, HostSourceIdentity, HostSourceLease,
    HostSourceObservationScope, HostSourceSnapshot,
};
use morphir_common::file_identity::FileIdentity;
use std::{
    future::Future,
    path::Path,
    pin::Pin,
    sync::{Arc, Mutex, MutexGuard},
    task::{Context, Poll},
};
use tokio::task::{JoinError, JoinHandle};

use super::lifecycle::AttemptKey;

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum WorkerObservationError {
    #[error("worker observation root identity does not match")]
    RootIdentity,
    #[error("worker observation capacity exceeded")]
    Capacity,
    #[error("worker observation belongs to another scope or connection")]
    ForeignWitness,
    #[error("worker prefix does not establish joined cleanup")]
    Incomplete,
}

/// Explicit evidence bounds. These do not limit or reject business work.
#[derive(Clone, Copy)]
pub struct WorkerObservationLimits {
    attempts: u64,
    updates: u64,
}
impl WorkerObservationLimits {
    pub fn new(attempts: u64, updates: u64) -> Result<Self, WorkerObservationError> {
        Ok(Self { attempts, updates })
    }
}

#[derive(Clone, Copy, Default)]
struct Counts {
    issuing: u64,
    scheduled: u64,
    started: u64,
    returned_ok: u64,
    returned_error: u64,
    panicked: u64,
    joined_ok: u64,
    joined_panicked: u64,
    joined_cancelled: u64,
    owned_handles: u64,
    dropped_unjoined: u64,
}
impl Counts {
    fn apply(&mut self, event: Event) -> Option<()> {
        let increment = |counter: &mut u64| -> Option<()> {
            *counter = counter.checked_add(1)?;
            Some(())
        };
        match event {
            Event::Scheduled => {
                self.issuing = self.issuing.checked_sub(1)?;
                increment(&mut self.scheduled)?;
                increment(&mut self.owned_handles)?;
            }
            Event::Started => increment(&mut self.started)?,
            Event::Returned(BodyOutcome::Ok) => increment(&mut self.returned_ok)?,
            Event::Returned(BodyOutcome::Error) => increment(&mut self.returned_error)?,
            Event::Returned(BodyOutcome::Panicked) => increment(&mut self.panicked)?,
            Event::Joined(outcome) => {
                self.owned_handles = self.owned_handles.checked_sub(1)?;
                match outcome {
                    JoinOutcome::Ok => increment(&mut self.joined_ok)?,
                    JoinOutcome::Panicked => increment(&mut self.joined_panicked)?,
                    JoinOutcome::Cancelled => increment(&mut self.joined_cancelled)?,
                    JoinOutcome::Unclassified => return None,
                }
            }
            Event::DroppedUnjoined => {
                self.owned_handles = self.owned_handles.checked_sub(1)?;
                increment(&mut self.dropped_unjoined)?;
            }
        }
        Some(())
    }
}
#[derive(Clone, Copy)]
enum BodyOutcome {
    Ok,
    Error,
    Panicked,
}
#[derive(Clone, Copy)]
enum JoinOutcome {
    Ok,
    Panicked,
    Cancelled,
    Unclassified,
}
#[derive(Clone, Copy)]
enum Event {
    Scheduled,
    Started,
    Returned(BodyOutcome),
    Joined(JoinOutcome),
    DroppedUnjoined,
}

#[derive(Default)]
struct Evidence {
    counts: Counts,
    fault: Option<WorkerObservationError>,
}
fn evidence(mutex: &Mutex<Evidence>) -> MutexGuard<'_, Evidence> {
    mutex.lock().unwrap_or_else(|poison| {
        let mut evidence = poison.into_inner();
        evidence
            .fault
            .get_or_insert(WorkerObservationError::Incomplete);
        evidence
    })
}
struct ScopeState {
    evidence: Evidence,
    reserved: u64,
    connections: u64,
    updates: u64,
}
struct Scope {
    // Metadata identity is retained, but no directory/read grant is exposed.
    _identity: FileIdentity,
    limits: WorkerObservationLimits,
    state: Mutex<ScopeState>,
}
impl Scope {
    fn state(&self) -> MutexGuard<'_, ScopeState> {
        self.state.lock().unwrap_or_else(|poison| {
            let mut state = poison.into_inner();
            state
                .evidence
                .fault
                .get_or_insert(WorkerObservationError::Incomplete);
            state
        })
    }
}
/// Non-Clone owner. Held capability identity binds scope issuance, not authority.
pub struct WorkerObservationScope {
    shared: Arc<Scope>,
}
impl WorkerObservationScope {
    pub fn bind_workspace(
        held: &Dir,
        label: &Path,
        limits: WorkerObservationLimits,
    ) -> Result<Self, WorkerObservationError> {
        let identity = held
            .try_clone()
            .ok()
            .and_then(|dir| FileIdentity::from_file(dir.into_std_file()).ok())
            .ok_or(WorkerObservationError::RootIdentity)?;
        if identity
            != FileIdentity::from_path(label).map_err(|_| WorkerObservationError::RootIdentity)?
        {
            return Err(WorkerObservationError::RootIdentity);
        }
        Ok(Self {
            shared: Arc::new(Scope {
                _identity: identity,
                limits,
                state: Mutex::new(ScopeState {
                    evidence: Evidence::default(),
                    reserved: 0,
                    connections: 0,
                    updates: 0,
                }),
            }),
        })
    }
    pub fn snapshot(&self) -> WorkerSnapshot {
        let state = self.shared.state();
        WorkerSnapshot::from_evidence(&state.evidence)
    }
    pub fn snapshot_for(
        &self,
        attempt: &WorkerAttemptObservation,
    ) -> Result<WorkerSnapshot, WorkerObservationError> {
        let record = attempt
            .record
            .as_ref()
            .ok_or(WorkerObservationError::Incomplete)?;
        if !Arc::ptr_eq(&self.shared, &record.connection.scope) {
            return Err(WorkerObservationError::ForeignWitness);
        }
        Ok(attempt.snapshot())
    }
}
struct Connection {
    scope: Arc<Scope>,
    evidence: Mutex<Evidence>,
}
/// Read-only connection identity, issued only by the actual owner constructor.
#[derive(Clone)]
pub struct WorkerConnectionObservation {
    connection: Option<Arc<Connection>>,
}
impl WorkerConnectionObservation {
    pub(super) fn unobserved() -> Self {
        Self { connection: None }
    }
    pub(super) fn bind(scope: &WorkerObservationScope) -> Self {
        // Connection views can outlive their business owners without ever
        // starting a worker. Reserve their own cumulative record allowance
        // before allocating, separately from the attempt allowance.
        let mut state = scope.shared.state();
        let Some(next) = state
            .connections
            .checked_add(1)
            .filter(|next| *next <= scope.shared.limits.attempts)
        else {
            state
                .evidence
                .fault
                .get_or_insert(WorkerObservationError::Capacity);
            return Self::unobserved();
        };
        state.connections = next;
        Self {
            connection: Some(Arc::new(Connection {
                scope: scope.shared.clone(),
                evidence: Mutex::new(Evidence::default()),
            })),
        }
    }
    pub fn snapshot(&self) -> WorkerSnapshot {
        let Some(connection) = &self.connection else {
            return WorkerSnapshot::unobserved();
        };
        let scope = connection.scope.state();
        let mut snapshot = WorkerSnapshot::from_evidence(&evidence(&connection.evidence));
        snapshot.include_fault(scope.evidence.fault);
        snapshot
    }
    pub fn snapshot_for(
        &self,
        attempt: &WorkerAttemptObservation,
    ) -> Result<WorkerSnapshot, WorkerObservationError> {
        let (Some(connection), Some(record)) = (&self.connection, &attempt.record) else {
            return Err(WorkerObservationError::Incomplete);
        };
        if !Arc::ptr_eq(connection, &record.connection) {
            return Err(WorkerObservationError::ForeignWitness);
        }
        Ok(attempt.snapshot())
    }
    pub(super) fn prepare(&self, attempt: AttemptKey) -> WorkerIssuance {
        let Some(connection) = &self.connection else {
            return WorkerIssuance::unobserved();
        };
        // Reserve the fixed per-attempt state before allocating it. No journal
        // or scope-owned table retains completed attempt records.
        let mut scope = connection.scope.state();
        let Some(next) = scope
            .reserved
            .checked_add(1)
            .filter(|next| *next <= connection.scope.limits.attempts)
        else {
            scope
                .evidence
                .fault
                .get_or_insert(WorkerObservationError::Capacity);
            evidence(&connection.evidence)
                .fault
                .get_or_insert(WorkerObservationError::Capacity);
            return WorkerIssuance::unobserved();
        };
        scope.reserved = next;
        // At most one issuance per reserved attempt. It remains visible from
        // before spawn until the genuine returned handle is installed.
        scope.evidence.counts.issuing += 1;
        evidence(&connection.evidence).counts.issuing += 1;
        let observation = WorkerAttemptObservation {
            record: Some(Arc::new(Attempt {
                connection: connection.clone(),
                _attempt: attempt,
                evidence: Mutex::new(Evidence {
                    counts: Counts {
                        issuing: 1,
                        ..Counts::default()
                    },
                    fault: None,
                }),
            })),
        };
        WorkerIssuance {
            observation: Some(observation),
        }
    }
}

/// Owns the pre-spawn issuance interval. An unwind before handle installation
/// cannot turn an older joined prefix into proof of cleanup.
pub(super) struct WorkerIssuance {
    observation: Option<WorkerAttemptObservation>,
}
impl WorkerIssuance {
    fn unobserved() -> Self {
        Self { observation: None }
    }
    pub(super) fn observation(&self) -> WorkerAttemptObservation {
        self.observation
            .clone()
            .unwrap_or_else(WorkerAttemptObservation::unobserved)
    }
    fn install(mut self) -> WorkerAttemptObservation {
        let observation = self
            .observation
            .take()
            .unwrap_or_else(WorkerAttemptObservation::unobserved);
        // Scheduled and the end of issuance commit under the same locks.
        observation.event(Event::Scheduled);
        observation
    }
}
impl Drop for WorkerIssuance {
    fn drop(&mut self) {
        let Some(record) = self
            .observation
            .as_ref()
            .and_then(|view| view.record.as_ref())
        else {
            return;
        };
        let mut scope = record.connection.scope.state();
        let mut connection = evidence(&record.connection.evidence);
        let mut attempt = evidence(&record.evidence);
        for evidence in [&mut scope.evidence, &mut connection, &mut attempt] {
            evidence
                .fault
                .get_or_insert(WorkerObservationError::Incomplete);
        }
    }
}
struct Attempt {
    connection: Arc<Connection>,
    _attempt: AttemptKey,
    evidence: Mutex<Evidence>,
}
/// Same-issued actual attempt provenance; retaining a view retains no task,
/// capture sources, JoinHandle or work permit.
#[derive(Clone)]
pub struct WorkerAttemptObservation {
    record: Option<Arc<Attempt>>,
}
impl WorkerAttemptObservation {
    fn unobserved() -> Self {
        Self { record: None }
    }
    pub fn snapshot(&self) -> WorkerSnapshot {
        let Some(record) = &self.record else {
            return WorkerSnapshot::unobserved();
        };
        // All event/snapshot locks follow scope -> connection -> attempt. No
        // observer operation calls domain code or user callbacks while locked.
        let scope = record.connection.scope.state();
        let connection = evidence(&record.connection.evidence);
        let mut snapshot = WorkerSnapshot::from_evidence(&evidence(&record.evidence));
        snapshot.include_fault(connection.fault.or(scope.evidence.fault));
        snapshot
    }
    fn event(&self, event: Event) {
        let Some(record) = &self.record else {
            return;
        };
        let mut scope = record.connection.scope.state();
        let mut connection = evidence(&record.connection.evidence);
        let mut attempt = evidence(&record.evidence);
        let Some(next) = scope
            .updates
            .checked_add(1)
            .filter(|next| *next <= record.connection.scope.limits.updates)
        else {
            scope
                .evidence
                .fault
                .get_or_insert(WorkerObservationError::Capacity);
            connection
                .fault
                .get_or_insert(WorkerObservationError::Capacity);
            attempt
                .fault
                .get_or_insert(WorkerObservationError::Capacity);
            return;
        };
        scope.updates = next;
        // Compute before committing all three bounded aggregates atomically.
        let mut scope_counts = scope.evidence.counts;
        let mut connection_counts = connection.counts;
        let mut attempt_counts = attempt.counts;
        if scope_counts.apply(event).is_none()
            || connection_counts.apply(event).is_none()
            || attempt_counts.apply(event).is_none()
        {
            scope
                .evidence
                .fault
                .get_or_insert(WorkerObservationError::Incomplete);
            connection
                .fault
                .get_or_insert(WorkerObservationError::Incomplete);
            attempt
                .fault
                .get_or_insert(WorkerObservationError::Incomplete);
            return;
        }
        scope.evidence.counts = scope_counts;
        connection.counts = connection_counts;
        attempt.counts = attempt_counts;
    }
}

/// Fixed immutable counters. Complete observed events and joined cleanup are
/// separate: a completed body can still have a genuinely held unjoined handle.
#[derive(Clone, Copy)]
pub struct WorkerSnapshot {
    counts: Counts,
    coverage: WorkerCoverage,
}
#[derive(Clone, Copy)]
enum WorkerCoverage {
    Unobserved,
    Partial(WorkerObservationError),
    Complete,
}
impl WorkerSnapshot {
    fn unobserved() -> Self {
        Self {
            counts: Counts::default(),
            coverage: WorkerCoverage::Unobserved,
        }
    }
    fn from_evidence(evidence: &Evidence) -> Self {
        let coverage = match evidence.fault {
            Some(error) => WorkerCoverage::Partial(error),
            None if evidence.counts.scheduled == 0 => WorkerCoverage::Unobserved,
            None => WorkerCoverage::Complete,
        };
        Self {
            counts: evidence.counts,
            coverage,
        }
    }
    fn include_fault(&mut self, fault: Option<WorkerObservationError>) {
        if let Some(error) = fault {
            self.coverage = WorkerCoverage::Partial(error);
        }
    }
    pub fn scheduled(&self) -> u64 {
        self.counts.scheduled
    }
    pub fn started(&self) -> u64 {
        self.counts.started
    }
    pub fn returned_ok(&self) -> u64 {
        self.counts.returned_ok
    }
    pub fn returned_error(&self) -> u64 {
        self.counts.returned_error
    }
    pub fn panicked(&self) -> u64 {
        self.counts.panicked
    }
    pub fn joined_ok(&self) -> u64 {
        self.counts.joined_ok
    }
    pub fn joined_panicked(&self) -> u64 {
        self.counts.joined_panicked
    }
    pub fn joined_cancelled(&self) -> u64 {
        self.counts.joined_cancelled
    }
    pub fn owned_handles(&self) -> u64 {
        self.counts.owned_handles
    }
    pub fn dropped_unjoined(&self) -> u64 {
        self.counts.dropped_unjoined
    }
    pub fn require_joined_cleanup(&self) -> Result<(), WorkerObservationError> {
        match self.coverage {
            WorkerCoverage::Unobserved => return Err(WorkerObservationError::Incomplete),
            WorkerCoverage::Partial(error) => return Err(error),
            WorkerCoverage::Complete => {}
        }
        let c = self.counts;
        let normal = c.returned_ok.checked_add(c.returned_error);
        let bodies = normal.and_then(|normal| normal.checked_add(c.panicked));
        if c.scheduled == 0
            || c.issuing != 0
            || c.owned_handles != 0
            || c.dropped_unjoined != 0
            || normal != Some(c.joined_ok)
            || c.panicked != c.joined_panicked
            || bodies != Some(c.started)
            || c.started.checked_add(c.joined_cancelled) != Some(c.scheduled)
        {
            return Err(WorkerObservationError::Incomplete);
        }
        Ok(())
    }
}

/// The only wrapper around the actual Tokio handle, shared by both pending types.
pub(super) struct TrackedJoin<T> {
    handle: Option<JoinHandle<T>>,
    observation: WorkerAttemptObservation,
}
impl<T> TrackedJoin<T> {
    pub(super) fn new(handle: JoinHandle<T>, issuance: WorkerIssuance) -> Self {
        let observation = issuance.install();
        Self {
            handle: Some(handle),
            observation,
        }
    }
    pub(super) fn observation(&self) -> WorkerAttemptObservation {
        self.observation.clone()
    }
    pub(super) fn is_finished(&self) -> bool {
        self.handle
            .as_ref()
            .expect("pending join already resolved")
            .is_finished()
    }
}
impl<T> Future for TrackedJoin<T> {
    type Output = Result<T, JoinError>;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        let this = self.get_mut();
        let Poll::Ready(result) =
            Pin::new(this.handle.as_mut().expect("join already resolved")).poll(cx)
        else {
            return Poll::Pending;
        };
        // Drop the consumed real handle before any caller validation runs.
        drop(this.handle.take());
        let outcome = match &result {
            Ok(_) => JoinOutcome::Ok,
            Err(error) if error.is_panic() => JoinOutcome::Panicked,
            Err(error) if error.is_cancelled() => JoinOutcome::Cancelled,
            Err(_) => JoinOutcome::Unclassified,
        };
        this.observation.event(Event::Joined(outcome));
        Poll::Ready(result)
    }
}
impl<T> Drop for TrackedJoin<T> {
    fn drop(&mut self) {
        if let Some(handle) = self.handle.take() {
            // Tokio detach occurs here. A later body return never becomes join.
            drop(handle);
            self.observation.event(Event::DroppedUnjoined);
        }
    }
}
struct BodyGuard(Option<WorkerAttemptObservation>);
impl Drop for BodyGuard {
    fn drop(&mut self) {
        if let Some(observation) = self.0.take() {
            observation.event(Event::Returned(BodyOutcome::Panicked));
        }
    }
}
pub(super) fn run_body<T, E>(
    observation: WorkerAttemptObservation,
    body: impl FnOnce() -> Result<T, E>,
) -> Result<T, E> {
    observation.event(Event::Started);
    let mut guard = BodyGuard(Some(observation));
    let result = body();
    let observation = guard.0.take().expect("whole body observed once");
    observation.event(Event::Returned(if result.is_ok() {
        BodyOutcome::Ok
    } else {
        BodyOutcome::Error
    }));
    result
}
