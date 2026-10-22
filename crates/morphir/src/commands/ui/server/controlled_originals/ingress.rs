//! Authenticated document transport component. No browser/product authority.
#[cfg(test)]
#[path = "ingress/tests.rs"]
mod tests;

use super::*;
use morphir_mck::workbench::BrowserApplicationSource;
use morphir_mck::workbench::{BrowserDocumentError, BrowserDocumentErrorKind};
use tokio::sync::Notify;

const PROTOCOL: &str = "morphir-document-v1";
const CREDENTIAL_PREFIX: &str = "morphir-document-key.";
const MAX_SAFE: u64 = 9_007_199_254_740_991;
const HEADER_BYTES: usize = 16;
const REQUEST_LOOKUPS: usize = 8;
const DUPLICATE_VALUE_STEPS: usize = 8;
const LONGEST_LOOKUP_NAME: usize = 22;

pub(super) struct DocumentIngressLimits {
    pub(super) observation_owners: usize,
    pub(super) observation_events: usize,
    pub(super) records: usize,
    pub(super) journal_bytes: usize,
    pub(super) frame_bytes: usize,
    pub(super) socket_tasks: usize,
    pub(super) request_tickets: usize,
    pub(super) request_header_fields: usize,
    pub(super) request_header_bytes: usize,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands::ui) enum DocumentIngressFault {
    Capacity,
    SizeOverflow,
    Framing,
    Shape,
    Order,
    ForeignDocument,
    ProducerIncomplete,
    PeerRead,
    PeerWrite,
    LostAck,
    Source,
    End,
    Poisoned,
    Abandoned,
}
#[derive(Debug)]
pub(super) enum DocumentSetupFault {
    Host(ControlledHostSetupFault),
    Assets(assets::ObservedAssetsFault),
}
impl From<ControlledHostSetupFault> for DocumentSetupFault {
    fn from(cause: ControlledHostSetupFault) -> Self {
        Self::Host(cause)
    }
}
#[derive(Clone, Copy)]
struct Charge {
    retained: usize,
    slots: usize,
    visits: usize,
}
struct Dimensions {
    journal: Charge,
    transport: Charge,
}
fn add(a: usize, b: usize) -> Result<usize, ControlledHostSetupFault> {
    a.checked_add(b)
        .ok_or(ControlledHostSetupFault::SizeOverflow)
}
fn mul(a: usize, b: usize) -> Result<usize, ControlledHostSetupFault> {
    a.checked_mul(b)
        .ok_or(ControlledHostSetupFault::SizeOverflow)
}
impl DocumentIngressLimits {
    fn dimensions(&self) -> Result<Dimensions, ControlledHostSetupFault> {
        if self.frame_bytes < HEADER_BYTES {
            return Err(ControlledHostSetupFault::DocumentLimits);
        }
        for n in [
            self.observation_owners,
            self.observation_events,
            self.records,
            self.journal_bytes,
            self.frame_bytes,
            self.socket_tasks,
            self.request_tickets,
            self.request_header_fields,
            self.request_header_bytes,
        ] {
            if u64::try_from(n).map_or(true, |n| n > MAX_SAFE) {
                return Err(ControlledHostSetupFault::DocumentLimits);
            }
        }
        for n in [mul(self.records, 8)?, self.journal_bytes, self.frame_bytes] {
            if u32::try_from(n).is_err() {
                return Err(ControlledHostSetupFault::DocumentLimits);
            }
        }
        let backing = add(self.journal_bytes, mul(self.records, 8)?)?;
        let journal = Charge {
            retained: backing,
            slots: add(mul(104, self.records)?, 8)?,
            visits: add(
                add(
                    backing,
                    mul(self.records, add(4218, mul(66, self.frame_bytes)?)?)?,
                )?,
                8,
            )?,
        };
        let transport = Charge {
            retained: add(self.frame_bytes, HEADER_BYTES)?,
            slots: add(8, mul(2, self.records)?)?,
            visits: add(
                add(
                    add(self.frame_bytes, HEADER_BYTES)?,
                    mul(self.records, add(mul(2, self.frame_bytes)?, 64)?)?,
                )?,
                96,
            )?,
        };
        for n in [
            journal.retained,
            journal.slots,
            journal.visits,
            transport.retained,
            transport.slots,
            transport.visits,
        ] {
            if u64::try_from(n).map_or(true, |n| n > MAX_SAFE) {
                return Err(ControlledHostSetupFault::DocumentLimits);
            }
        }
        Ok(Dimensions { journal, transport })
    }
}
enum Admission {
    Prepared {
        body: axum::body::Bytes,
        headers: HeaderMap,
    },
    Bootstrapped,
    Admitted,
}
struct Record {
    kind: u8,
    sequence: u64,
    bytes: std::ops::Range<usize>,
}
enum Incoming {
    Vacant(Vec<u8>),
    Staged(Vec<u8>),
    Checking,
    Retained {
        buffer: Vec<u8>,
        kind: u8,
        sequence: u64,
    },
    AckWriting {
        buffer: Vec<u8>,
        kind: u8,
        sequence: u64,
    },
}
#[derive(Clone, Copy)]
enum Physical {
    Open,
    EndAckWritten,
    CloseSeen,
    Drained,
}
#[derive(Clone, Copy)]
enum Stop {
    NotRequested,
    Requested,
    Writing(u64),
    Sent(u64),
}
struct IngressState {
    admission: Admission,
    requests: usize,
    raw: Vec<u8>,
    records: Vec<Record>,
    incoming: Incoming,
    first: Option<DocumentIngressFault>,
    decode_error: Option<BrowserDocumentError>,
    actual_io: Option<ActualPeerFault>,
    physical: Physical,
    stop: Stop,
    last_fact: u64,
    last_ack_fact: u64,
}
pub(super) struct DocumentIngress {
    source: BrowserApplicationSource,
    auth: SessionAuth,
    limits: DocumentIngressLimits,
    state: Mutex<IngressState>,
    changed: Notify,
    send: Notify,
}
impl DocumentIngress {
    fn prepare(
        stimulus: &ControlledHostStimulus,
        loans: &mut BrowserLoans<'_, '_>,
        limits: DocumentIngressLimits,
        end: Instant,
    ) -> Result<Self, DocumentSetupFault> {
        loans
            .validate_controlled_source(stimulus)
            .map_err(ControlledHostSetupFault::Funding)?;
        let source = loans
            .prepare_application_source()
            .map_err(ControlledHostSetupFault::Funding)?;
        let dimensions = limits.dimensions()?;
        for charge in [dimensions.journal, dimensions.transport] {
            loans
                .reserve_application_storage(&source, charge.retained, charge.slots, charge.visits)
                .map_err(ControlledHostSetupFault::Funding)?;
        }
        // Named native buffers have immutable requested dimensions. Neither
        // allocator spare nor a producer mirror enlarges the stream bound.
        let native = add(
            add(limits.journal_bytes, limits.frame_bytes)?,
            add(
                mul(limits.records, std::mem::size_of::<Record>())?,
                std::mem::size_of::<Self>(),
            )?,
        )?;
        loans
            .reserve_application_storage(&source, native, add(limits.records, 3)?, native)
            .map_err(ControlledHostSetupFault::Funding)?;
        // Four duplicate get_all lookups, Cookie authentication, Host, Origin,
        // and offered protocol make eight lookups on an accepted upgrade.
        // http1.5.0 HeaderMap::find visits <=H occupied entries plus one
        // terminating probe. Each of four duplicate iterators takes <=2 steps.
        // Field/value lengths are bounded before any of these content scans.
        let lookups = mul(limits.request_tickets, REQUEST_LOOKUPS)?;
        let probes = mul(lookups, add(limits.request_header_fields, 1)?)?;
        let duplicate_steps = mul(limits.request_tickets, DUPLICATE_VALUE_STEPS)?;
        loans
            .reserve_application_comparison(
                &source,
                add(probes, duplicate_steps)?,
                add(
                    mul(mul(probes, 2)?, LONGEST_LOOKUP_NAME)?,
                    mul(mul(limits.request_tickets, limits.request_header_bytes)?, 6)?,
                )?,
                limits.request_tickets,
            )
            .map_err(ControlledHostSetupFault::Funding)?;
        loans
            .reserve_application_storage(
                &source,
                0,
                0,
                mul(
                    limits.request_tickets,
                    add(
                        add(
                            mul(limits.request_header_bytes, 16)?,
                            mul(limits.request_header_fields, 2)?,
                        )?,
                        mul(REQUEST_LOOKUPS, LONGEST_LOOKUP_NAME)?,
                    )?,
                )?,
            )
            .map_err(ControlledHostSetupFault::Funding)?;
        let raw = assets::allocate::<u8>(limits.journal_bytes, loans, &source, end)
            .map_err(DocumentSetupFault::Assets)?;
        let staging = assets::allocate::<u8>(limits.frame_bytes, loans, &source, end)
            .map_err(DocumentSetupFault::Assets)?;
        let records = assets::allocate::<Record>(limits.records, loans, &source, end)
            .map_err(DocumentSetupFault::Assets)?;
        let (auth, credential, unused_cookie) =
            SessionAuth::generate_prepaid_scoped(loans, "model-originals-document", &source, end)
                .map_err(ControlledHostSetupFault::Auth)?
                .into_parts();
        drop(unused_cookie);
        const SYNTAX: &str = r#"{"observation":{"owners":,"events":},"records":,"journalBytes":,"frameBytes":,"journalCharge":{"retainedBytes":,"slots":,"byteVisits":},"transportCharge":{"retainedBytes":,"slots":,"byteVisits":},"credential":""}"#;
        let capacity = add(SYNTAX.len(), add(mul(11, 16)?, 43)?)?;
        let owned = Layout::new::<std::sync::atomic::AtomicUsize>()
            .extend(Layout::new::<Vec<u8>>())
            .map_err(|_| ControlledHostSetupFault::SizeOverflow)?
            .0
            .pad_to_align()
            .size();
        let boxed_body = std::mem::size_of::<Option<axum::body::Bytes>>()
            + 2 * (std::mem::align_of::<Option<axum::body::Bytes>>() - 1);
        loans
            .reserve_application_storage(
                &source,
                add(capacity, add(owned, boxed_body)?)?,
                1,
                mul(capacity, 2)?,
            )
            .map_err(ControlledHostSetupFault::Funding)?;
        let mut body = assets::allocate::<u8>(capacity, loans, &source, end)
            .map_err(DocumentSetupFault::Assets)?;
        let headers = assets::prepare_document_headers(loans, &source, end)
            .map_err(DocumentSetupFault::Assets)?;
        let body=assets::source_work(&source,end,|| {
            use std::io::Write as _;
            // This fixed closed projection contains only admitted integers and
            // base64url. The checked upper capacity precedes this bounded write.
            body.resize(capacity,0);
            let mut destination=std::io::Cursor::new(body.as_mut_slice());
            write!(&mut destination,
                "{{\"observation\":{{\"owners\":{},\"events\":{}}},\"records\":{},\"journalBytes\":{},\"frameBytes\":{},\"journalCharge\":{{\"retainedBytes\":{},\"slots\":{},\"byteVisits\":{}}},\"transportCharge\":{{\"retainedBytes\":{},\"slots\":{},\"byteVisits\":{}}},\"credential\":\"{}\"}}",
                limits.observation_owners,limits.observation_events,limits.records,limits.journal_bytes,limits.frame_bytes,
                dimensions.journal.retained,dimensions.journal.slots,dimensions.journal.visits,
                dimensions.transport.retained,dimensions.transport.slots,dimensions.transport.visits,credential)
                .map_err(assets::ObservedAssetsFault::Io)?;
            let used=usize::try_from(destination.position()).map_err(|_|assets::ObservedAssetsFault::SizeOverflow)?;
            body.truncate(used);
            Ok(axum::body::Bytes::from_owner(body))
        }).map_err(DocumentSetupFault::Assets)?;
        let requests = limits.request_tickets;
        Ok(Self {
            source,
            auth,
            limits,
            state: Mutex::new(IngressState {
                admission: Admission::Prepared { body, headers },
                requests,
                raw,
                records,
                incoming: Incoming::Vacant(staging),
                first: None,
                decode_error: None,
                actual_io: None,
                physical: Physical::Open,
                stop: Stop::NotRequested,
                last_fact: 0,
                last_ack_fact: 0,
            }),
            changed: Notify::new(),
            send: Notify::new(),
        })
    }
    fn fault(&self, cause: DocumentIngressFault) {
        match self.state.lock() {
            Ok(mut state) => {
                state.first.get_or_insert(cause);
            }
            Err(poison) => {
                poison
                    .into_inner()
                    .first
                    .get_or_insert(DocumentIngressFault::Poisoned);
            }
        }
        self.changed.notify_one();
        self.send.notify_one();
    }
    fn request(&self, headers: &HeaderMap) -> Result<(), StatusCode> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
        state.requests = state
            .requests
            .checked_sub(1)
            .ok_or(StatusCode::SERVICE_UNAVAILABLE)?;
        if state.first.is_some() {
            return Err(StatusCode::SERVICE_UNAVAILABLE);
        }
        if headers.len() > self.limits.request_header_fields {
            return Err(StatusCode::REQUEST_HEADER_FIELDS_TOO_LARGE);
        }
        let mut bytes = 0usize;
        for (name, value) in headers {
            bytes = bytes
                .checked_add(name.as_str().len())
                .and_then(|n| n.checked_add(value.len()))
                .ok_or(StatusCode::REQUEST_HEADER_FIELDS_TOO_LARGE)?;
            if bytes > self.limits.request_header_bytes {
                return Err(StatusCode::REQUEST_HEADER_FIELDS_TOO_LARGE);
            }
        }
        for name in [
            header::HOST,
            header::ORIGIN,
            header::COOKIE,
            header::SEC_WEBSOCKET_PROTOCOL,
        ] {
            if headers.get_all(name).iter().nth(1).is_some() {
                return Err(StatusCode::FORBIDDEN);
            }
        }
        Ok(())
    }
}
impl BoundControlledUiHost {
    pub(super) async fn bind_with_document_ingress(
        stimulus: ControlledHostStimulus,
        loans: &mut BrowserLoans<'_, '_>,
        limits: DocumentIngressLimits,
        end: Instant,
    ) -> Result<Self, DocumentSetupFault> {
        Self::bind_prepared_document(stimulus, None, loans, limits, end).await
    }

    // Both constructors retain one controlled stimulus, auth exchange, source,
    // listener and socket registry. Assets never create a second host owner.
    pub(super) async fn bind_prepared_document(
        stimulus: ControlledHostStimulus,
        assets: Option<assets::HostAssets>,
        loans: &mut BrowserLoans<'_, '_>,
        limits: DocumentIngressLimits,
        end: Instant,
    ) -> Result<Self, DocumentSetupFault> {
        let slots = limits.socket_tasks;
        // Prepay every possible ACK and one STOP owner before binding. bytes'
        // from_owner stores repr(C) AtomicUsize followed by the16-byte owner.
        loans
            .validate_controlled_source(&stimulus)
            .map_err(ControlledHostSetupFault::Funding)?;
        let header_owner = Layout::new::<std::sync::atomic::AtomicUsize>()
            .extend(Layout::new::<[u8; HEADER_BYTES]>())
            .map_err(|_| ControlledHostSetupFault::SizeOverflow)?
            .0
            .pad_to_align()
            .size();
        let sends = add(limits.records, 1)?;
        reserve(
            loans,
            mul(sends, header_owner)?,
            sends,
            mul(sends, HEADER_BYTES)?,
        )?;
        // Stage copy, journal copy and fixed header handling; one additional
        // offending message can be refused, never retained as another record.
        reserve(
            loans,
            0,
            0,
            add(
                mul(mul(limits.records, limits.frame_bytes)?, 4)?,
                mul(add(limits.records, 1)?, HEADER_BYTES)?,
            )?,
        )?;
        let decode_source = loans
            .prepare_application_source()
            .map_err(ControlledHostSetupFault::Funding)?;
        let decoder = loans
            .prepare_document_decoder(&decode_source, limits.records, limits.frame_bytes)
            .map_err(ControlledHostSetupFault::Funding)?;
        let document = DocumentIngress::prepare(&stimulus, loans, limits, end)?;
        let mut host = Self::bind_inner(stimulus, assets, Some(document), slots, loans, end)
            .await
            .map_err(DocumentSetupFault::Host)?;
        host.document_decoder = Some(decoder);
        Ok(host)
    }
}
fn admit(state: &HostState, headers: &HeaderMap) -> Result<(), StatusCode> {
    let document = state
        .document
        .as_ref()
        .ok_or(StatusCode::SERVICE_UNAVAILABLE)?;
    document.request(headers)?;
    if !state.authenticated(headers) {
        return Err(StatusCode::UNAUTHORIZED);
    }
    if headers.get(header::HOST).and_then(|v| v.to_str().ok()) != Some(&state.authority)
        || headers.get(header::ORIGIN).and_then(|v| v.to_str().ok()) != Some(&state.origin)
    {
        return Err(StatusCode::FORBIDDEN);
    }
    Ok(())
}
pub(super) async fn bootstrap_route(
    State(state): State<Arc<HostState>>,
    headers: HeaderMap,
    uri: axum::http::Uri,
    _empty: axum::body::Bytes,
) -> Response {
    state
        .source
        .while_source_active(|| {
            if Instant::now() >= state.end {
                return StatusCode::SERVICE_UNAVAILABLE.into_response();
            }
            if let Err(status) = admit(&state, &headers) {
                return status.into_response();
            }
            if uri.query().is_some() {
                return StatusCode::FORBIDDEN.into_response();
            }
            let document = state.document.as_ref().expect("admission checked document");
            let Ok(mut inner) = document.state.lock() else {
                return StatusCode::SERVICE_UNAVAILABLE.into_response();
            };
            match std::mem::replace(&mut inner.admission, Admission::Bootstrapped) {
                Admission::Prepared { body, headers } => {
                    let mut response = Response::new(Body::from(body));
                    *response.headers_mut() = headers;
                    response
                }
                prior => {
                    inner.admission = prior;
                    StatusCode::CONFLICT.into_response()
                }
            }
        })
        .unwrap_or_else(|_| StatusCode::SERVICE_UNAVAILABLE.into_response())
}
pub(super) async fn upgrade_route(
    State(state): State<Arc<HostState>>,
    headers: HeaderMap,
    uri: axum::http::Uri,
    upgrade: WebSocketUpgrade,
) -> Response {
    let admitted = state.source.while_source_active(|| {
        if Instant::now() >= state.end {
            return Err(StatusCode::SERVICE_UNAVAILABLE);
        }
        admit(&state, &headers)?;
        if uri.query().is_some() {
            return Err(StatusCode::FORBIDDEN);
        }
        let document = state
            .document
            .as_ref()
            .ok_or(StatusCode::SERVICE_UNAVAILABLE)?;
        let mut inner = document
            .state
            .lock()
            .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
        if !matches!(inner.admission, Admission::Bootstrapped) {
            return Err(StatusCode::CONFLICT);
        }
        let offered = headers
            .get(header::SEC_WEBSOCKET_PROTOCOL)
            .and_then(|v| v.to_str().ok())
            .ok_or(StatusCode::FORBIDDEN)?;
        let mut tokens = offered.split(',');
        if tokens.next().map(str::trim) != Some(PROTOCOL) {
            return Err(StatusCode::FORBIDDEN);
        }
        let key = tokens
            .next()
            .map(str::trim)
            .and_then(|v| v.strip_prefix(CREDENTIAL_PREFIX))
            .ok_or(StatusCode::FORBIDDEN)?;
        if tokens.next().is_some() || key.len() != 43 || !document.auth.exchange_launch_token(key) {
            return Err(StatusCode::FORBIDDEN);
        }
        inner.admission = Admission::Admitted;
        Ok(document.limits.frame_bytes)
    });
    let limit = match admitted {
        Ok(Ok(limit)) => limit,
        Ok(Err(status)) => return status.into_response(),
        Err(_) => return StatusCode::SERVICE_UNAVAILABLE.into_response(),
    };
    let source = state.source.clone();
    let tasks = state.tasks.clone();
    let end = state.end;
    let (response, actual) = upgrade
        .protocols([PROTOCOL])
        .max_message_size(limit)
        .max_frame_size(limit)
        .into_upgrade_future(move |socket| serve(socket, state));
    match source.while_source_active(|| {
        if Instant::now() >= end {
            Err(SocketCleanupError::Closed)
        } else {
            tasks.spawn_upgrade(actual)
        }
    }) {
        Ok(Ok(())) => response,
        _ => StatusCode::SERVICE_UNAVAILABLE.into_response(),
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum DocumentCollectOutcome {
    Drained,
    Incomplete(DocumentIngressFault),
}
fn map_gate(cause: ControlledHostFault) -> DocumentIngressFault {
    match cause {
        ControlledHostFault::End => DocumentIngressFault::End,
        _ => DocumentIngressFault::Source,
    }
}
fn decode_kind(cause: &BrowserDocumentError) -> DocumentIngressFault {
    match cause.kind() {
        BrowserDocumentErrorKind::Source => DocumentIngressFault::Source,
        BrowserDocumentErrorKind::End => DocumentIngressFault::End,
        BrowserDocumentErrorKind::Capacity | BrowserDocumentErrorKind::Funding => {
            DocumentIngressFault::Capacity
        }
        BrowserDocumentErrorKind::Order => DocumentIngressFault::Order,
        BrowserDocumentErrorKind::ProducerIncomplete => DocumentIngressFault::ProducerIncomplete,
        BrowserDocumentErrorKind::Json | BrowserDocumentErrorKind::Shape => {
            DocumentIngressFault::Shape
        }
    }
}
struct CheckingFrame<'a> {
    document: &'a DocumentIngress,
    bytes: Option<Vec<u8>>,
}
impl Drop for CheckingFrame<'_> {
    fn drop(&mut self) {
        if let Some(bytes) = self.bytes.take() {
            let mut state = match self.document.state.lock() {
                Ok(state) => state,
                Err(poison) => poison.into_inner(),
            };
            if matches!(state.incoming, Incoming::Checking) {
                state.incoming = Incoming::Staged(bytes);
            }
            if std::thread::panicking() {
                state.first.get_or_insert(DocumentIngressFault::Abandoned);
            }
        }
    }
}
fn header(bytes: &[u8]) -> Result<(u8, u64), DocumentIngressFault> {
    if bytes.len() < HEADER_BYTES || bytes[0] != 1 || bytes[2] != 0 || bytes[3] != 0 {
        return Err(DocumentIngressFault::Framing);
    }
    let sequence = u64::from_be_bytes(
        bytes[4..12]
            .try_into()
            .map_err(|_| DocumentIngressFault::Framing)?,
    );
    let body = usize::try_from(u32::from_be_bytes(
        bytes[12..16]
            .try_into()
            .map_err(|_| DocumentIngressFault::Framing)?,
    ))
    .map_err(|_| DocumentIngressFault::SizeOverflow)?;
    if HEADER_BYTES.checked_add(body) != Some(bytes.len()) {
        return Err(DocumentIngressFault::Framing);
    }
    if !matches!(bytes[1], 1 | 2) {
        return Err(DocumentIngressFault::Shape);
    }
    Ok((bytes[1], sequence))
}
impl DocumentIngress {
    fn first(&self) -> Option<DocumentIngressFault> {
        match self.state.lock() {
            Ok(state) => state.first,
            Err(poison) => {
                let mut state = poison.into_inner();
                state.first.get_or_insert(DocumentIngressFault::Poisoned);
                state.first
            }
        }
    }
    fn take_frame(&self) -> Result<Option<CheckingFrame<'_>>, DocumentIngressFault> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| DocumentIngressFault::Poisoned)?;
        if let Some(first) = state.first {
            return Err(first);
        }
        match std::mem::replace(&mut state.incoming, Incoming::Checking) {
            Incoming::Staged(bytes) => Ok(Some(CheckingFrame {
                document: self,
                bytes: Some(bytes),
            })),
            prior => {
                state.incoming = prior;
                Ok(None)
            }
        }
    }
    fn retain(
        &self,
        mut frame: CheckingFrame<'_>,
        kind: u8,
        sequence: u64,
    ) -> Result<(), DocumentIngressFault> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| DocumentIngressFault::Poisoned)?;
        if let Some(first) = state.first {
            return Err(first);
        }
        if !matches!(state.incoming, Incoming::Checking) {
            return Err(DocumentIngressFault::Order);
        }
        let bytes = frame.bytes.as_ref().ok_or(DocumentIngressFault::Order)?;
        let finish = state
            .raw
            .len()
            .checked_add(bytes.len())
            .ok_or(DocumentIngressFault::SizeOverflow)?;
        if finish > self.limits.journal_bytes || state.records.len() >= self.limits.records {
            return Err(DocumentIngressFault::Capacity);
        }
        if sequence
            != state
                .last_fact
                .checked_add(1)
                .ok_or(DocumentIngressFault::SizeOverflow)?
        {
            return Err(DocumentIngressFault::Order);
        }
        let start = state.raw.len();
        state.raw.extend_from_slice(bytes);
        state.records.push(Record {
            kind,
            sequence,
            bytes: start..finish,
        });
        if kind == 1 {
            state.last_fact = sequence;
        }
        state.incoming = Incoming::Retained {
            buffer: frame.bytes.take().ok_or(DocumentIngressFault::Order)?,
            kind,
            sequence,
        };
        drop(state);
        self.send.notify_one();
        Ok(())
    }
    fn stage(&self, bytes: &[u8]) -> Result<(), DocumentIngressFault> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| DocumentIngressFault::Poisoned)?;
        if let Some(first) = state.first {
            return Err(first);
        }
        if !matches!(state.physical, Physical::Open) {
            return Err(DocumentIngressFault::Framing);
        }
        if bytes.len() > self.limits.frame_bytes || bytes.len() < HEADER_BYTES {
            return Err(DocumentIngressFault::Framing);
        }
        if state.records.len() >= self.limits.records {
            return Err(DocumentIngressFault::Capacity);
        }
        match std::mem::replace(&mut state.incoming, Incoming::Checking) {
            Incoming::Vacant(mut buffer) => {
                buffer.extend_from_slice(bytes);
                state.incoming = Incoming::Staged(buffer);
            }
            prior => {
                state.incoming = prior;
                return Err(DocumentIngressFault::Order);
            }
        }
        drop(state);
        self.changed.notify_one();
        Ok(())
    }
}
impl BoundControlledUiHost {
    pub(super) fn request_document_stop(&self) -> Result<(), DocumentIngressFault> {
        self.state
            .source
            .while_source_active(|| {
                if Instant::now() >= self.state.end {
                    return Err(DocumentIngressFault::End);
                }
                let document = self
                    .state
                    .document
                    .as_ref()
                    .ok_or(DocumentIngressFault::ForeignDocument)?;
                let mut state = document
                    .state
                    .lock()
                    .map_err(|_| DocumentIngressFault::Poisoned)?;
                if let Some(first) = state.first {
                    return Err(first);
                }
                if !matches!(state.stop, Stop::NotRequested)
                    || !matches!(state.physical, Physical::Open)
                {
                    drop(state);
                    document.fault(DocumentIngressFault::Order);
                    return Err(DocumentIngressFault::Order);
                }
                state.stop = Stop::Requested;
                drop(state);
                document.send.notify_one();
                Ok(())
            })
            .map_err(|_| DocumentIngressFault::Source)?
    }
    pub(super) async fn collect_document(
        &mut self,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> DocumentCollectOutcome {
        let host = &self.state;
        let Some(document) = host.document.as_ref() else {
            return DocumentCollectOutcome::Incomplete(DocumentIngressFault::ForeignDocument);
        };
        if loans
            .validate_controlled_application(&document.source, &host.source)
            .is_err()
        {
            document.fault(DocumentIngressFault::Source);
            return DocumentCollectOutcome::Incomplete(
                document.first().unwrap_or(DocumentIngressFault::Source),
            );
        }
        let Some(permission) = self.document_decoder.as_mut() else {
            return DocumentCollectOutcome::Incomplete(DocumentIngressFault::ForeignDocument);
        };
        let result = async {
            loop {
                let notified = document.changed.notified();
                if let Some(first) = document.first() {
                    return Err(first);
                }
                let frame = host
                    .source
                    .while_source_active(|| {
                        if Instant::now() >= host.end {
                            return Err(DocumentIngressFault::End);
                        }
                        document.take_frame()
                    })
                    .map_err(|_| DocumentIngressFault::Source)??;
                if let Some(frame) = frame {
                    let bytes = frame.bytes.as_ref().ok_or(DocumentIngressFault::Order)?;
                    let (kind, sequence) = header(bytes)?;
                    let expected = document
                        .state
                        .lock()
                        .map_err(|_| DocumentIngressFault::Poisoned)?
                        .last_fact
                        .checked_add(1)
                        .ok_or(DocumentIngressFault::SizeOverflow)?;
                    if sequence != expected {
                        return Err(DocumentIngressFault::Order);
                    }
                    if let Err(cause) = loans.validate_document_frame(
                        &document.source,
                        permission,
                        kind,
                        sequence,
                        &bytes[HEADER_BYTES..],
                        host.end,
                    ) {
                        let first = decode_kind(&cause);
                        let mut inner = document
                            .state
                            .lock()
                            .map_err(|_| DocumentIngressFault::Poisoned)?;
                        if inner.decode_error.is_none() {
                            inner.decode_error = Some(cause);
                        }
                        return Err(first);
                    }
                    host.source
                        .while_source_active(|| {
                            if Instant::now() >= host.end {
                                return Err(DocumentIngressFault::End);
                            }
                            document.retain(frame, kind, sequence)
                        })
                        .map_err(|_| DocumentIngressFault::Source)??;
                    continue;
                }
                let drained = matches!(
                    document
                        .state
                        .lock()
                        .map_err(|_| DocumentIngressFault::Poisoned)?
                        .physical,
                    Physical::Drained
                );
                if drained {
                    return Ok(());
                }
                gated(host, notified).await.map_err(map_gate)?;
            }
        }
        .await;
        match result {
            Ok(()) => DocumentCollectOutcome::Drained,
            Err(cause) => {
                document.fault(cause);
                host.fault(ControlledHostFault::Document(cause));
                let _ = loans.refuse_application(&document.source);
                DocumentCollectOutcome::Incomplete(document.first().unwrap_or(cause))
            }
        }
    }
}
enum Outgoing {
    Ack { kind: u8, sequence: u64 },
    Stop { sequence: u64 },
}
fn next_outgoing(document: &DocumentIngress) -> Result<Option<Outgoing>, DocumentIngressFault> {
    let mut state = document
        .state
        .lock()
        .map_err(|_| DocumentIngressFault::Poisoned)?;
    if let Some(first) = state.first {
        return Err(first);
    }
    match std::mem::replace(&mut state.incoming, Incoming::Checking) {
        Incoming::Retained {
            buffer,
            kind,
            sequence,
        } => {
            state.incoming = Incoming::AckWriting {
                buffer,
                kind,
                sequence,
            };
            return Ok(Some(Outgoing::Ack { kind, sequence }));
        }
        prior => state.incoming = prior,
    }
    if matches!(state.stop, Stop::Requested) {
        let sequence = state.last_ack_fact;
        state.stop = Stop::Writing(sequence);
        return Ok(Some(Outgoing::Stop { sequence }));
    }
    Ok(None)
}
fn control_frame(
    document: &DocumentIngress,
    end: Instant,
    kind: u8,
    sequence: u64,
) -> Result<axum::body::Bytes, DocumentIngressFault> {
    document
        .source
        .while_source_active(|| {
            if Instant::now() >= end {
                return Err(DocumentIngressFault::End);
            }
            let mut bytes = [0u8; HEADER_BYTES];
            bytes[0] = 1;
            bytes[1] = kind;
            bytes[4..12].copy_from_slice(&sequence.to_be_bytes());
            Ok(axum::body::Bytes::from_owner(bytes))
        })
        .map_err(|_| DocumentIngressFault::Source)?
}
struct ServeGuard(Arc<HostState>);
impl Drop for ServeGuard {
    fn drop(&mut self) {
        if let Some(document) = &self.0.document {
            let mut state = match document.state.lock() {
                Ok(state) => state,
                Err(poison) => poison.into_inner(),
            };
            if !matches!(state.physical, Physical::Drained) {
                state.first.get_or_insert(DocumentIngressFault::Abandoned);
            }
            drop(state);
            document.changed.notify_one();
            document.send.notify_one();
        }
    }
}
async fn serve(mut socket: WebSocket, state: Arc<HostState>) {
    let _guard = ServeGuard(Arc::clone(&state));
    let document = state.document.as_ref().expect("admitted document retained");
    let result: Result<(), DocumentIngressFault> = async {
        loop {
            let sent = document.send.notified();
            let command = state
                .source
                .while_source_active(|| {
                    if Instant::now() >= state.end {
                        return Err(DocumentIngressFault::End);
                    }
                    next_outgoing(document)
                })
                .map_err(|_| DocumentIngressFault::Source)??;
            if let Some(command) = command {
                let (wire, sequence) = match command {
                    Outgoing::Ack { sequence, .. } => (3, sequence),
                    Outgoing::Stop { sequence } => (4, sequence),
                };
                let bytes = control_frame(document, state.end, wire, sequence)?;
                if let Err(error) = gated(&state, socket.send(Message::Binary(bytes)))
                    .await
                    .map_err(map_gate)?
                {
                    if let Ok(mut inner) = document.state.lock()
                        && inner.actual_io.is_none()
                    {
                        inner.actual_io = Some(ActualPeerFault::Write(error));
                    }
                    return Err(if wire == 3 {
                        DocumentIngressFault::LostAck
                    } else {
                        DocumentIngressFault::PeerWrite
                    });
                }
                let mut inner = document
                    .state
                    .lock()
                    .map_err(|_| DocumentIngressFault::Poisoned)?;
                match command {
                    Outgoing::Ack { kind, sequence } => {
                        match std::mem::replace(&mut inner.incoming, Incoming::Checking) {
                            Incoming::AckWriting {
                                mut buffer,
                                kind: actual_kind,
                                sequence: actual_sequence,
                            } if actual_kind == kind && actual_sequence == sequence => {
                                buffer.clear();
                                inner.incoming = Incoming::Vacant(buffer);
                                if kind == 1 {
                                    inner.last_ack_fact = sequence;
                                } else {
                                    inner.physical = Physical::EndAckWritten;
                                }
                            }
                            prior => {
                                inner.incoming = prior;
                                return Err(DocumentIngressFault::Order);
                            }
                        }
                    }
                    Outgoing::Stop { sequence } => inner.stop = Stop::Sent(sequence),
                }
                drop(inner);
                document.changed.notify_one();
                continue;
            }
            let pending = !matches!(
                document
                    .state
                    .lock()
                    .map_err(|_| DocumentIngressFault::Poisoned)?
                    .incoming,
                Incoming::Vacant(_)
            );
            if pending {
                gated(&state, sent).await.map_err(map_gate)?;
                continue;
            }
            let message = tokio::select! {
                result=gated(&state,sent)=>{result.map_err(map_gate)?;continue;}
                message=gated(&state,socket.next())=>message.map_err(map_gate)?,
            };
            match message {
                Some(Ok(Message::Binary(bytes))) => {
                    state
                        .source
                        .while_source_active(|| {
                            if Instant::now() >= state.end {
                                return Err(DocumentIngressFault::End);
                            }
                            document.stage(&bytes)
                        })
                        .map_err(|_| DocumentIngressFault::Source)??;
                }
                Some(Ok(Message::Close(_))) => {
                    let mut inner = document
                        .state
                        .lock()
                        .map_err(|_| DocumentIngressFault::Poisoned)?;
                    if !matches!(inner.physical, Physical::EndAckWritten) {
                        return Err(DocumentIngressFault::ProducerIncomplete);
                    }
                    inner.physical = Physical::CloseSeen;
                }
                None => {
                    let mut inner = document
                        .state
                        .lock()
                        .map_err(|_| DocumentIngressFault::Poisoned)?;
                    if !matches!(inner.physical, Physical::CloseSeen) {
                        return Err(DocumentIngressFault::ProducerIncomplete);
                    }
                    inner.physical = Physical::Drained;
                    drop(inner);
                    document.changed.notify_one();
                    return Ok(());
                }
                Some(Err(error)) => {
                    if let Ok(mut inner) = document.state.lock()
                        && inner.actual_io.is_none()
                    {
                        inner.actual_io = Some(ActualPeerFault::Read(error));
                    }
                    return Err(DocumentIngressFault::PeerRead);
                }
                Some(Ok(_)) => return Err(DocumentIngressFault::Framing),
            }
        }
    }
    .await;
    if let Err(cause) = result {
        document.fault(cause);
        state.fault(ControlledHostFault::Document(cause));
    }
}
