//! Private ownership of the actual worker's compile-record allocation.
//! Weak observer/registry views issue no filesystem or provider authority.
use super::*;
use morphir_mck::workbench::model_originals::native::{
    PrivateRecordAdoption, PrivateRecordError, data,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub(in crate::commands::ui) enum PrivateRecordObservationError {
    #[error("The capture does not belong to this actual owner.")]
    NotOwned,
    #[error("The actual private record is not ready.")]
    NotReady,
    #[error("The actual private record was already taken.")]
    AlreadyTaken,
}
#[derive(Default, Clone, Copy)]
pub(in crate::commands::ui) struct PrivateRecordSnapshot {
    bytes: usize,
    capacity: usize,
}
impl PrivateRecordSnapshot {
    pub(in crate::commands::ui) fn retained_bytes(self) -> usize {
        self.bytes
    }
    pub(in crate::commands::ui) fn retained_capacity(self) -> usize {
        self.capacity
    }
}

pub(super) enum RecordConnection {
    Disabled,
    Observed {
        source: observation::HostSourceIdentity,
        registry: Option<PrivateRecordRegistry>,
    },
}
impl RecordConnection {
    pub(super) fn observed(
        source: observation::HostSourceIdentity,
        registry: Option<PrivateRecordRegistry>,
    ) -> Self {
        Self::Observed { source, registry }
    }
    pub(super) fn enabled(&self) -> bool {
        matches!(self, Self::Observed { .. })
    }
    pub(super) fn validate(
        &self,
        offer: &crate::commands::ui::provider::originals::SelectedOriginalsOffer,
    ) -> Result<(), CaptureError> {
        if let Self::Observed { source, .. } = self {
            match offer.provider().workspace().source_observation_identity() {
                Some(actual) if actual.matches(source) => {}
                _ => return Err(CaptureError::CaptureFailed),
            }
        }
        Ok(())
    }
    pub(super) fn prepare(
        &self,
        reservation: &mut Reservation,
        work: &WorkPermit,
        attempt: AttemptKey,
        owner: &mut ConnectionOwner,
    ) -> Result<(), CaptureError> {
        let Self::Observed { registry, .. } = self else {
            return Ok(());
        };
        // The fixed registry is host infrastructure. This dynamic slot and its
        // possible association/string use the SAME capture metadata ledger.
        let credit = reservation.host.reserve_evidence(
            std::mem::size_of::<RecordSlot>()
                .checked_add(std::mem::size_of::<Association>())
                .and_then(|n| n.checked_add(128 + 2 * std::mem::size_of::<usize>()))
                .ok_or(CaptureError::Capacity)?,
        )?;
        let slot = Arc::new(RecordSlot {
            attempt,
            state: Mutex::new(RecordState::Awaiting(work.clone())),
            registry: registry
                .as_ref()
                .map(|registry| Arc::downgrade(&registry.0)),
            _credit: credit,
        });
        owner.record = Arc::downgrade(&slot);
        reservation.record = Some(slot);
        Ok(())
    }
    pub(super) fn remove(&self, id: &CaptureId, owner: &Arc<Mutex<ConnectionOwner>>) {
        if let Self::Observed {
            registry: Some(registry),
            ..
        } = self
        {
            registry.remove(id, owner);
        }
    }
}

struct RetainedRecord {
    // Actual bytes drop before the clone of the same original work permit.
    bytes: Vec<u8>,
    work: WorkPermit,
}
enum RecordState {
    Awaiting(WorkPermit),
    Owned(RetainedRecord),
    CheckedOut(PrivateRecordSnapshot),
    Transferred,
}
pub(super) struct RecordSlot {
    attempt: AttemptKey,
    state: Mutex<RecordState>,
    registry: Option<Weak<Mutex<RegistryState>>>,
    _credit: RetainedEvidenceCredit,
}
impl RecordSlot {
    pub(super) fn store(&self, bytes: Vec<u8>) -> Result<(), CaptureError> {
        let mut state = self.state.lock().expect("private record slot");
        match std::mem::replace(&mut *state, RecordState::Transferred) {
            RecordState::Awaiting(work) => {
                *state = RecordState::Owned(RetainedRecord { bytes, work });
                Ok(())
            }
            prior => {
                *state = prior;
                Err(CaptureError::CaptureFailed)
            }
        }
    }
    fn snapshot(&self) -> PrivateRecordSnapshot {
        match &*self.state.lock().expect("private record slot") {
            RecordState::Owned(raw) => PrivateRecordSnapshot {
                bytes: raw.bytes.len(),
                capacity: raw.bytes.capacity(),
            },
            RecordState::CheckedOut(snapshot) => *snapshot,
            _ => PrivateRecordSnapshot::default(),
        }
    }
    pub(super) fn register(
        self: &Arc<Self>,
        id: &CaptureId,
        owner: &Arc<Mutex<ConnectionOwner>>,
    ) -> Result<(), CaptureError> {
        if let Some(registry) = self.registry.as_ref().and_then(Weak::upgrade) {
            PrivateRecordRegistry(registry).insert(id, owner, self)?;
        }
        Ok(())
    }
    fn transferred(&self) {
        *self.state.lock().expect("private record slot") = RecordState::Transferred;
    }
}
impl Drop for RecordSlot {
    fn drop(&mut self) {
        // A panic/abandoned waiter may retire Ready without going through the
        // explicit release method. Remove its exact weak association before
        // returning the slot's retained metadata credit.
        if let Some(registry) = self.registry.as_ref().and_then(Weak::upgrade) {
            let pointer = self as *const Self;
            for entry in &mut registry.lock().expect("private record registry").entries {
                if entry.as_ref().is_some_and(|entry| {
                    entry.attempt == self.attempt && entry.slot.as_ptr() == pointer
                }) {
                    *entry = None;
                }
            }
        }
    }
}

/// Read-only weak view; it cannot retain a record after the real owners exit.
#[derive(Clone)]
pub(in crate::commands::ui) struct PrivateRecordObserver {
    owner: Weak<Mutex<ConnectionOwner>>,
}
impl PrivateRecordObserver {
    pub(super) fn issued(owner: &Arc<Mutex<ConnectionOwner>>) -> Self {
        Self {
            owner: Arc::downgrade(owner),
        }
    }
    pub(in crate::commands::ui) fn snapshot(&self) -> PrivateRecordSnapshot {
        self.owner
            .upgrade()
            .and_then(|owner| {
                owner
                    .lock()
                    .expect("model capture connection")
                    .record
                    .upgrade()
            })
            .map_or_else(PrivateRecordSnapshot::default, |slot| slot.snapshot())
    }
    pub(in crate::commands::ui) fn with_ready_record<T>(
        &self,
        id: &CaptureId,
        inspect: impl FnOnce(&Vec<u8>) -> T,
    ) -> Result<T, PrivateRecordObservationError> {
        let owner = self
            .owner
            .upgrade()
            .ok_or(PrivateRecordObservationError::NotOwned)?;
        let state = owner.lock().expect("model capture connection");
        let ConnectionState::Ready(capture) = &state.state else {
            return Err(PrivateRecordObservationError::NotReady);
        };
        if &capture.id != id {
            return Err(PrivateRecordObservationError::NotOwned);
        }
        let slot = capture
            .reservation
            .record
            .as_ref()
            .ok_or(PrivateRecordObservationError::NotReady)?;
        let raw = slot.state.lock().expect("private record slot");
        match &*raw {
            RecordState::Owned(raw) => Ok(inspect(&raw.bytes)),
            RecordState::CheckedOut(_) | RecordState::Transferred => {
                Err(PrivateRecordObservationError::AlreadyTaken)
            }
            RecordState::Awaiting(_) => Err(PrivateRecordObservationError::NotReady),
        }
    }
    pub(in crate::commands::ui) fn take(
        &self,
        id: &CaptureId,
    ) -> Result<PrivateRecordLease, PrivateRecordObservationError> {
        let owner = self
            .owner
            .upgrade()
            .ok_or(PrivateRecordObservationError::NotOwned)?;
        let state = owner.lock().expect("model capture connection");
        let ConnectionState::Ready(capture) = &state.state else {
            return Err(PrivateRecordObservationError::NotReady);
        };
        if &capture.id != id {
            return Err(PrivateRecordObservationError::NotOwned);
        }
        let slot = capture
            .reservation
            .record
            .as_ref()
            .ok_or(PrivateRecordObservationError::NotReady)?
            .clone();
        let mut raw = slot.state.lock().expect("private record slot");
        let retained = match std::mem::replace(&mut *raw, RecordState::Transferred) {
            RecordState::Owned(retained) => retained,
            prior => {
                *raw = prior;
                return Err(PrivateRecordObservationError::AlreadyTaken);
            }
        };
        *raw = RecordState::CheckedOut(PrivateRecordSnapshot {
            bytes: retained.bytes.len(),
            capacity: retained.bytes.capacity(),
        });
        drop(raw);
        drop(state);
        Ok(PrivateRecordLease {
            retained: Some(retained),
            slot,
            _connection: owner,
        })
    }
}
pub(in crate::commands::ui) struct PrivateRecordLease {
    retained: Option<RetainedRecord>,
    slot: Arc<RecordSlot>,
    // Keep the actual connection identity alive so weak snapshots cannot claim
    // zero after socket/connection drop while this real lease still owns bytes.
    _connection: Arc<Mutex<ConnectionOwner>>,
}
impl PrivateRecordLease {
    #[cfg(test)]
    pub(in crate::commands::ui) fn buffer(&self) -> &Vec<u8> {
        &self.retained.as_ref().expect("owned record lease").bytes
    }
    pub(in crate::commands::ui) fn adopt<'ticket>(
        mut self,
        ticket: PrivateRecordAdoption<'ticket>,
    ) -> Result<data::Bytes, &'ticket PrivateRecordError> {
        let RetainedRecord { bytes, work } = self.retained.take().expect("single-use record lease");
        let result = ticket.commit(bytes);
        self.slot.transferred();
        // commit has consumed/dropped the raw buffer on every error path.
        drop(work);
        result
    }
}
impl Drop for PrivateRecordLease {
    fn drop(&mut self) {
        if let Some(RetainedRecord { bytes, work }) = self.retained.take() {
            drop(bytes);
            self.slot.transferred();
            drop(work);
        }
    }
}

struct Association {
    id: CaptureId,
    attempt: AttemptKey,
    owner: Weak<Mutex<ConnectionOwner>>,
    slot: Weak<RecordSlot>,
}
struct RegistryState {
    entries: [Option<Association>; MAX_HOST_CAPTURES],
}
/// Fixed bounded host infrastructure, not capture resident storage or a journal.
#[derive(Clone)]
pub(in crate::commands::ui) struct PrivateRecordRegistry(Arc<Mutex<RegistryState>>);
impl PrivateRecordRegistry {
    pub(in crate::commands::ui) fn new() -> Self {
        Self(Arc::new(Mutex::new(RegistryState {
            entries: std::array::from_fn(|_| None),
        })))
    }
    pub(in crate::commands::ui) fn observer(&self) -> HostPrivateRecordObserver {
        HostPrivateRecordObserver(Arc::downgrade(&self.0))
    }
    fn insert(
        &self,
        id: &CaptureId,
        owner: &Arc<Mutex<ConnectionOwner>>,
        slot: &Arc<RecordSlot>,
    ) -> Result<(), CaptureError> {
        let mut state = self.0.lock().expect("private record registry");
        for entry in &mut state.entries {
            if entry.as_ref().is_some_and(|entry| {
                entry.owner.strong_count() == 0 || entry.slot.strong_count() == 0
            }) {
                *entry = None;
            }
        }
        let entry = state
            .entries
            .iter_mut()
            .find(|entry| entry.is_none())
            .ok_or(CaptureError::Capacity)?;
        // RecordSlot's credit conservatively reserved this association and128
        // retained ID bytes before slot/association construction.
        let mut key = String::new();
        key.try_reserve_exact(id.0.len())
            .map_err(|_| CaptureError::Capacity)?;
        key.push_str(&id.0);
        *entry = Some(Association {
            id: CaptureId(key),
            attempt: slot.attempt,
            owner: Arc::downgrade(owner),
            slot: Arc::downgrade(slot),
        });
        Ok(())
    }
    fn remove(&self, id: &CaptureId, owner: &Arc<Mutex<ConnectionOwner>>) {
        let weak = Arc::downgrade(owner);
        for entry in &mut self.0.lock().expect("private record registry").entries {
            if entry
                .as_ref()
                .is_some_and(|entry| &entry.id == id && Weak::ptr_eq(&entry.owner, &weak))
            {
                *entry = None;
            }
        }
    }
}
/// Issued by an actual bound host. Capture labels alone cannot create this view.
#[derive(Clone)]
pub(in crate::commands::ui) struct HostPrivateRecordObserver(Weak<Mutex<RegistryState>>);
impl HostPrivateRecordObserver {
    pub(in crate::commands::ui) fn for_capture(
        &self,
        id: &CaptureId,
    ) -> Result<PrivateRecordObserver, PrivateRecordObservationError> {
        let registry = self
            .0
            .upgrade()
            .ok_or(PrivateRecordObservationError::NotOwned)?;
        // Release registry lock BEFORE actual connection lookup; publication has
        // the reverse acquisition order and must never deadlock with observers.
        let (owner, attempt, slot) = {
            let state = registry.lock().expect("private record registry");
            let entry = state
                .entries
                .iter()
                .flatten()
                .find(|entry| &entry.id == id)
                .ok_or(PrivateRecordObservationError::NotOwned)?;
            (entry.owner.clone(), entry.attempt, entry.slot.clone())
        };
        let actual = owner
            .upgrade()
            .ok_or(PrivateRecordObservationError::NotOwned)?;
        let state = actual.lock().expect("model capture connection");
        match &state.state {
            ConnectionState::Ready(capture)
                if &capture.id == id
                    && capture.attempt == attempt
                    && capture
                        .reservation
                        .record
                        .as_ref()
                        .is_some_and(|actual| Weak::ptr_eq(&Arc::downgrade(actual), &slot)) =>
            {
                Ok(PrivateRecordObserver { owner })
            }
            _ => Err(PrivateRecordObservationError::NotOwned),
        }
    }
}
