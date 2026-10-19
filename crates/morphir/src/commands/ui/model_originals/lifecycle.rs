//! Host resource ownership around the confined storage core. These handles are
//! connection-scoped storage leases, not authenticated provider authority.
use cap_std::fs::Dir;
use morphir_distribution::Sha256Digest;
use serde::Serialize;
use std::sync::{Arc, Mutex, Weak};
use tokio::task::JoinHandle;

use super::{
    capture::{CaptureAccounting, Limits, capture_accounted},
    *,
};

pub const MAX_HOST_CAPTURES: usize = 64;
pub const MAX_HOST_CAPTURE_BYTES: usize = 128 * 1024 * 1024;
pub const MAX_HOST_CAPTURE_METADATA_BYTES: usize = 64 * 1024 * 1024;

#[derive(Debug, Clone, Eq, PartialEq, Serialize)]
#[serde(transparent)]
pub struct CaptureId(String);
impl CaptureId {
    pub fn parse(text: &str) -> Result<Self, CaptureError> {
        if text.is_empty() || text.len() > 128 || text.chars().any(char::is_control) {
            return Err(CaptureError::InvalidIdentity);
        }
        Ok(Self(text.to_owned()))
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
    fn fresh() -> Self {
        Self(uuid::Uuid::new_v4().to_string())
    }
}
#[derive(Debug, Clone, Copy, Eq, PartialEq)]
struct AttemptKey(uuid::Uuid);

#[derive(Debug, Clone, Copy, Default, Eq, PartialEq)]
pub struct ModelCaptureUsage {
    source_bytes: usize,
    metadata_bytes: usize,
    captures: usize,
    active_workers: usize,
}
impl ModelCaptureUsage {
    pub fn source_bytes(self) -> usize {
        self.source_bytes
    }
    pub fn metadata_bytes(self) -> usize {
        self.metadata_bytes
    }
    pub fn captures(self) -> usize {
        self.captures
    }
    /// Reserved active-work credits, including private preparation awaiting
    /// publication. This is not a count of currently running OS threads.
    pub fn active_workers(self) -> usize {
        self.active_workers
    }
}
#[derive(Debug, Clone, Copy)]
pub(super) struct HostLimits {
    pub bytes: usize,
    pub metadata: usize,
    pub captures: usize,
}
impl Default for HostLimits {
    fn default() -> Self {
        Self {
            bytes: MAX_HOST_CAPTURE_BYTES,
            metadata: MAX_HOST_CAPTURE_METADATA_BYTES,
            captures: MAX_HOST_CAPTURES,
        }
    }
}
#[derive(Debug)]
struct Capacity {
    limits: HostLimits,
    usage: ModelCaptureUsage,
}
#[derive(Debug, Clone)]
pub struct HostModelCaptureCapacity(Arc<Mutex<Capacity>>);
impl Default for HostModelCaptureCapacity {
    fn default() -> Self {
        Self::with_limits(HostLimits::default())
    }
}
impl HostModelCaptureCapacity {
    pub(super) fn with_limits(limits: HostLimits) -> Self {
        Self(Arc::new(Mutex::new(Capacity {
            limits,
            usage: ModelCaptureUsage::default(),
        })))
    }
    pub fn usage(&self) -> ModelCaptureUsage {
        self.0.lock().expect("model capture capacity").usage
    }
    fn reserve(&self) -> Result<(Reservation, WorkPermit), CaptureError> {
        let mut state = self.0.lock().expect("model capture capacity");
        if state.usage.captures == state.limits.captures || state.usage.active_workers != 0 {
            return Err(CaptureError::Capacity);
        }
        state.usage.captures += 1;
        state.usage.active_workers = 1;
        Ok((
            Reservation {
                host: self.clone(),
                source_bytes: 0,
                metadata_bytes: 0,
            },
            WorkPermit {
                _reservation: Arc::new(WorkReservation(self.clone())),
            },
        ))
    }
}
#[derive(Debug)]
struct Reservation {
    host: HostModelCaptureCapacity,
    source_bytes: usize,
    metadata_bytes: usize,
}
impl CaptureAccounting for Reservation {
    fn source(&mut self, bytes: usize) -> Result<(), CaptureError> {
        let mut state = self.host.0.lock().expect("model capture capacity");
        let total = state
            .usage
            .source_bytes
            .checked_add(bytes)
            .filter(|total| *total <= state.limits.bytes)
            .ok_or(CaptureError::Capacity)?;
        state.usage.source_bytes = total;
        self.source_bytes += bytes;
        Ok(())
    }
    fn metadata(&mut self, bytes: usize) -> Result<(), CaptureError> {
        let mut state = self.host.0.lock().expect("model capture capacity");
        let total = state
            .usage
            .metadata_bytes
            .checked_add(bytes)
            .filter(|total| *total <= state.limits.metadata)
            .ok_or(CaptureError::Capacity)?;
        state.usage.metadata_bytes = total;
        self.metadata_bytes += bytes;
        Ok(())
    }
}
impl Drop for Reservation {
    fn drop(&mut self) {
        let mut state = self.host.0.lock().expect("model capture capacity");
        state.usage.source_bytes -= self.source_bytes;
        state.usage.metadata_bytes -= self.metadata_bytes;
        state.usage.captures -= 1;
    }
}
// Clones retain the same single credit, never reserve another. Both the actual
// worker and the private preparation own this guard until their work ends.
#[derive(Clone)]
struct WorkPermit {
    _reservation: Arc<WorkReservation>,
}
struct WorkReservation(HostModelCaptureCapacity);
impl Drop for WorkReservation {
    fn drop(&mut self) {
        self.0
            .0
            .lock()
            .expect("model capture capacity")
            .usage
            .active_workers -= 1;
    }
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct CaptureInfo {
    id: CaptureId,
    source_bytes: usize,
    metadata_bytes: usize,
    entries: usize,
    digest: Sha256Digest,
}
impl CaptureInfo {
    pub fn id(&self) -> &CaptureId {
        &self.id
    }
    pub fn source_byte_length(&self) -> usize {
        self.source_bytes
    }
    pub fn metadata_byte_length(&self) -> usize {
        self.metadata_bytes
    }
    pub fn entry_count(&self) -> usize {
        self.entries
    }
    pub fn inventory_sha256(&self) -> &Sha256Digest {
        &self.digest
    }
}
// Field order is intentional: release drops owned buffers before returning their
// credits. No Arc<CapturedSources> can escape the retaining connection.
struct OwnedCapture {
    sources: Box<CapturedSources>,
    reservation: Reservation,
    attempt: AttemptKey,
    id: CaptureId,
}
impl OwnedCapture {
    fn info(&self) -> CaptureInfo {
        debug_assert_eq!(
            self.reservation.source_bytes,
            self.sources.source_byte_length()
        );
        debug_assert_eq!(
            self.reservation.metadata_bytes,
            self.sources.metadata_byte_length()
        );
        CaptureInfo {
            id: self.id.clone(),
            source_bytes: self.sources.source_byte_length(),
            metadata_bytes: self.sources.metadata_byte_length(),
            entries: self.sources.entries().len(),
            digest: self.sources.inventory_sha256().clone(),
        }
    }
}
// Drop owned buffers and their byte/slot reservation before the work credit.
struct PreparedOwner {
    capture: Box<OwnedCapture>,
    _work: WorkPermit,
    control: CaptureControl,
}
enum ConnectionState {
    Empty,
    Capturing {
        attempt: AttemptKey,
        control: CaptureControl,
    },
    Prepared(Box<PreparedOwner>),
    Ready(Box<OwnedCapture>),
    Released(CaptureId),
    Closed,
}
impl ConnectionState {
    fn matches(&self, key: AttemptKey) -> bool {
        match self {
            Self::Capturing { attempt, .. } => *attempt == key,
            Self::Prepared(prepared) => prepared.capture.attempt == key,
            Self::Ready(capture) => capture.attempt == key,
            _ => false,
        }
    }
}

/// The initial lifecycle boundary accepts an existing confined directory and
/// selected module. Provider/source/project authorization must be resolved by
/// the eventual real provider caller; public labels cannot construct authority.
pub struct ModelCaptureConnection {
    capacity: HostModelCaptureCapacity,
    state: Arc<Mutex<ConnectionState>>,
}
impl ModelCaptureConnection {
    pub fn new(capacity: HostModelCaptureCapacity) -> Self {
        Self {
            capacity,
            state: Arc::new(Mutex::new(ConnectionState::Empty)),
        }
    }
    /// Must be called inside a Tokio runtime. All owned work is moved into the
    /// blocking worker; dropping the waiter never drops that worker's permit.
    pub fn start(
        &self,
        output: Dir,
        module: SelectedModule,
        scope: CaptureScope,
    ) -> Result<PendingModelCapture, CaptureError> {
        self.start_with(
            output,
            module,
            scope,
            CaptureControl::new(),
            Arc::new(NoopHooks),
        )
    }
    pub(super) fn start_with(
        &self,
        output: Dir,
        module: SelectedModule,
        scope: CaptureScope,
        control: CaptureControl,
        hooks: Arc<dyn WorkerHooks>,
    ) -> Result<PendingModelCapture, CaptureError> {
        let runtime =
            tokio::runtime::Handle::try_current().map_err(|_| CaptureError::CaptureFailed)?;
        control.check()?;
        let mut state = self.state.lock().expect("model capture connection");
        match &*state {
            ConnectionState::Capturing { .. }
            | ConnectionState::Prepared(_)
            | ConnectionState::Ready(_) => {
                return Err(CaptureError::ActiveCapture);
            }
            ConnectionState::Closed => return Err(CaptureError::UnknownHandle),
            _ => {}
        }
        // Slot and active work are reserved atomically, before opening compile
        // storage or publishing Capturing. A refusal preserves the old tombstone.
        let (mut reservation, permit) = self.capacity.reserve()?;
        let attempt = AttemptKey(uuid::Uuid::new_v4());
        *state = ConnectionState::Capturing {
            attempt,
            control: control.clone(),
        };
        drop(state);
        let worker_control = control.clone();
        let owner = Arc::downgrade(&self.state);
        let worker_owner = owner.clone();
        let result = runtime.spawn_blocking(move || {
            // The guard lives until this blocking task exits, even when its
            // JoinHandle/waiter is dropped or the connection is closed.
            let _worker_permit = permit.clone();
            hooks.before_capture();
            let result = capture_accounted(
                &output,
                &module,
                scope,
                &worker_control,
                Limits::default(),
                &mut reservation,
            );
            hooks.after_capture();
            let completion = finish(
                &worker_owner,
                attempt,
                &worker_control,
                result,
                reservation,
                permit,
            );
            hooks.before_worker_exit();
            completion
        });
        Ok(PendingModelCapture {
            owner,
            attempt,
            control,
            result,
            armed: true,
        })
    }
    pub fn inspect(&self, id: &CaptureId) -> Result<CaptureInfo, CaptureError> {
        let state = self.state.lock().expect("model capture connection");
        match &*state {
            ConnectionState::Ready(capture) if &capture.id == id => Ok(capture.info()),
            _ => Err(CaptureError::UnknownHandle),
        }
    }
    pub fn release(&self, id: &CaptureId) -> Result<(), CaptureError> {
        let prior = {
            let mut state = self.state.lock().expect("model capture connection");
            match &*state {
                ConnectionState::Ready(capture) if &capture.id == id => {
                    std::mem::replace(&mut *state, ConnectionState::Released(id.clone()))
                }
                ConnectionState::Released(prior) if prior == id => return Ok(()),
                _ => return Err(CaptureError::UnknownHandle),
            }
        };
        drop(prior);
        Ok(())
    }
    pub fn close(&self) {
        let prior = std::mem::replace(
            &mut *self.state.lock().expect("model capture connection"),
            ConnectionState::Closed,
        );
        match &prior {
            ConnectionState::Capturing { control, .. } => control.cancel(),
            ConnectionState::Prepared(prepared) => prepared.control.cancel(),
            _ => {}
        }
        drop(prior);
    }
}
impl Drop for ModelCaptureConnection {
    fn drop(&mut self) {
        self.close();
    }
}

pub(super) trait WorkerHooks: Send + Sync {
    fn before_capture(&self) {}
    fn after_capture(&self) {}
    fn before_worker_exit(&self) {}
}
struct NoopHooks;
impl WorkerHooks for NoopHooks {}

#[derive(Debug, Eq, PartialEq)]
pub enum ModelCaptureCompletion {
    Ready(CaptureId),
    Unavailable(CaptureUnavailable),
}
impl ModelCaptureCompletion {
    pub fn ready(self) -> Option<CaptureId> {
        match self {
            Self::Ready(id) => Some(id),
            _ => None,
        }
    }
}

pub struct PendingModelCapture {
    owner: Weak<Mutex<ConnectionState>>,
    attempt: AttemptKey,
    control: CaptureControl,
    result: JoinHandle<Result<WorkerCompletion, CaptureError>>,
    armed: bool,
}
impl PendingModelCapture {
    pub fn cancel(&self) {
        abandon(&self.owner, self.attempt, &self.control);
    }
    /// Storage-only convenience for existing callers. This does not establish
    /// provider authorization. The eventual provider path must revalidate its
    /// actual authority between private preparation and publication.
    pub async fn wait(self) -> Result<ModelCaptureCompletion, CaptureError> {
        match self.wait_prepared().await? {
            PreparedCaptureCompletion::Prepared(prepared) => prepared.publish(),
            PreparedCaptureCompletion::Unavailable(reason) => {
                Ok(ModelCaptureCompletion::Unavailable(reason))
            }
        }
    }
    pub(super) async fn wait_prepared(mut self) -> Result<PreparedCaptureCompletion, CaptureError> {
        let deadline = tokio::time::Instant::from_std(self.control.deadline());
        let result = tokio::select! {
            result = &mut self.result => result.map_err(|_| CaptureError::CaptureFailed)?,
            () = self.control.cancelled() => return Err(CaptureError::Timeout),
            () = tokio::time::sleep_until(deadline) => return Err(CaptureError::Timeout),
        }?;
        self.control.check()?;
        let completion = match result {
            WorkerCompletion::Prepared => {
                let owner = self.owner.upgrade().ok_or(CaptureError::Timeout)?;
                let state = owner.lock().expect("model capture connection");
                if !matches!(&*state, ConnectionState::Prepared(prepared)
                    if prepared.capture.attempt == self.attempt)
                {
                    return Err(CaptureError::Timeout);
                }
                PreparedCaptureCompletion::Prepared(PreparedModelCapture {
                    owner: self.owner.clone(),
                    attempt: self.attempt,
                    control: self.control.clone(),
                    armed: true,
                })
            }
            WorkerCompletion::Unavailable(reason) => PreparedCaptureCompletion::Unavailable(reason),
        };
        self.armed = false;
        Ok(completion)
    }
}
// No sources, capture ID, or retaining Arc escape through this sealed token.
// Possession alone is not authority: a real provider caller must perform its
// current-source/project revalidation before calling publish.
pub(super) struct PreparedModelCapture {
    owner: Weak<Mutex<ConnectionState>>,
    attempt: AttemptKey,
    control: CaptureControl,
    armed: bool,
}
pub(super) enum PreparedCaptureCompletion {
    Prepared(PreparedModelCapture),
    Unavailable(CaptureUnavailable),
}
impl PreparedCaptureCompletion {
    #[cfg(test)]
    pub(super) fn prepared(self) -> Option<PreparedModelCapture> {
        match self {
            Self::Prepared(prepared) => Some(prepared),
            _ => None,
        }
    }
}
impl PreparedModelCapture {
    pub(super) fn publish(mut self) -> Result<ModelCaptureCompletion, CaptureError> {
        self.control.check()?;
        let owner = self.owner.upgrade().ok_or(CaptureError::Timeout)?;
        let mut state = owner.lock().expect("model capture connection");
        self.control.check()?;
        if !matches!(&*state, ConnectionState::Prepared(prepared)
            if prepared.capture.attempt == self.attempt)
        {
            return Err(CaptureError::Timeout);
        }
        let ConnectionState::Prepared(prepared) =
            std::mem::replace(&mut *state, ConnectionState::Empty)
        else {
            unreachable!()
        };
        let PreparedOwner {
            capture,
            _work: work,
            control: _,
        } = *prepared;
        let id = capture.id.clone();
        *state = ConnectionState::Ready(capture);
        self.armed = false;
        drop(state);
        drop(work);
        Ok(ModelCaptureCompletion::Ready(id))
    }
    #[cfg(test)]
    pub(super) fn id_for_test(&self) -> CaptureId {
        let owner = self.owner.upgrade().unwrap();
        let state = owner.lock().unwrap();
        match &*state {
            ConnectionState::Prepared(prepared) if prepared.capture.attempt == self.attempt => {
                prepared.capture.id.clone()
            }
            _ => panic!("not current private preparation"),
        }
    }
}
impl Drop for PreparedModelCapture {
    fn drop(&mut self) {
        if self.armed {
            abandon(&self.owner, self.attempt, &self.control);
        }
    }
}

impl Drop for PendingModelCapture {
    fn drop(&mut self) {
        if self.armed {
            self.cancel();
        }
    }
}
fn abandon(owner: &Weak<Mutex<ConnectionState>>, attempt: AttemptKey, control: &CaptureControl) {
    control.cancel();
    if let Some(owner) = owner.upgrade() {
        let prior = {
            let mut state = owner.lock().expect("model capture connection");
            state
                .matches(attempt)
                .then(|| std::mem::replace(&mut *state, ConnectionState::Empty))
        };
        drop(prior);
    }
}
enum WorkerCompletion {
    Prepared,
    Unavailable(CaptureUnavailable),
}
fn finish(
    owner: &Weak<Mutex<ConnectionState>>,
    attempt: AttemptKey,
    control: &CaptureControl,
    result: Result<CaptureResult, CaptureError>,
    reservation: Reservation,
    work: WorkPermit,
) -> Result<WorkerCompletion, CaptureError> {
    enum Prepared {
        Ready(Box<OwnedCapture>),
        Unavailable(CaptureUnavailable),
        Failed(CaptureError),
    }
    let prepared = match result {
        Ok(CaptureResult::Ready(sources)) => Prepared::Ready(Box::new(OwnedCapture {
            sources,
            reservation,
            attempt,
            id: CaptureId::fresh(),
        })),
        Ok(CaptureResult::Unavailable(reason)) => {
            drop(reservation);
            Prepared::Unavailable(reason)
        }
        Err(error) => {
            drop(reservation);
            Prepared::Failed(error)
        }
    };
    let owner = owner.upgrade().ok_or(CaptureError::Timeout)?;
    let mut state = owner.lock().expect("model capture connection");
    if !state.matches(attempt) {
        return Err(CaptureError::Timeout);
    }
    if control.check().is_err() {
        *state = ConnectionState::Empty;
        return Err(CaptureError::Timeout);
    }
    match prepared {
        Prepared::Ready(capture) => {
            *state = ConnectionState::Prepared(Box::new(PreparedOwner {
                capture,
                _work: work,
                control: control.clone(),
            }));
            Ok(WorkerCompletion::Prepared)
        }
        Prepared::Unavailable(reason) => {
            *state = ConnectionState::Empty;
            Ok(WorkerCompletion::Unavailable(reason))
        }
        Prepared::Failed(error) => {
            *state = ConnectionState::Empty;
            Err(error)
        }
    }
}
