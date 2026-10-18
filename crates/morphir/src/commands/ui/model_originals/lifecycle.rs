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
            WorkPermit(self.clone()),
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
struct WorkPermit(HostModelCaptureCapacity);
impl Drop for WorkPermit {
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
enum ConnectionState {
    Empty,
    Capturing {
        attempt: AttemptKey,
        control: CaptureControl,
    },
    Ready(Box<OwnedCapture>),
    Released(CaptureId),
    Closed,
}
impl ConnectionState {
    fn matches(&self, key: AttemptKey) -> bool {
        match self {
            Self::Capturing { attempt, .. } => *attempt == key,
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
            ConnectionState::Capturing { .. } | ConnectionState::Ready(_) => {
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
            let _permit = permit;
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
            finish(&worker_owner, attempt, &worker_control, result, reservation)
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
        if let ConnectionState::Capturing { control, .. } = &prior {
            control.cancel();
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
    result: JoinHandle<Result<ModelCaptureCompletion, CaptureError>>,
    armed: bool,
}
impl PendingModelCapture {
    pub fn cancel(&self) {
        abandon(&self.owner, self.attempt, &self.control);
    }
    pub async fn wait(mut self) -> Result<ModelCaptureCompletion, CaptureError> {
        let deadline = tokio::time::Instant::from_std(self.control.deadline());
        let result = tokio::select! {
            result = &mut self.result => result.map_err(|_| CaptureError::CaptureFailed)?,
            () = self.control.cancelled() => return Err(CaptureError::Timeout),
            () = tokio::time::sleep_until(deadline) => return Err(CaptureError::Timeout),
        };
        self.control.check()?;
        if let Ok(ModelCaptureCompletion::Ready(_)) = &result {
            let owner = self.owner.upgrade().ok_or(CaptureError::Timeout)?;
            if !owner
                .lock()
                .expect("model capture connection")
                .matches(self.attempt)
            {
                return Err(CaptureError::Timeout);
            }
        }
        self.armed = false;
        result
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
fn finish(
    owner: &Weak<Mutex<ConnectionState>>,
    attempt: AttemptKey,
    control: &CaptureControl,
    result: Result<CaptureResult, CaptureError>,
    reservation: Reservation,
) -> Result<ModelCaptureCompletion, CaptureError> {
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
            let id = capture.id.clone();
            *state = ConnectionState::Ready(capture);
            Ok(ModelCaptureCompletion::Ready(id))
        }
        Prepared::Unavailable(reason) => {
            *state = ConnectionState::Empty;
            Ok(ModelCaptureCompletion::Unavailable(reason))
        }
        Prepared::Failed(error) => {
            *state = ConnectionState::Empty;
            Err(error)
        }
    }
}
