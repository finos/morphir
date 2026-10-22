//! Source-issued, prepaid host transcript DATA; not client acceptance or joins.
use super::*;
use std::ops::Range;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserHostTranscriptFault {
    Source,
    End,
    Capacity,
    Order,
    Poisoned,
    Incomplete,
}
/// A retained DATA lifecycle summary, independent of physical shutdown or any
/// workflow expectation. An issued but unfinished host never counts as absent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserIssuedHostsTerminal {
    NoneIssued,
    AllOperationsReported {
        hosts: usize,
        events: usize,
    },
    Incomplete {
        hosts: usize,
        unfinished: usize,
        pending: usize,
        first: Option<BrowserHostTranscriptFault>,
    },
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserHostTranscriptTerminal {
    AllOperationsReported {
        events: usize,
    },
    Incomplete {
        pending: usize,
        first: Option<BrowserHostTranscriptFault>,
    },
}
#[derive(Debug)]
pub enum BrowserHostTranscriptPrepareError {
    Input(BrowserInputError),
    Transcript(BrowserHostTranscriptFault),
}
impl From<BrowserInputError> for BrowserHostTranscriptPrepareError {
    fn from(e: BrowserInputError) -> Self {
        Self::Input(e)
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserHostInterruption {
    Source,
    End,
    Cancelled,
    Abandoned,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserHostPollState {
    NotStarted,
    Started,
    Unobserved,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserHostIoFailure {
    Transport,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserHostManifestFailure {
    DeliveryTaken,
    Poisoned,
    Shape,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserHostSendOutcome {
    Returned,
    Failed(BrowserHostIoFailure),
    Unfinished {
        cause: BrowserHostInterruption,
        poll: BrowserHostPollState,
    },
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserHostPeerFinish {
    ScriptFinished,
    Failed,
    Interrupted(BrowserHostInterruption),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserHostReadResult {
    Binary {
        bytes: usize,
    },
    Ping {
        bytes: usize,
    },
    Pong {
        bytes: usize,
    },
    Close {
        code: Option<u16>,
        reason_bytes: usize,
    },
    Eof,
    Failed(BrowserHostIoFailure),
    Unfinished {
        cause: BrowserHostInterruption,
        poll: BrowserHostPollState,
    },
}
pub enum BrowserHostReadOutcome<'a> {
    Text(&'a [u8]),
    Binary {
        bytes: usize,
    },
    Ping {
        bytes: usize,
    },
    Pong {
        bytes: usize,
    },
    Close {
        code: Option<u16>,
        reason_bytes: usize,
    },
    Eof,
    Failed(BrowserHostIoFailure),
    Unfinished {
        cause: BrowserHostInterruption,
        poll: BrowserHostPollState,
    },
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserHostFact {
    ManifestRequestReceived,
    ManifestResponsePrepared {
        status: u16,
    },
    ManifestResponseOverBound {
        status: u16,
        actual_bytes: usize,
        admitted_bytes: usize,
    },
    ManifestResponseUnfinished {
        cause: BrowserHostInterruption,
    },
    ManifestResponseFailed {
        cause: BrowserHostManifestFailure,
    },
    AuthenticatedPeerOpened,
    TextRequestReceived,
    TextRequestOverBound {
        actual_bytes: usize,
        admitted_bytes: usize,
    },
    PeerReadFinished {
        outcome: BrowserHostReadResult,
    },
    ReplySendAttempted,
    ReplySendAttemptOverBound {
        actual_bytes: usize,
        admitted_bytes: usize,
    },
    ReplySendReturned {
        outcome: BrowserHostSendOutcome,
    },
    PeerFinished {
        outcome: BrowserHostPeerFinish,
    },
}
struct Event {
    fact: BrowserHostFact,
    bytes: Option<Range<usize>>,
}
pub(super) enum HostSlot {
    Unissued,
    Issued(HostCache),
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum ManifestLifecycle {
    Unissued,
    Pending,
    Finished,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum PeerOperation {
    Read(usize),
    Reply(usize),
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum PeerLifecycle {
    Unopened,
    Open,
    Pending(PeerOperation),
    Finished(Option<PeerOperation>),
}
impl PeerLifecycle {
    fn pending(self) -> Option<PeerOperation> {
        match self {
            Self::Pending(p) | Self::Finished(Some(p)) => Some(p),
            _ => None,
        }
    }
}
pub(super) struct HostCache {
    raw: Vec<u8>,
    events: Vec<Event>,
    reads: Vec<usize>,
    replies: Vec<usize>,
    manifest_bound: usize,
    byte_limit: usize,
    event_limit: usize,
    first: Option<BrowserHostTranscriptFault>,
    manifest: ManifestLifecycle,
    peer: PeerLifecycle,
    next_read: usize,
    next_reply: usize,
}
impl HostCache {
    fn pending(&self) -> usize {
        usize::from(self.manifest == ManifestLifecycle::Pending)
            + usize::from(self.peer.pending().is_some())
    }
    fn terminal(&self) -> BrowserHostTranscriptTerminal {
        if self.first.is_none()
            && self.manifest == ManifestLifecycle::Finished
            && self.peer == PeerLifecycle::Finished(None)
            && self.next_read == self.reads.len()
            && self.next_reply == self.replies.len()
        {
            BrowserHostTranscriptTerminal::AllOperationsReported {
                events: self.events.len(),
            }
        } else {
            BrowserHostTranscriptTerminal::Incomplete {
                pending: self.pending(),
                first: self.first,
            }
        }
    }
    fn fault(&mut self, e: BrowserHostTranscriptFault) -> BrowserHostTranscriptFault {
        *self.first.get_or_insert(e)
    }
    fn append(
        &mut self,
        fact: BrowserHostFact,
        bytes: Option<&[u8]>,
    ) -> Result<(), BrowserHostTranscriptFault> {
        if self.events.len() >= self.event_limit
            || bytes.is_some_and(|b| {
                self.raw
                    .len()
                    .checked_add(b.len())
                    .is_none_or(|n| n > self.byte_limit)
            })
        {
            return Err(self.fault(BrowserHostTranscriptFault::Capacity));
        }
        let range = bytes.map(|b| {
            let start = self.raw.len();
            self.raw.extend_from_slice(b);
            start..self.raw.len()
        });
        self.events.push(Event { fact, bytes: range });
        Ok(())
    }
}
/// Single moved port; the engine retains its journal independently of this owner.
pub struct BrowserHostTranscript {
    journal: Arc<Mutex<Journal>>,
    relation: BrowserLoanStamp,
    end: Instant,
}
pub struct BrowserHostTranscriptSnapshot<'a> {
    cache: &'a HostCache,
}
pub struct BrowserHostTranscriptRecord<'a> {
    fact: &'a BrowserHostFact,
    bytes: Option<&'a [u8]>,
}
impl BrowserHostTranscriptSnapshot<'_> {
    pub fn event_count(&self) -> usize {
        self.cache.events.len()
    }
    pub fn event(&self, index: usize) -> Option<BrowserHostTranscriptRecord<'_>> {
        let e = self.cache.events.get(index)?;
        Some(BrowserHostTranscriptRecord {
            fact: &e.fact,
            bytes: e.bytes.as_ref().and_then(|r| self.cache.raw.get(r.clone())),
        })
    }
    pub fn first(&self) -> Option<BrowserHostTranscriptFault> {
        self.cache.first
    }
    pub fn pending(&self) -> usize {
        self.cache.pending()
    }
    pub fn terminal(&self) -> BrowserHostTranscriptTerminal {
        self.cache.terminal()
    }
}
impl BrowserHostTranscriptRecord<'_> {
    pub fn fact(&self) -> &BrowserHostFact {
        self.fact
    }
    pub fn bytes(&self) -> Option<&[u8]> {
        self.bytes
    }
}
impl BrowserDocumentSnapshot<'_> {
    pub fn host_transcript(&self) -> Option<BrowserHostTranscriptSnapshot<'_>> {
        match &self.state.host {
            HostSlot::Unissued => None,
            HostSlot::Issued(cache) => Some(BrowserHostTranscriptSnapshot { cache }),
        }
    }
}
impl BrowserRowCollection {
    /// Read-only retained DATA; this deliberately leaves document END and actual
    /// listener/socket/driver joins as separate observations.
    pub fn issued_hosts_terminal(&self) -> BrowserIssuedHostsTerminal {
        let (mut hosts, mut events, mut unfinished, mut pending, mut first) = (0, 0, 0, 0, None);
        for slot in &self.slots {
            let Slot::Issued { journal, .. } = slot else {
                continue;
            };
            let (journal, poisoned) = match journal.lock() {
                Ok(journal) => (journal, false),
                Err(poison) => (poison.into_inner(), true),
            };
            let HostSlot::Issued(cache) = &journal.host else {
                continue;
            };
            hosts += 1;
            events += cache.events.len();
            pending += cache.pending();
            if poisoned {
                unfinished += 1;
                first.get_or_insert(cache.first.unwrap_or(BrowserHostTranscriptFault::Poisoned));
            } else if let BrowserHostTranscriptTerminal::Incomplete { first: fault, .. } =
                cache.terminal()
            {
                unfinished += 1;
                if let Some(fault) = fault {
                    first.get_or_insert(fault);
                }
            }
        }
        if hosts == 0 {
            BrowserIssuedHostsTerminal::NoneIssued
        } else if unfinished == 0 {
            BrowserIssuedHostsTerminal::AllOperationsReported { hosts, events }
        } else {
            BrowserIssuedHostsTerminal::Incomplete {
                hosts,
                unfinished,
                pending,
                first,
            }
        }
    }
}
fn overflow(loans: &mut BrowserLoans<'_, '_>) -> BrowserInputError {
    refuse(loans, InstalledObservationFault::SizeOverflow)
}
impl BrowserDocumentProducer {
    pub fn prepare_host_transcript(
        &mut self,
        loans: &mut BrowserLoans<'_, '_>,
        stimulus: &ControlledHostStimulus,
        end: Instant,
    ) -> Result<BrowserHostTranscript, BrowserHostTranscriptPrepareError> {
        self.validate_host(loans, stimulus)?;
        if Instant::now() >= end {
            return Err(BrowserHostTranscriptPrepareError::Transcript(
                BrowserHostTranscriptFault::End,
            ));
        }
        {
            let journal = self.journal.lock().map_err(|_| {
                BrowserHostTranscriptPrepareError::Transcript(BrowserHostTranscriptFault::Poisoned)
            })?;
            if !matches!(journal.host, HostSlot::Unissued) {
                return Err(BrowserHostTranscriptPrepareError::Transcript(
                    BrowserHostTranscriptFault::Order,
                ));
            }
        }
        let request_count = stimulus.requests().map_or(0, <[String]>::len);
        let reply_count = stimulus.frames().len();
        let operand_count = request_count
            .checked_add(reply_count)
            .ok_or_else(|| overflow(loans))?;
        let shape_visits = operand_count
            .checked_mul(size_of::<String>())
            .ok_or_else(|| overflow(loans))?;
        loans.reserve_controlled_host_storage(0, 0, shape_visits)?;
        let event_limit = reply_count
            .checked_mul(2)
            .and_then(|n| n.checked_add(request_count))
            .and_then(|n| n.checked_add(4))
            .ok_or_else(|| overflow(loans))?;
        // The manifest bound is derived from both genuine source operands, including
        // deliberate over-limit body fixtures; it grants no additional delivery.
        let manifest_bound = usize::try_from(stimulus.manifest_byte_limit())
            .map_err(|_| overflow(loans))?
            .max(stimulus.manifest_body().len());
        let byte_limit = stimulus
            .requests()
            .into_iter()
            .flatten()
            .chain(stimulus.frames())
            .try_fold(manifest_bound, |n, s| n.checked_add(s.len()))
            .ok_or_else(|| overflow(loans))?;
        let mut reads = funded_vec(loans, request_count)?;
        let mut replies = funded_vec(loans, reply_count)?;
        let raw = funded_vec(loans, byte_limit)?;
        let events = funded_vec(loans, event_limit)?;
        // All later raw copies, comparisons, event writes, Arc counter changes and
        // owned pending wrappers are prepaid from these SAME cumulative owners.
        let tokens = operand_count
            .checked_add(1)
            .ok_or_else(|| overflow(loans))?;
        let handles = tokens.checked_add(1).ok_or_else(|| overflow(loans))?;
        let metadata = size_of::<HostCache>()
            .checked_add(size_of::<BrowserHostTranscript>())
            .and_then(|n| {
                tokens
                    .checked_mul(size_of::<Pending>() + 2 * size_of::<AtomicUsize>())
                    .and_then(|t| n.checked_add(t))
            })
            .ok_or_else(|| overflow(loans))?;
        let work = byte_limit
            .checked_add(
                event_limit
                    .checked_mul(size_of::<Event>())
                    .ok_or_else(|| overflow(loans))?,
            )
            .and_then(|n| n.checked_add(metadata))
            .and_then(|n| {
                operand_count
                    .checked_mul(size_of::<usize>())
                    .and_then(|v| n.checked_add(v))
            })
            .and_then(|n| {
                event_limit
                    .checked_mul(size_of::<HostCache>())
                    .and_then(|v| n.checked_add(v))
            })
            .ok_or_else(|| overflow(loans))?;
        loans.reserve_controlled_host_storage(metadata, handles, work)?;
        for request in stimulus.requests().into_iter().flatten() {
            reads.push(request.len());
        }
        for reply in stimulus.frames() {
            replies.push(reply.len());
        }
        let relation = loans.prepare_relation_stamp()?;
        self.relation
            .while_active(|| {
                if Instant::now() >= end {
                    return Err(BrowserHostTranscriptFault::End);
                }
                let mut journal = self
                    .journal
                    .lock()
                    .map_err(|_| BrowserHostTranscriptFault::Poisoned)?;
                if !matches!(journal.host, HostSlot::Unissued) {
                    return Err(BrowserHostTranscriptFault::Order);
                }
                journal.host = HostSlot::Issued(HostCache {
                    raw,
                    events,
                    reads,
                    replies,
                    manifest_bound,
                    byte_limit,
                    event_limit,
                    first: None,
                    manifest: ManifestLifecycle::Unissued,
                    peer: PeerLifecycle::Unopened,
                    next_read: 0,
                    next_reply: 0,
                });
                Ok(BrowserHostTranscript {
                    journal: Arc::clone(&self.journal),
                    relation,
                    end,
                })
            })
            .map_err(|_| {
                BrowserHostTranscriptPrepareError::Transcript(BrowserHostTranscriptFault::Source)
            })?
            .map_err(BrowserHostTranscriptPrepareError::Transcript)
    }
}
impl BrowserHostTranscript {
    /// Borrow only the original end of the exact already-prepared host slot.
    /// This issues no new time budget, host port, action or physical proof.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn source_controller_end(
        &self,
        producer: &BrowserDocumentProducer,
        stimulus: &ControlledHostStimulus,
        opening: usize,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<Instant, BrowserHostTranscriptPrepareError> {
        producer.validate_host(loans, stimulus)?;
        loans.validate_relation_stamp(&self.relation)?;
        if producer.opening != opening || !Arc::ptr_eq(&producer.journal, &self.journal) {
            return Err(BrowserHostTranscriptPrepareError::Input(
                inputs::BrowserInputFault::Source(BrowserSourceFault::ForeignSource).into(),
            ));
        }
        self.with_cache(|_| Ok(self.end))
            .map_err(BrowserHostTranscriptPrepareError::Transcript)
    }
    fn with_cache<R>(
        &self,
        operation: impl FnOnce(&mut HostCache) -> Result<R, BrowserHostTranscriptFault>,
    ) -> Result<R, BrowserHostTranscriptFault> {
        let result = self.relation.while_active(|| {
            let mut journal = self
                .journal
                .lock()
                .map_err(|_| BrowserHostTranscriptFault::Poisoned)?;
            let HostSlot::Issued(cache) = &mut journal.host else {
                return Err(BrowserHostTranscriptFault::Order);
            };
            if let Some(first) = cache.first {
                return Err(first);
            }
            if Instant::now() >= self.end {
                return Err(cache.fault(BrowserHostTranscriptFault::End));
            }
            operation(cache)
        });
        match result {
            Ok(result) => result,
            Err(_) => {
                if let Ok(mut j) = self.journal.lock() {
                    if let HostSlot::Issued(c) = &mut j.host {
                        c.fault(BrowserHostTranscriptFault::Source);
                    }
                }
                Err(BrowserHostTranscriptFault::Source)
            }
        }
    }
    pub fn begin_manifest(&self) -> Result<BrowserManifestPending, BrowserHostTranscriptFault> {
        self.with_cache(|c| {
            if c.manifest != ManifestLifecycle::Unissued {
                return Err(c.fault(BrowserHostTranscriptFault::Order));
            }
            c.append(BrowserHostFact::ManifestRequestReceived, None)?;
            c.manifest = ManifestLifecycle::Pending;
            Ok(())
        })?;
        Ok(BrowserManifestPending(Pending::new(
            &self.journal,
            Operation::Manifest,
        )))
    }
    pub fn peer_opened(&self) -> Result<(), BrowserHostTranscriptFault> {
        self.with_cache(|c| {
            if c.peer != PeerLifecycle::Unopened {
                return Err(c.fault(BrowserHostTranscriptFault::Order));
            }
            c.append(BrowserHostFact::AuthenticatedPeerOpened, None)?;
            c.peer = PeerLifecycle::Open;
            Ok(())
        })
    }
    pub fn begin_read(&self) -> Result<BrowserHostReadPending, BrowserHostTranscriptFault> {
        let index = self.with_cache(|c| {
            if c.peer != PeerLifecycle::Open
                || c.next_read >= c.reads.len()
                || c.next_read != c.next_reply
            {
                return Err(c.fault(BrowserHostTranscriptFault::Order));
            }
            let i = c.next_read;
            c.next_read += 1;
            c.peer = PeerLifecycle::Pending(PeerOperation::Read(i));
            Ok(i)
        })?;
        Ok(BrowserHostReadPending(Pending::new(
            &self.journal,
            Operation::Read(index),
        )))
    }
    pub fn begin_reply(
        &self,
        bytes: &[u8],
    ) -> Result<BrowserReplyPending, BrowserHostTranscriptFault> {
        let index = self.with_cache(|c| {
            if c.peer != PeerLifecycle::Open
                || c.next_reply >= c.replies.len()
                || (!c.reads.is_empty() && c.next_read != c.next_reply + 1)
            {
                return Err(c.fault(BrowserHostTranscriptFault::Order));
            }
            let index = c.next_reply;
            let admitted = c.replies[index];
            if bytes.len() > admitted {
                c.append(
                    BrowserHostFact::ReplySendAttemptOverBound {
                        actual_bytes: bytes.len(),
                        admitted_bytes: admitted,
                    },
                    None,
                )?;
                return Err(c.fault(BrowserHostTranscriptFault::Capacity));
            }
            c.append(BrowserHostFact::ReplySendAttempted, Some(bytes))?;
            c.next_reply += 1;
            c.peer = PeerLifecycle::Pending(PeerOperation::Reply(index));
            Ok(index)
        })?;
        Ok(BrowserReplyPending(Pending::new(
            &self.journal,
            Operation::Reply(index),
        )))
    }
    /// An actual already-open peer's outcome is DATA, including after refusal or
    /// revocation. This method cannot authorize a subsequent read or send.
    pub fn peer_finished(
        &self,
        outcome: BrowserHostPeerFinish,
    ) -> Result<(), BrowserHostTranscriptFault> {
        let mut j = self
            .journal
            .lock()
            .map_err(|_| BrowserHostTranscriptFault::Poisoned)?;
        let HostSlot::Issued(c) = &mut j.host else {
            return Err(BrowserHostTranscriptFault::Order);
        };
        if matches!(c.peer, PeerLifecycle::Unopened | PeerLifecycle::Finished(_)) {
            return Err(c.fault(BrowserHostTranscriptFault::Order));
        }
        c.append(BrowserHostFact::PeerFinished { outcome }, None)?;
        let pending = c.peer.pending();
        c.peer = PeerLifecycle::Finished(pending);
        if outcome != BrowserHostPeerFinish::ScriptFinished
            || c.next_read != c.reads.len()
            || c.next_reply != c.replies.len()
            || pending.is_some()
        {
            c.fault(BrowserHostTranscriptFault::Incomplete);
        }
        Ok(())
    }
}
impl Drop for BrowserHostTranscript {
    fn drop(&mut self) {
        if let Ok(mut j) = self.journal.lock() {
            if let HostSlot::Issued(c) = &mut j.host {
                if c.manifest != ManifestLifecycle::Finished
                    || c.peer != PeerLifecycle::Finished(None)
                {
                    c.fault(BrowserHostTranscriptFault::Incomplete);
                }
            }
        }
    }
}
#[derive(Clone, Copy)]
enum Operation {
    Manifest,
    Read(usize),
    Reply(usize),
}
struct Pending {
    journal: Arc<Mutex<Journal>>,
    operation: Operation,
    active: bool,
}
impl Pending {
    fn new(journal: &Arc<Mutex<Journal>>, operation: Operation) -> Self {
        Self {
            journal: Arc::clone(journal),
            operation,
            active: true,
        }
    }
    fn complete(
        &mut self,
        operation: impl FnOnce(&mut HostCache, Operation) -> Result<(), BrowserHostTranscriptFault>,
    ) -> Result<(), BrowserHostTranscriptFault> {
        let mut j = self
            .journal
            .lock()
            .map_err(|_| BrowserHostTranscriptFault::Poisoned)?;
        let HostSlot::Issued(c) = &mut j.host else {
            return Err(BrowserHostTranscriptFault::Order);
        };
        if !self.active {
            return Err(c.fault(BrowserHostTranscriptFault::Order));
        }
        self.active = false;
        match self.operation {
            Operation::Manifest => {
                if c.manifest != ManifestLifecycle::Pending {
                    return Err(c.fault(BrowserHostTranscriptFault::Order));
                }
                c.manifest = ManifestLifecycle::Finished;
            }
            Operation::Read(i) | Operation::Reply(i) => {
                let expected = match self.operation {
                    Operation::Read(_) => PeerOperation::Read(i),
                    _ => PeerOperation::Reply(i),
                };
                if c.peer.pending() != Some(expected) {
                    return Err(c.fault(BrowserHostTranscriptFault::Order));
                }
                c.peer = match c.peer {
                    PeerLifecycle::Finished(_) => PeerLifecycle::Finished(None),
                    _ => PeerLifecycle::Open,
                };
            }
        }
        operation(c, self.operation)
    }
}
impl Drop for Pending {
    fn drop(&mut self) {
        if self.active {
            let _ = self.complete(|c, op| {
                c.fault(BrowserHostTranscriptFault::Incomplete);
                let fact = match op {
                    Operation::Manifest => BrowserHostFact::ManifestResponseUnfinished {
                        cause: BrowserHostInterruption::Abandoned,
                    },
                    Operation::Read(_) => BrowserHostFact::PeerReadFinished {
                        outcome: BrowserHostReadResult::Unfinished {
                            cause: BrowserHostInterruption::Abandoned,
                            poll: BrowserHostPollState::Unobserved,
                        },
                    },
                    Operation::Reply(_) => BrowserHostFact::ReplySendReturned {
                        outcome: BrowserHostSendOutcome::Unfinished {
                            cause: BrowserHostInterruption::Abandoned,
                            poll: BrowserHostPollState::Unobserved,
                        },
                    },
                };
                c.append(fact, None)
            });
        }
    }
}
pub struct BrowserManifestPending(Pending);
pub struct BrowserHostReadPending(Pending);
pub struct BrowserReplyPending(Pending);
impl BrowserManifestPending {
    pub fn prepared(mut self, status: u16, body: &[u8]) -> Result<(), BrowserHostTranscriptFault> {
        self.0.complete(|c, _| {
            if body.len() > c.manifest_bound {
                c.append(
                    BrowserHostFact::ManifestResponseOverBound {
                        status,
                        actual_bytes: body.len(),
                        admitted_bytes: c.manifest_bound,
                    },
                    None,
                )?;
                return Err(c.fault(BrowserHostTranscriptFault::Capacity));
            }
            c.append(
                BrowserHostFact::ManifestResponsePrepared { status },
                Some(body),
            )
        })
    }
    pub fn unfinished(
        mut self,
        cause: BrowserHostInterruption,
    ) -> Result<(), BrowserHostTranscriptFault> {
        self.0.complete(|c, _| {
            c.fault(BrowserHostTranscriptFault::Incomplete);
            c.append(BrowserHostFact::ManifestResponseUnfinished { cause }, None)
        })
    }
    pub fn failed(
        mut self,
        cause: BrowserHostManifestFailure,
    ) -> Result<(), BrowserHostTranscriptFault> {
        self.0.complete(|c, _| {
            c.fault(BrowserHostTranscriptFault::Incomplete);
            c.append(BrowserHostFact::ManifestResponseFailed { cause }, None)
        })
    }
}
impl BrowserHostReadPending {
    pub fn finish(
        mut self,
        outcome: BrowserHostReadOutcome<'_>,
    ) -> Result<(), BrowserHostTranscriptFault> {
        self.0.complete(|c, op| {
            let Operation::Read(i) = op else {
                return Err(c.fault(BrowserHostTranscriptFault::Order));
            };
            let result = match outcome {
                BrowserHostReadOutcome::Text(bytes) => {
                    let admitted = c.reads[i];
                    if bytes.len() > admitted {
                        c.append(
                            BrowserHostFact::TextRequestOverBound {
                                actual_bytes: bytes.len(),
                                admitted_bytes: admitted,
                            },
                            None,
                        )?;
                        return Err(c.fault(BrowserHostTranscriptFault::Capacity));
                    }
                    return c.append(BrowserHostFact::TextRequestReceived, Some(bytes));
                }
                BrowserHostReadOutcome::Binary { bytes } => BrowserHostReadResult::Binary { bytes },
                BrowserHostReadOutcome::Ping { bytes } => BrowserHostReadResult::Ping { bytes },
                BrowserHostReadOutcome::Pong { bytes } => BrowserHostReadResult::Pong { bytes },
                BrowserHostReadOutcome::Close { code, reason_bytes } => {
                    BrowserHostReadResult::Close { code, reason_bytes }
                }
                BrowserHostReadOutcome::Eof => BrowserHostReadResult::Eof,
                BrowserHostReadOutcome::Failed(e) => BrowserHostReadResult::Failed(e),
                BrowserHostReadOutcome::Unfinished { cause, poll } => {
                    BrowserHostReadResult::Unfinished { cause, poll }
                }
            };
            c.fault(BrowserHostTranscriptFault::Incomplete);
            c.append(BrowserHostFact::PeerReadFinished { outcome: result }, None)
        })
    }
}
impl BrowserReplyPending {
    pub fn finish(
        mut self,
        outcome: BrowserHostSendOutcome,
    ) -> Result<(), BrowserHostTranscriptFault> {
        self.0.complete(|c, op| {
            let Operation::Reply(i) = op else {
                return Err(c.fault(BrowserHostTranscriptFault::Order));
            };
            debug_assert!(i < c.replies.len());
            if outcome != BrowserHostSendOutcome::Returned {
                c.fault(BrowserHostTranscriptFault::Incomplete);
            }
            c.append(BrowserHostFact::ReplySendReturned { outcome }, None)
        })
    }
}
#[cfg(test)]
#[path = "transcript/tests.rs"]
mod tests;
