//! A single prearmed slot in the existing source owner. Business payloads move
//! through it; the coordinator precharges retained copies before acknowledgement.
use super::model_originals::{CaptureId, PrivateRecordObserver, observation::HostSourceLease};
use axum::extract::ws::Utf8Bytes;
use morphir_mck::workbench::model_originals::{
    installed::{
        InstalledClientRun, ObservationBufferRole, ObservationRecordRole, RetainedObservationText,
    },
    native::data,
};
use std::sync::{Mutex, MutexGuard};
use tokio::sync::Notify;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands::ui) enum HostEventKind {
    AuthenticatedConnection,
    ReceivedText,
    PreparedSend,
    SendOutcome,
    ReadyOpportunity,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands::ui) enum SendOutcome {
    Completed,
    Failed,
    TimedOut,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands::ui) enum HostEventError {
    Closed,
    Revoked,
    WrongEvent,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands::ui) enum HostEventRefusal {
    ForeignInvocation,
    Closed,
    Receiving,
    Record,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands::ui) struct EventKey {
    sequence: u64,
    connection: u64,
}
#[cfg(test)]
#[derive(Debug, Clone, Copy)]
pub(in crate::commands::ui) struct InstalledCollectedTestDiagnostic {
    pub kind: HostEventKind,
    pub key: EventKey,
    pub prepared: Option<EventKey>,
    pub outcome: Option<SendOutcome>,
    pub slot_checked_out: bool,
}
enum Payload {
    Authenticated,
    Received(Utf8Bytes),
    Prepared(String),
    Outcome {
        prepared: EventKey,
        outcome: SendOutcome,
    },
    Ready {
        id: CaptureId,
        observer: PrivateRecordObserver,
    },
}
impl Payload {
    fn kind(&self) -> HostEventKind {
        match self {
            Self::Authenticated => HostEventKind::AuthenticatedConnection,
            Self::Received(_) => HostEventKind::ReceivedText,
            Self::Prepared(_) => HostEventKind::PreparedSend,
            Self::Outcome { .. } => HostEventKind::SendOutcome,
            Self::Ready { .. } => HostEventKind::ReadyOpportunity,
        }
    }
    fn text(&self) -> Option<&str> {
        match self {
            Self::Received(raw) => Some(raw.as_str()),
            Self::Prepared(raw) => Some(raw),
            _ => None,
        }
    }
}
enum Slot {
    Empty,
    Offered(EventKey, Payload),
    Claimed(EventKey, Payload),
    CheckedOut(EventKey),
    Accepted(EventKey, Payload),
    Closed,
}
struct State {
    slot: Slot,
    sequence: u64,
    connections: u64,
}
#[cfg(test)]
type RetentionProbe = fn(&InstalledSlot) -> bool;
pub(in crate::commands::ui) struct InstalledSlot {
    state: Mutex<State>,
    changed: Notify,
    #[cfg(test)]
    hook: Mutex<Option<InstalledSocketEntryTestHook>>,
    #[cfg(test)]
    retention_probe: Mutex<Option<RetentionProbe>>,
    #[cfg(test)]
    after_collect_probe: Mutex<Option<std::sync::mpsc::Sender<InstalledCollectedTestDiagnostic>>>,
}
impl InstalledSlot {
    pub(in crate::commands::ui) fn dormant() -> Self {
        Self {
            state: Mutex::new(State {
                slot: Slot::Empty,
                sequence: 0,
                connections: 0,
            }),
            changed: Notify::new(),
            #[cfg(test)]
            hook: Mutex::new(None),
            #[cfg(test)]
            retention_probe: Mutex::new(None),
            #[cfg(test)]
            after_collect_probe: Mutex::new(None),
        }
    }
    fn state(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|poison| {
            let mut state = poison.into_inner();
            state.slot = Slot::Closed;
            state
        })
    }
    pub(in crate::commands::ui) fn wake(&self) {
        self.changed.notify_waiters();
    }
    fn close(&self) {
        self.state().slot = Slot::Closed;
        self.wake();
    }
    #[cfg(test)]
    pub(in crate::commands::ui) fn set_after_collect_test_probe(
        &self,
        sender: std::sync::mpsc::Sender<InstalledCollectedTestDiagnostic>,
    ) {
        *self.after_collect_probe.lock().unwrap() = Some(sender);
    }
    #[cfg(test)]
    pub(in crate::commands::ui) fn offered_test_diagnostic(
        &self,
    ) -> Option<InstalledCollectedTestDiagnostic> {
        let state = self.state.lock().ok()?;
        let Slot::Offered(key, payload) = &state.slot else {
            return None;
        };
        let (prepared, outcome) = match payload {
            Payload::Outcome { prepared, outcome } => (Some(*prepared), Some(*outcome)),
            _ => (None, None),
        };
        Some(InstalledCollectedTestDiagnostic {
            kind: payload.kind(),
            key: *key,
            prepared,
            outcome,
            slot_checked_out: false,
        })
    }
    #[cfg(test)]
    fn report_collected(&self, mut diagnostic: InstalledCollectedTestDiagnostic) {
        diagnostic.slot_checked_out = self.state.lock().is_ok_and(
            |state| matches!(state.slot, Slot::CheckedOut(key) if key == diagnostic.key),
        );
        let sender = self.after_collect_probe.lock().unwrap().clone();
        if let Some(sender) = sender {
            let _ = sender.send(diagnostic);
        }
    }
}
pub(in crate::commands::ui) struct InstalledHostObservation {
    source: HostSourceLease,
}
enum ReceiverPoll {
    Wait,
    Closed,
    Claimed { key: EventKey, kind: HostEventKind },
}
impl InstalledHostObservation {
    pub(in crate::commands::ui) fn new(source: HostSourceLease) -> Self {
        Self { source }
    }
    pub(in crate::commands::ui) async fn next(&mut self) -> Option<PendingHostEvent> {
        loop {
            let slot = self.source.installed_slot();
            let changed = slot.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            // Check and claim under the SAME gate transition as canonical
            // revocation, with gate -> slot as the only nested lock order.
            let polled = self.source.invocation_gate().while_open(|| {
                let mut state = slot.state();
                match std::mem::replace(&mut state.slot, Slot::Empty) {
                    Slot::Offered(key, event) => {
                        let kind = event.kind();
                        state.slot = Slot::Claimed(key, event);
                        ReceiverPoll::Claimed { key, kind }
                    }
                    Slot::Closed => {
                        state.slot = Slot::Closed;
                        ReceiverPoll::Closed
                    }
                    other => {
                        state.slot = other;
                        ReceiverPoll::Wait
                    }
                }
            });
            match polled {
                Ok(ReceiverPoll::Claimed { key, kind }) => {
                    return Some(PendingHostEvent {
                        source: self.source.clone(),
                        key,
                        kind,
                        armed: true,
                    });
                }
                Ok(ReceiverPoll::Wait) => {}
                Ok(ReceiverPoll::Closed) | Err(_) => {
                    slot.close();
                    return None;
                }
            }
            changed.await;
        }
    }
    pub(in crate::commands::ui) fn close(&mut self) {
        self.source.installed_slot().close();
    }
}
impl Drop for InstalledHostObservation {
    fn drop(&mut self) {
        self.source.installed_slot().close();
    }
}
#[derive(Clone)]
pub(in crate::commands::ui) struct InstalledSocket {
    source: HostSourceLease,
    connection: u64,
}
impl InstalledSocket {
    pub(in crate::commands::ui) async fn authenticate(
        source: HostSourceLease,
    ) -> Result<Self, HostEventError> {
        let connection = source
            .invocation_gate()
            .while_open(|| {
                let mut state = source.installed_slot().state();
                if matches!(state.slot, Slot::Closed) {
                    return Err(HostEventError::Closed);
                }
                state.connections = state
                    .connections
                    .checked_add(1)
                    .ok_or(HostEventError::Closed)?;
                Ok(state.connections)
            })
            .map_err(|_| HostEventError::Revoked)??;
        let socket = Self { source, connection };
        socket.offer(Payload::Authenticated).await?;
        Ok(socket)
    }
    async fn offer(&self, event: Payload) -> Result<(EventKey, Payload), HostEventError> {
        let mut event = Some(event);
        let key = loop {
            let slot = self.source.installed_slot();
            let changed = slot.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let result = self
                .source
                .invocation_gate()
                .while_open(|| {
                    let mut state = slot.state();
                    match state.slot {
                        Slot::Closed => Err(HostEventError::Closed),
                        Slot::Empty => {
                            state.sequence = state
                                .sequence
                                .checked_add(1)
                                .ok_or(HostEventError::Closed)?;
                            let key = EventKey {
                                sequence: state.sequence,
                                connection: self.connection,
                            };
                            state.slot = Slot::Offered(key, event.take().expect("one publication"));
                            Ok(Some(key))
                        }
                        _ => Ok(None),
                    }
                })
                .map_err(|_| HostEventError::Revoked)??;
            if let Some(key) = result {
                slot.wake();
                break key;
            }
            changed.await;
        };
        let mut guard = Publication {
            source: &self.source,
            armed: true,
        };
        loop {
            let slot = self.source.installed_slot();
            let changed = slot.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            self.source
                .invocation_gate()
                .while_open(|| ())
                .map_err(|_| HostEventError::Revoked)?;
            {
                let mut state = slot.state();
                match std::mem::replace(&mut state.slot, Slot::Empty) {
                    Slot::Accepted(actual, event) if actual == key => {
                        guard.armed = false;
                        slot.wake();
                        return Ok((key, event));
                    }
                    Slot::Closed => {
                        state.slot = Slot::Closed;
                        return Err(HostEventError::Closed);
                    }
                    other => state.slot = other,
                }
            }
            changed.await;
        }
    }
    pub(in crate::commands::ui) async fn received(
        &self,
        raw: Utf8Bytes,
    ) -> Result<Utf8Bytes, HostEventError> {
        let (_, Payload::Received(raw)) = self.offer(Payload::Received(raw)).await? else {
            unreachable!()
        };
        Ok(raw)
    }
    pub(in crate::commands::ui) async fn prepared(
        &self,
        raw: String,
    ) -> Result<(EventKey, String), HostEventError> {
        let (key, Payload::Prepared(raw)) = self.offer(Payload::Prepared(raw)).await? else {
            unreachable!()
        };
        Ok((key, raw))
    }
    pub(in crate::commands::ui) async fn outcome(
        &self,
        prepared: EventKey,
        outcome: SendOutcome,
    ) -> Result<(), HostEventError> {
        self.offer(Payload::Outcome { prepared, outcome })
            .await
            .map(|_| ())
    }
    pub(in crate::commands::ui) async fn ready(
        &self,
        id: CaptureId,
        observer: PrivateRecordObserver,
    ) -> Result<CaptureId, HostEventError> {
        let (_, Payload::Ready { id, .. }) = self.offer(Payload::Ready { id, observer }).await?
        else {
            unreachable!()
        };
        Ok(id)
    }
}
struct Publication<'a> {
    source: &'a HostSourceLease,
    armed: bool,
}
impl Drop for Publication<'_> {
    fn drop(&mut self) {
        if self.armed {
            self.source.installed_slot().close();
        }
    }
}
pub(in crate::commands::ui) struct PendingHostEvent {
    source: HostSourceLease,
    key: EventKey,
    kind: HostEventKind,
    armed: bool,
}
/// Stack ownership of the SAME business payload during receiving work. The
/// inline slot keeps its key and cannot publish another event until restore.
struct CheckedOutPayload<'a> {
    event: Option<Payload>,
    source: &'a HostSourceLease,
    key: EventKey,
}
impl CheckedOutPayload<'_> {
    fn event(&self) -> &Payload {
        self.event.as_ref().expect("checked-out business payload")
    }
    fn restore(mut self) -> Result<(), HostEventRefusal> {
        let mut state = self.source.installed_slot().state();
        if !matches!(state.slot,Slot::CheckedOut(key)if key==self.key) {
            return Err(HostEventRefusal::Closed);
        }
        state.slot = Slot::Claimed(
            self.key,
            self.event.take().expect("same checked-out payload"),
        );
        Ok(())
    }
}
impl Drop for CheckedOutPayload<'_> {
    fn drop(&mut self) {
        if self.event.is_some() {
            self.source.installed_slot().close();
        }
    }
}
impl PendingHostEvent {
    fn checkout(&self) -> Result<CheckedOutPayload<'_>, HostEventRefusal> {
        let mut state = self.source.installed_slot().state();
        match std::mem::replace(&mut state.slot, Slot::Closed) {
            Slot::Claimed(key, event) if key == self.key => {
                state.slot = Slot::CheckedOut(key);
                Ok(CheckedOutPayload {
                    event: Some(event),
                    source: &self.source,
                    key,
                })
            }
            other => {
                state.slot = other;
                Err(HostEventRefusal::Closed)
            }
        }
    }
    fn inspect<T>(&self, inspect: impl FnOnce(&Payload) -> T) -> Result<T, HostEventError> {
        let state = self.source.installed_slot().state();
        match &state.slot {
            Slot::Claimed(key, event) if *key == self.key => Ok(inspect(event)),
            _ => Err(HostEventError::WrongEvent),
        }
    }
    // Actual kind captured at claim is diagnostic DATA only. All operations
    // that borrow/retain/adopt/ack still validate the live actual slot and key.
    pub(in crate::commands::ui) fn kind(&self) -> HostEventKind {
        self.kind
    }
    pub(in crate::commands::ui) fn with_text<T>(
        &self,
        inspect: impl FnOnce(&str) -> T,
    ) -> Result<T, HostEventError> {
        self.inspect(|event| event.text().map(inspect))?
            .ok_or(HostEventError::WrongEvent)
    }
    pub(in crate::commands::ui) fn with_ready_record<T>(
        &self,
        inspect: impl FnOnce(&Vec<u8>) -> T,
    ) -> Result<T, HostEventError> {
        self.inspect(|event| match event {
            Payload::Ready { id, observer } => observer
                .with_ready_record(id, inspect)
                .map_err(|_| HostEventError::WrongEvent),
            _ => Err(HostEventError::WrongEvent),
        })?
    }
    fn accept(&mut self) -> Result<(), HostEventRefusal> {
        self.source
            .invocation_gate()
            .while_open(|| {
                let mut state = self.source.installed_slot().state();
                match std::mem::replace(&mut state.slot, Slot::Closed) {
                    Slot::Claimed(key, event) if key == self.key => {
                        state.slot = Slot::Accepted(key, event);
                        Ok(())
                    }
                    other => {
                        state.slot = other;
                        Err(HostEventRefusal::Closed)
                    }
                }
            })
            .map_err(|_| HostEventRefusal::Closed)??;
        self.armed = false;
        self.source.installed_slot().wake();
        Ok(())
    }
    pub(in crate::commands::ui) fn retain(
        self,
        run: &mut InstalledClientRun<'_>,
    ) -> Result<RetainedHostEvent, HostEventRefusal> {
        self.retain_with(run, |event, _| Ok(event))
    }
    pub(in crate::commands::ui) fn collect(
        self,
        run: &mut InstalledClientRun<'_>,
    ) -> Result<(), HostEventRefusal> {
        // Test-only lease exists only during this call. The probe sees actual
        // successful cache work while the same business slot is checked out.
        #[cfg(test)]
        let probe_source = self.source.clone();
        let finish = |event: RetainedHostEvent, run: &mut InstalledClientRun<'_>| {
            #[cfg(test)]
            let diagnostic = InstalledCollectedTestDiagnostic {
                kind: event.kind(),
                key: event.key(),
                prepared: event.prepared_event(),
                outcome: event.send_outcome(),
                slot_checked_out: false,
            };
            event.collect(run)?;
            #[cfg(test)]
            probe_source.installed_slot().report_collected(diagnostic);
            Ok(())
        };
        if self.kind() == HostEventKind::ReadyOpportunity {
            self.adopt_ready_with(run, finish)
        } else {
            self.retain_with(run, finish)
        }
    }
    fn retain_with<T>(
        mut self,
        run: &mut InstalledClientRun<'_>,
        finish: impl FnOnce(
            RetainedHostEvent,
            &mut InstalledClientRun<'_>,
        ) -> Result<T, HostEventRefusal>,
    ) -> Result<T, HostEventRefusal> {
        let projection = self.source.invocation_projection();
        if !run.host_invocation_matches(&projection) {
            return Err(HostEventRefusal::ForeignInvocation);
        }
        let checked_out = self.checkout()?;
        let payload = (|event: &Payload| {
            #[cfg(test)]
            self.source
                .installed_slot()
                .probe_retention()
                .map_err(|_| HostEventRefusal::Closed)?;
            let role = match event {
                Payload::Authenticated => ObservationRecordRole::AuthenticatedConnection,
                Payload::Received(_) => ObservationRecordRole::ReceivedFrame,
                Payload::Prepared(_) => ObservationRecordRole::SendAttempt,
                Payload::Outcome { .. } => ObservationRecordRole::SendOutcome,
                Payload::Ready { .. } => return Err(HostEventRefusal::Record),
            };
            run.retain_host_record(&projection, role)
                .map_err(|_| HostEventRefusal::Receiving)?;
            match event {
                Payload::Authenticated => Ok(RetainedPayload::Authenticated),
                Payload::Received(raw) => run
                    .retain_host_text(&projection, ObservationBufferRole::RpcRequest, raw.as_str())
                    .map(RetainedPayload::Received)
                    .map_err(|_| HostEventRefusal::Receiving),
                Payload::Prepared(raw) => run
                    .retain_host_text(&projection, ObservationBufferRole::RpcReply, raw.as_str())
                    .map(RetainedPayload::Prepared)
                    .map_err(|_| HostEventRefusal::Receiving),
                Payload::Outcome { prepared, outcome } => Ok(RetainedPayload::Outcome {
                    prepared: *prepared,
                    outcome: *outcome,
                }),
                _ => Err(HostEventRefusal::Record),
            }
        })(checked_out.event())?;
        let result = finish(
            RetainedHostEvent {
                key: self.key,
                payload,
            },
            run,
        )?;
        checked_out.restore()?;
        self.accept()?;
        Ok(result)
    }
    pub(in crate::commands::ui) fn adopt_ready(
        self,
        run: &mut InstalledClientRun<'_>,
    ) -> Result<RetainedHostEvent, HostEventRefusal> {
        self.adopt_ready_with(run, |event, _| Ok(event))
    }
    fn adopt_ready_with<T>(
        mut self,
        run: &mut InstalledClientRun<'_>,
        finish: impl FnOnce(
            RetainedHostEvent,
            &mut InstalledClientRun<'_>,
        ) -> Result<T, HostEventRefusal>,
    ) -> Result<T, HostEventRefusal> {
        let projection = self.source.invocation_projection();
        if !run.host_invocation_matches(&projection) {
            return Err(HostEventRefusal::ForeignInvocation);
        }
        let checked_out = self.checkout()?;
        let payload = (|event: &Payload| {
            #[cfg(test)]
            self.source
                .installed_slot()
                .probe_retention()
                .map_err(|_| HostEventRefusal::Closed)?;
            let Payload::Ready { id, observer } = event else {
                return Err(HostEventRefusal::Record);
            };
            run.retain_host_record(&projection, ObservationRecordRole::ReadyOpportunity)
                .map_err(|_| HostEventRefusal::Receiving)?;
            let retained_id = run
                .retain_host_text(
                    &projection,
                    ObservationBufferRole::CensusMetadata,
                    id.as_str(),
                )
                .map_err(|_| HostEventRefusal::Receiving)?;
            let ticket = observer
                .with_ready_record(id, |raw| run.prepare_private_record_adoption(raw))
                .map_err(|_| HostEventRefusal::Record)?
                .map_err(|_| HostEventRefusal::Receiving)?;
            let record = observer
                .take(id)
                .map_err(|_| HostEventRefusal::Record)?
                .adopt(ticket)
                .map_err(|_| HostEventRefusal::Receiving)?;
            Ok(RetainedPayload::Ready {
                id: RetainedCaptureId(retained_id),
                record,
            })
        })(checked_out.event())?;
        let result = finish(
            RetainedHostEvent {
                key: self.key,
                payload,
            },
            run,
        )?;
        checked_out.restore()?;
        self.accept()?;
        Ok(result)
    }
}
impl Drop for PendingHostEvent {
    fn drop(&mut self) {
        if self.armed {
            self.source.installed_slot().close();
        }
    }
}
enum RetainedPayload {
    Authenticated,
    Received(RetainedObservationText),
    Prepared(RetainedObservationText),
    Outcome {
        prepared: EventKey,
        outcome: SendOutcome,
    },
    Ready {
        id: RetainedCaptureId,
        record: data::Bytes,
    },
}
pub(in crate::commands::ui) struct RetainedCaptureId(RetainedObservationText);
impl RetainedCaptureId {
    pub(in crate::commands::ui) fn as_str(&self) -> &str {
        self.0.as_str()
    }
}
pub(in crate::commands::ui) struct RetainedHostEvent {
    key: EventKey,
    payload: RetainedPayload,
}
impl RetainedHostEvent {
    fn collect(self, run: &mut InstalledClientRun<'_>) -> Result<(), HostEventRefusal> {
        use morphir_mck::workbench::model_originals::installed::InstalledSendCompletion;
        let EventKey {
            sequence,
            connection,
        } = self.key;
        let result = match self.payload {
            RetainedPayload::Authenticated => {
                run.record_authenticated_connection(sequence, connection)
            }
            RetainedPayload::Received(text) => run.record_received_text(sequence, connection, text),
            RetainedPayload::Prepared(text) => run.record_prepared_send(sequence, connection, text),
            RetainedPayload::Outcome { prepared, outcome } => run.record_send_outcome(
                sequence,
                connection,
                prepared.sequence,
                match outcome {
                    SendOutcome::Completed => InstalledSendCompletion::Completed,
                    SendOutcome::Failed => InstalledSendCompletion::Failed,
                    SendOutcome::TimedOut => InstalledSendCompletion::TimedOut,
                },
            ),
            RetainedPayload::Ready { id: _, record } => {
                run.record_adopted_ready(sequence, connection, record)
            }
        };
        result.map_err(|_| HostEventRefusal::Receiving)
    }
    pub(in crate::commands::ui) fn key(&self) -> EventKey {
        self.key
    }
    pub(in crate::commands::ui) fn sequence(&self) -> u64 {
        self.key.sequence
    }
    pub(in crate::commands::ui) fn connection(&self) -> u64 {
        self.key.connection
    }
    pub(in crate::commands::ui) fn kind(&self) -> HostEventKind {
        match self.payload {
            RetainedPayload::Authenticated => HostEventKind::AuthenticatedConnection,
            RetainedPayload::Received(_) => HostEventKind::ReceivedText,
            RetainedPayload::Prepared(_) => HostEventKind::PreparedSend,
            RetainedPayload::Outcome { .. } => HostEventKind::SendOutcome,
            RetainedPayload::Ready { .. } => HostEventKind::ReadyOpportunity,
        }
    }
    pub(in crate::commands::ui) fn body(&self) -> Option<&str> {
        match &self.payload {
            RetainedPayload::Received(raw) | RetainedPayload::Prepared(raw) => Some(raw.as_str()),
            _ => None,
        }
    }
    pub(in crate::commands::ui) fn prepared_event(&self) -> Option<EventKey> {
        match self.payload {
            RetainedPayload::Outcome { prepared, .. } => Some(prepared),
            _ => None,
        }
    }
    pub(in crate::commands::ui) fn send_outcome(&self) -> Option<SendOutcome> {
        match self.payload {
            RetainedPayload::Outcome { outcome, .. } => Some(outcome),
            _ => None,
        }
    }
    pub(in crate::commands::ui) fn ready(&self) -> Option<(&RetainedCaptureId, &data::Bytes)> {
        match &self.payload {
            RetainedPayload::Ready { id, record } => Some((id, record)),
            _ => None,
        }
    }
}
#[cfg(test)]
pub(in crate::commands::ui) struct InstalledSocketEntryTestHook {
    entered: tokio::sync::oneshot::Sender<()>,
    resume: tokio::sync::oneshot::Receiver<()>,
    returned: tokio::sync::oneshot::Sender<()>,
}
#[cfg(test)]
impl InstalledSocketEntryTestHook {
    pub(in crate::commands::ui) fn new(
        entered: tokio::sync::oneshot::Sender<()>,
        resume: tokio::sync::oneshot::Receiver<()>,
        returned: tokio::sync::oneshot::Sender<()>,
    ) -> Self {
        Self {
            entered,
            resume,
            returned,
        }
    }
    pub(in crate::commands::ui) async fn pause(self) -> tokio::sync::oneshot::Sender<()> {
        let _ = self.entered.send(());
        let _ = self.resume.await;
        self.returned
    }
}
#[cfg(test)]
impl InstalledSlot {
    pub(in crate::commands::ui) fn set_retention_probe(&self, probe: fn(&InstalledSlot) -> bool) {
        *self.retention_probe.lock().expect("retention probe") = Some(probe);
    }
    pub(in crate::commands::ui) fn retention_state_is_unlocked(&self) -> bool {
        self.state.try_lock().is_ok()
    }
    fn probe_retention(&self) -> Result<(), HostEventError> {
        let probe = *self.retention_probe.lock().expect("retention probe");
        if probe.is_none_or(|probe| probe(self)) {
            Ok(())
        } else {
            Err(HostEventError::Closed)
        }
    }
    pub(in crate::commands::ui) fn set_entry_hook(&self, hook: InstalledSocketEntryTestHook) {
        *self.hook.lock().expect("entry hook") = Some(hook);
    }
    pub(in crate::commands::ui) fn take_entry_hook(&self) -> Option<InstalledSocketEntryTestHook> {
        self.hook.lock().expect("entry hook").take()
    }
}
