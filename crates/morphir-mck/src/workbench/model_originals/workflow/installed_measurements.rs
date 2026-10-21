//! Private factual DATA. Derived caches never serialize or issue live grants.
#[cfg(test)]
#[path = "installed_measurements_live_tests.rs"]
mod live_tests;
use super::observation_check::InstalledClientFault as Fault;
use super::*;
use crate::json::strict::Document;
use crate::workbench::model_originals as protocol;
pub(super) mod implementation;
use implementation::{ImplementationObservation, OsOperand};

pub struct ObservedBytes {
    storage: ObservedByteStorage,
}
enum ObservedByteStorage {
    Materialized { wire: input::Bytes, bytes: Vec<u8> },
    MovedUtf8(String),
    MovedHex(Vec<u8>),
}
struct PrefixHex<'a>(&'a [u8]);
impl std::fmt::Display for PrefixHex<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        const DIGITS: [&str; 16] = [
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
        ];
        for &byte in self.0 {
            f.write_str(DIGITS[(byte >> 4) as usize])?;
            f.write_str(DIGITS[(byte & 15) as usize])?;
        }
        Ok(())
    }
}
impl serde::Serialize for PrefixHex<'_> {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_str(self)
    }
}
impl std::fmt::Debug for ObservedBytes {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        struct Wire<'a>(&'a ObservedByteStorage);
        impl std::fmt::Debug for Wire<'_> {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                struct Text<'a>(&'a str);
                impl std::fmt::Debug for Text<'_> {
                    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        f.debug_tuple("Text").field(&self.0).finish()
                    }
                }
                struct Hex<'a>(&'a [u8]);
                impl std::fmt::Debug for Hex<'_> {
                    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        f.write_str("BytesHexHex(\"")?;
                        std::fmt::Display::fmt(&PrefixHex(self.0), f)?;
                        f.write_str("\")")
                    }
                }
                match self.0 {
                    ObservedByteStorage::Materialized { wire, .. } => std::fmt::Debug::fmt(wire, f),
                    ObservedByteStorage::MovedUtf8(text) => {
                        f.debug_struct("Utf8").field("text", &Text(text)).finish()
                    }
                    ObservedByteStorage::MovedHex(bytes) => {
                        f.debug_struct("Hex").field("hex", &Hex(bytes)).finish()
                    }
                }
            }
        }
        f.debug_struct("ObservedBytes")
            .field("wire", &Wire(&self.storage))
            .field("bytes", &self.as_bytes())
            .finish()
    }
}
impl ObservedBytes {
    pub(super) fn bytes(&self) -> &[u8] {
        self.as_bytes()
    }
    pub fn as_bytes(&self) -> &[u8] {
        match &self.storage {
            ObservedByteStorage::Materialized { bytes, .. }
            | ObservedByteStorage::MovedHex(bytes) => bytes,
            ObservedByteStorage::MovedUtf8(text) => text.as_bytes(),
        }
    }
    fn utf8<'a>(&'a self, owner: &mut Decoder) -> Result<Option<&'a str>, DecodeError> {
        match &self.storage {
            ObservedByteStorage::Materialized {
                wire: input::Bytes::Utf8 { text },
                ..
            } => Ok(Some(text.as_str())),
            ObservedByteStorage::MovedUtf8(text) => Ok(Some(text)),
            _ => {
                owner.bytes(self.as_bytes().len())?;
                Ok(std::str::from_utf8(self.as_bytes()).ok())
            }
        }
    }
    pub(in crate::workbench::model_originals::workflow) fn adopt_prefix(
        bytes: Vec<u8>,
        _permission: super::pipeline::installed::adapter::processes::IssuedPrefixProjection,
    ) -> Self {
        Self {
            storage: match String::from_utf8(bytes) {
                Ok(text) => ObservedByteStorage::MovedUtf8(text),
                Err(error) => ObservedByteStorage::MovedHex(error.into_bytes()),
            },
        }
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow) fn test_raw_capacity(&self) -> usize {
        match &self.storage {
            ObservedByteStorage::Materialized { bytes, .. }
            | ObservedByteStorage::MovedHex(bytes) => bytes.capacity(),
            ObservedByteStorage::MovedUtf8(text) => text.capacity(),
        }
    }
}
pub(super) enum ByteCacheError<E> {
    Decode(DecodeError),
    Storage(E),
}
impl<E> From<DecodeError> for ByteCacheError<E> {
    fn from(error: DecodeError) -> Self {
        Self::Decode(error)
    }
}
impl serde::Serialize for ObservedBytes {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeStruct;
        match &self.storage {
            ObservedByteStorage::Materialized { wire, .. } => wire.serialize(s),
            ObservedByteStorage::MovedUtf8(text) => {
                let mut value = s.serialize_struct("Bytes", 2)?;
                value.serialize_field("kind", "utf8")?;
                value.serialize_field("text", text)?;
                value.end()
            }
            ObservedByteStorage::MovedHex(bytes) => {
                let mut value = s.serialize_struct("Bytes", 2)?;
                value.serialize_field("kind", "hex")?;
                value.serialize_field("hex", &PrefixHex(bytes))?;
                value.end()
            }
        }
    }
}
impl Decode for ObservedBytes {
    fn decode(doc: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let wire = input::Bytes::decode(doc, owner)?;
        Self::from_wire(wire, owner)
    }
}
impl ObservedBytes {
    pub(super) fn from_wire(wire: input::Bytes, owner: &mut Decoder) -> Result<Self, DecodeError> {
        match Self::from_wire_with_storage::<std::convert::Infallible>(wire, owner, |_, _| Ok(())) {
            Ok(value) => Ok(value),
            Err(ByteCacheError::Decode(error)) => Err(error),
            Err(ByteCacheError::Storage(never)) => match never {},
        }
    }
    /// Saved decoding uses its existing Decoder logical destinations. Live
    /// receiving additionally funds requested storage and actual spare capacity
    /// before the SAME copy. The hook creates no owner or positive policy.
    pub(super) fn from_wire_with_storage<E>(
        wire: input::Bytes,
        owner: &mut Decoder,
        mut storage: impl FnMut(usize, usize) -> Result<(), E>,
    ) -> Result<Self, ByteCacheError<E>> {
        let length = match &wire {
            input::Bytes::Utf8 { text } => text.as_str().len(),
            input::Bytes::Hex { hex } => {
                owner.bytes(hex.as_str().len())?;
                protocol::fixture_bytes::hex_byte_length(hex.as_str())
                    .map_err(|_| DecodeError::Shape("literal hex"))?
            }
            _ => {
                return Err(DecodeError::Shape("observed bytes require retained literal").into());
            }
        };
        // Actual retained byte elements and copy/conversion visits, not RSS.
        owner.slots(length)?;
        owner.bytes(length)?;
        storage(length, length).map_err(ByteCacheError::Storage)?;
        let mut bytes = Vec::new();
        bytes
            .try_reserve_exact(length)
            .map_err(|_| DecodeError::Allocation)?;
        storage(
            0,
            bytes
                .capacity()
                .checked_sub(length)
                .ok_or(DecodeError::Limits)?,
        )
        .map_err(ByteCacheError::Storage)?;
        match &wire {
            input::Bytes::Utf8 { text } => bytes.extend_from_slice(text.as_str().as_bytes()),
            input::Bytes::Hex { hex } => {
                owner.bytes(
                    hex.as_str()
                        .len()
                        .checked_mul(2)
                        .ok_or(DecodeError::Limits)?,
                )?;
                for pair in hex.as_str().as_bytes().as_chunks::<2>().0 {
                    let text =
                        std::str::from_utf8(pair).map_err(|_| DecodeError::Shape("literal hex"))?;
                    bytes.push(
                        u8::from_str_radix(text, 16)
                            .map_err(|_| DecodeError::Shape("literal hex"))?,
                    );
                }
            }
            _ => return Err(DecodeError::Shape("observed literal").into()),
        }
        Ok(Self {
            storage: ObservedByteStorage::Materialized { wire, bytes },
        })
    }
}
macro_rules! ordinal {
    ($name:ident) => {
        #[derive(Debug, PartialEq, Eq)]
        pub struct $name(u64);
        impl $name {
            pub(super) fn get(&self) -> u64 {
                self.0
            }
        }
        impl Decode for $name {
            fn decode(v: &Document, o: &mut Decoder) -> Result<Self, DecodeError> {
                Natural::<0, { u64::MAX }>::decode(v, o).map(|value| Self(value.0))
            }
        }
        impl serde::Serialize for $name {
            fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
                self.0.serialize(s)
            }
        }
    };
}
ordinal!(EventSequence);
ordinal!(PreparedEventSequence);
impl PreparedEventSequence {
    pub(super) fn live(value: u64) -> Self {
        Self(value)
    }
}
ordinal!(ConnectionOrdinal);
words! { pub ProcessCommand { Connect => "connect", List => "list", Publish => "publish" } }
words! { pub DescendantCoverage { Unobserved => "unobserved", TerminationRequestedUnverified => "termination-requested-unverified" } }
#[derive(Debug)]
pub struct MeasuredBool(bool);
impl MeasuredBool {
    pub(super) fn live(value: bool) -> Self {
        Self(value)
    }
    pub(super) fn observed(&self) -> bool {
        self.0
    }
}
impl Decode for MeasuredBool {
    fn decode(doc: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        JsonBool::decode(doc, owner).map(|v| Self(v.0))
    }
}
impl serde::Serialize for MeasuredBool {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_bool(self.0)
    }
}
tagged! { pub ProcessExit("kind") {
    Code => "code" { value: Natural<0, {u32::MAX as u64}> => "value" },
    Signal => "signal" { value: Natural<1, {u32::MAX as u64}> => "value" },
    Other => "other" {},
} }
tagged! { pub DirectProcessCompletion("kind") {
    Finished => "finished" { exit: ProcessExit => "exit" },
    Incomplete => "incomplete" {},
} }
record! { pub ProcessMeasurement {
    directory:OsOperand=>"directory",
    process_ordinal: Natural<0,{u64::MAX}> => "processOrdinal",
    program: OsOperand => "program",
    arguments: Items<OsOperand,0,{usize::MAX}> => "arguments",
    action_index: Natural<0, {u64::MAX}> => "actionIndex",
    command: ProcessCommand => "command",
    completion: DirectProcessCompletion => "completion",
    stdout: ObservedBytes => "stdout",
    stderr: ObservedBytes => "stderr",
    stderr_truncated: MeasuredBool => "stderrTruncated",
    descendants: DescendantCoverage => "descendants",
} }
macro_rules! payload {
    ($name:ident,$maximum:expr) => {
        #[derive(Debug)]
        pub struct $name(String);
        impl $name {
            pub(super) fn text(&self) -> &str {
                &self.0
            }
        }
        impl Decode for $name {
            fn decode(v: &Document, o: &mut Decoder) -> Result<Self, DecodeError> {
                let text = string(v, o)?;
                if text.len() > $maximum {
                    return Err(DecodeError::Shape("profile frame byte limit"));
                }
                o.bytes(text.len())?;
                let mut owned = String::new();
                owned
                    .try_reserve_exact(text.len())
                    .map_err(|_| DecodeError::Allocation)?;
                owned.push_str(text);
                Ok(Self(owned))
            }
        }
        impl serde::Serialize for $name {
            fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
                s.serialize_str(&self.0)
            }
        }
    };
}
payload!(ReceivedPayload, protocol::MAX_REQUEST_BYTES);
payload!(PreparedPayload, protocol::transcript::MAX_REPLY_BYTES);
words! { pub SendCompletion { Completed => "completed", Failed => "failed", TimedOut => "timed-out" } }
tagged! { pub SocketEvent("kind") {
    AuthenticatedConnection => "authenticated-connection" {},
    ReceivedText => "received-text" { payload: ReceivedPayload => "payload" },
    PreparedSend => "prepared-send" { payload: PreparedPayload => "payload" },
    SendOutcome => "send-outcome" { prepared_sequence: PreparedEventSequence => "preparedSequence", outcome: SendCompletion => "outcome" },
    ReadyRecordAdopted => "ready-record-adopted" { bytes: ObservedBytes => "bytes" },
} }
record! { pub SequencedSocketEvent {
    sequence: EventSequence => "sequence", connection: ConnectionOrdinal => "connection", event: SocketEvent => "event",
} }
literal! { pub InvocationAssociation => "invocation-credential" }
record! { pub SelectedRuntimeData {
    session_id: protocol::SessionId => "sessionId", source: protocol::SourceIdentity => "source", project_id: protocol::ProjectId => "projectId",
} }
record! { pub HostMeasurement {
    association: InvocationAssociation => "association", selection: SelectedRuntimeData => "selection",
    events: Items<SequencedSocketEvent,0,{usize::MAX}> => "events",
    source: native_original::SourceMeasurements => "source", workers: native_original::WorkerMeasurements => "workers",
} }
tagged! { pub CensusEntry("kind") {
    File => "file" { path: SourcePath => "path", bytes: ObservedBytes => "bytes" },
    PhysicalDirectory => "physical-directory" { path: SourcePath => "path" },
} }
impl CensusEntry {
    pub(super) fn path(&self) -> &str {
        match self {
            Self::File { path, .. } | Self::PhysicalDirectory { path } => path.as_str(),
        }
    }
}
words! { pub SnapshotCoverage { Complete => "complete", Incomplete => "incomplete" } }
record! { pub FileSummary { path:SourcePath=>"path",byte_length:Natural<0,{u64::MAX}> =>"byteLength",sha256:ContentSha256=>"sha256" } }
record! { pub PostExitSnapshot {
    after_action:Natural<0,{u64::MAX}> =>"afterAction",root:Text<1,{usize::MAX}> =>"root",coverage:SnapshotCoverage=>"coverage",
    raw_entries:Items<CensusEntry,0,{usize::MAX}> =>"rawEntries",files:Items<FileSummary,0,{usize::MAX}> =>"files",
} }
literal! { pub Unobserved => "unobserved" }
record! { pub WireMeasurements {
    implementation: ImplementationObservation => "implementation",
    processes:Items<ProcessMeasurement,0,{usize::MAX}> =>"processes",host:HostMeasurement=>"host",
    destination:PostExitSnapshot=>"destination",published_relative_root:SourcePath=>"publishedRelativeRoot",scratch:PostExitSnapshot=>"scratch",
    dynamic_commit:Unobserved=>"dynamicCommit",dynamic_scratch_cleanup:Unobserved=>"dynamicScratchCleanup",client_release_acceptance:Unobserved=>"clientReleaseAcceptance",
} }
pub(super) struct ParsedFrame {
    pub(super) event: usize,
    pub(super) document: Option<Document>,
}
pub(super) struct StreamBytes {
    pub(super) path: String,
    pub(super) bytes: Vec<u8>,
}
pub(super) struct ProtocolFacts {
    pub(super) capture: protocol::CaptureExpectation,
    pub(super) inventory: protocol::CaptureInventory,
    pub(super) streams: Vec<StreamBytes>,
    pub(super) request: protocol::Request,
}
pub struct InstalledClientMeasurements {
    pub(super) wire: WireMeasurements,
    pub(super) frames: Vec<ParsedFrame>,
    pub(super) claims: Vec<Option<Document>>,
    pub(super) protocol: Result<ProtocolFacts, Fault>,
}
pub(super) enum LiveFrame {
    Received(String),
    Prepared(String),
}
/// Partial factual collection. The SAME helpers and caller Decoder also build
/// saved caches; malformed literals remain DATA, never invented successes.
pub(super) struct LiveMeasurements {
    pub(super) consumer:
        Option<super::pipeline::installed::adapter::processes::ConsumerOperationRecord>,
    pub(super) events: Vec<SequencedSocketEvent>,
    pub(super) frames: Vec<ParsedFrame>,
    pub(super) processes: Vec<ProcessMeasurement>,
    pub(super) claims: Vec<Option<Document>>,
    pub(super) descriptions:
        Vec<super::pipeline::installed::adapter::processes::ProcessDescription>,
    pub(super) tools: Vec<super::pipeline::installed::adapter::FinishedInstalledProcess>,
}
impl LiveMeasurements {
    pub(super) fn new() -> Self {
        Self {
            consumer: None,
            events: Vec::new(),
            frames: Vec::new(),
            processes: Vec::new(),
            claims: Vec::new(),
            descriptions: Vec::new(),
            tools: Vec::new(),
        }
    }
    pub(super) fn push_text(
        &mut self,
        sequence: u64,
        connection: u64,
        text: LiveFrame,
        owner: &mut Decoder,
    ) -> Result<(), DecodeError> {
        let event = match text {
            LiveFrame::Received(raw) if raw.len() <= protocol::MAX_REQUEST_BYTES => {
                SocketEvent::ReceivedText {
                    payload: ReceivedPayload(raw),
                }
            }
            LiveFrame::Prepared(raw) if raw.len() <= protocol::transcript::MAX_REPLY_BYTES => {
                SocketEvent::PreparedSend {
                    payload: PreparedPayload(raw),
                }
            }
            _ => return Err(DecodeError::Shape("profile frame byte limit")),
        };
        self.push_event(sequence, connection, event, owner)
    }
    pub(super) fn push_event(
        &mut self,
        sequence: u64,
        connection: u64,
        event: SocketEvent,
        owner: &mut Decoder,
    ) -> Result<(), DecodeError> {
        owner.ready()?;
        owner.slots(1)?;
        self.events
            .try_reserve_exact(1)
            .map_err(|_| DecodeError::Allocation)?;
        let raw = match &event {
            SocketEvent::ReceivedText { payload } => Some(payload.text()),
            SocketEvent::PreparedSend { payload } => Some(payload.text()),
            _ => None,
        };
        let parsed = if let Some(raw) = raw {
            owner.slots(1)?;
            self.frames
                .try_reserve_exact(1)
                .map_err(|_| DecodeError::Allocation)?;
            Some(literal(raw, owner)?)
        } else {
            None
        };
        if let Some(document) = parsed {
            self.frames.push(ParsedFrame {
                event: self.events.len(),
                document,
            });
        }
        self.events.push(SequencedSocketEvent {
            sequence: EventSequence(sequence),
            connection: ConnectionOrdinal(connection),
            event,
        });
        Ok(())
    }
    pub(super) fn push_process(
        &mut self,
        process: ProcessMeasurement,
        owner: &mut Decoder,
    ) -> Result<(), DecodeError> {
        owner.ready()?;
        owner.slots(2)?;
        self.processes
            .try_reserve_exact(1)
            .map_err(|_| DecodeError::Allocation)?;
        self.claims
            .try_reserve_exact(1)
            .map_err(|_| DecodeError::Allocation)?;
        let claim = match process.stdout.utf8(owner)? {
            Some(raw) => literal(raw, owner)?,
            None => None,
        };
        self.processes.push(process);
        self.claims.push(claim);
        Ok(())
    }
    pub(super) fn claim<'a>(
        &'a self,
        index: usize,
        keys: &[&str],
        owner: &mut Decoder,
    ) -> Result<Option<&'a Document>, DecodeError> {
        match self.claims.get(index).and_then(Option::as_ref) {
            Some(doc) => path(doc, keys, owner),
            None => Ok(None),
        }
    }
    pub(super) fn finish(
        self,
        implementation: ImplementationObservation,
        host: HostMeasurement,
        destination: PostExitSnapshot,
        published_relative_root: SourcePath,
        scratch: PostExitSnapshot,
        owner: &mut Decoder,
    ) -> Result<InstalledClientMeasurements, DecodeError> {
        let wire = WireMeasurements {
            implementation,
            processes: Items(self.processes),
            host,
            destination,
            published_relative_root,
            scratch,
            dynamic_commit: Unobserved,
            dynamic_scratch_cleanup: Unobserved,
            client_release_acceptance: Unobserved,
        };
        let protocol = prepare_protocol(&wire, &self.frames, owner)?;
        Ok(InstalledClientMeasurements {
            wire,
            frames: self.frames,
            claims: self.claims,
            protocol,
        })
    }
}
impl serde::Serialize for InstalledClientMeasurements {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        self.wire.serialize(s)
    }
}
/// Authorize the actual temporary reparse/typed-copy destinations on the SAME
/// Decoder before using the existing protocol parser. No resident/RSS claim.
pub(in crate::workbench::model_originals::workflow) fn reparse_credit(
    doc: &Document,
    owner: &mut Decoder,
) -> Result<(), DecodeError> {
    match doc {
        Document::String(text) => owner.bytes(text.len()),
        Document::Array(values) => {
            owner.slots(values.len())?;
            for value in values {
                reparse_credit(value, owner)?
            }
            Ok(())
        }
        Document::Object(fields) => {
            owner.slots(fields.len())?;
            for (key, value) in fields {
                owner.bytes(key.len())?;
                reparse_credit(value, owner)?
            }
            Ok(())
        }
        _ => Ok(()),
    }
}
fn literal(raw: &str, owner: &mut Decoder) -> Result<Option<Document>, DecodeError> {
    match owner.literal_with_raw(raw) {
        Ok((doc, _)) => Ok(Some(doc)),
        Err(error) => {
            owner.ready()?;
            if matches!(error, DecodeError::Allocation) {
                return Err(error);
            }
            Ok(None)
        }
    }
}
pub(super) fn member<'a>(
    doc: &'a Document,
    name: &str,
    owner: &mut Decoder,
) -> Result<Option<&'a Document>, DecodeError> {
    owner.ready()?;
    if let Document::Object(fields) = doc {
        for (key, value) in fields {
            owner.bytes(
                key.len()
                    .checked_add(name.len())
                    .ok_or(DecodeError::Limits)?,
            )?;
            if key == name {
                return Ok(Some(value));
            }
        }
    }
    Ok(None)
}
fn path<'a>(
    doc: &'a Document,
    keys: &[&str],
    owner: &mut Decoder,
) -> Result<Option<&'a Document>, DecodeError> {
    let mut value = Some(doc);
    for key in keys {
        value = match value {
            Some(doc) => member(doc, key, owner)?,
            None => None,
        }
    }
    Ok(value)
}
pub(super) fn text(doc: &Document) -> Option<&str> {
    match doc {
        Document::String(t) => Some(t),
        _ => None,
    }
}
pub(super) fn number(doc: &Document) -> Option<u64> {
    match doc {
        Document::Number(n)
            if !n.as_str().is_empty() && n.as_str().bytes().all(|b| b.is_ascii_digit()) =>
        {
            n.as_str().parse().ok()
        }
        _ => None,
    }
}
fn payload(wire: &WireMeasurements, event: usize) -> Option<&str> {
    match &wire.host.events.0.get(event)?.event {
        SocketEvent::ReceivedText { payload } => Some(payload.text()),
        SocketEvent::PreparedSend { payload } => Some(payload.text()),
        _ => None,
    }
}
struct ParsedExchange {
    request: protocol::Request,
    reply: usize,
    connection: u64,
}
fn exchange<'a>(wire: &'a WireMeasurements, e: &'a ParsedExchange) -> protocol::Exchange<'a> {
    protocol::Exchange {
        request: &e.request,
        reply: payload(wire, e.reply).unwrap_or(""),
    }
}
impl Decode for InstalledClientMeasurements {
    fn decode(doc: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        super::installed_client::copy_credit(doc, owner)?;
        let wire = WireMeasurements::decode(doc, owner)?;
        owner.slots(wire.host.events.0.len())?;
        let mut frames = Vec::new();
        frames
            .try_reserve_exact(wire.host.events.0.len())
            .map_err(|_| DecodeError::Allocation)?;
        for (event, _) in wire.host.events.0.iter().enumerate() {
            if let Some(raw) = payload(&wire, event) {
                frames.push(ParsedFrame {
                    event,
                    document: literal(raw, owner)?,
                })
            }
        }
        owner.slots(wire.processes.0.len())?;
        let mut claims = Vec::new();
        claims
            .try_reserve_exact(wire.processes.0.len())
            .map_err(|_| DecodeError::Allocation)?;
        for process in &wire.processes.0 {
            claims.push(match process.stdout.utf8(owner)? {
                Some(raw) => literal(raw, owner)?,
                None => None,
            })
        }
        let protocol = prepare_protocol(&wire, &frames, owner)?;
        Ok(Self {
            wire,
            frames,
            claims,
            protocol,
        })
    }
}

#[cfg(test)]
#[path = "installed_measurements_work_tests.rs"]
mod review_work;

#[cfg(test)]
#[path = "installed_measurements_budget_tests.rs"]
mod review_budget;

fn raw_credit(
    wire: &WireMeasurements,
    event: usize,
    passes: usize,
    owner: &mut Decoder,
) -> Result<(), DecodeError> {
    let raw = payload(wire, event).ok_or(DecodeError::Shape("retained frame"))?;
    owner.bytes(raw.len().checked_mul(passes).ok_or(DecodeError::Limits)?)
}
pub(in crate::workbench::model_originals::workflow) fn normalized_copy(
    path: &str,
    owner: &mut Decoder,
) -> Result<(), DecodeError> {
    owner.slots(1)?;
    owner.bytes(path.len())?;
    // SAME normalization iterator as the original collector; admit census and
    // later output copy bytes before its destination String, without guesses
    // about Unicode expansion, allocator headers or resident bytes.
    for ch in protocol::folded_chars(path) {
        owner.bytes(ch.len_utf8().checked_mul(2).ok_or(DecodeError::Limits)?)?;
    }
    Ok(())
}
pub(in crate::workbench::model_originals::workflow) fn namespace_path(
    path: &str,
    owner: &mut Decoder,
) -> Result<(), DecodeError> {
    owner.slots(1)?; // NamespacePath row
    normalized_copy(path, owner)?;
    for part in path.split('/') {
        owner.slots(1)?; // conservative actual prefix insertion upper bound
        normalized_copy(part, owner)?;
    }
    Ok(())
}
/// Concrete logical destinations only. Existing schema engines/std allocator
/// internals and comparison schedules are not claimed globally qualified here.
fn charge_inventory_metadata<'a>(
    capture: &protocol::CaptureExpectation,
    ready: &Document,
    pages: impl Iterator<Item = &'a Document> + Clone,
    owner: &mut Decoder,
) -> Result<(), DecodeError> {
    owner.ready()?;
    let roots = std::iter::once(capture.primary()).chain(capture.companions());
    owner.slots(roots.clone().count())?;
    for (index, root) in roots.clone().enumerate() {
        namespace_path(root.path.as_str(), owner)?;
        owner.bytes(root.path.as_str().len())?; // clone actual root path
        for other in roots.clone().take(index) {
            normalized_copy(root.path.as_str(), owner)?;
            normalized_copy(other.path.as_str(), owner)?;
        }
    }
    // Clone actual binding/capture identity strings, never a serialized proof.
    for keys in [
        &["result", "binding", "sessionId"][..],
        &["result", "binding", "source", "providerId"][..],
        &["result", "binding", "source", "locator"][..],
        &["result", "binding", "projectId"][..],
        &["result", "captureId"][..],
    ] {
        let value = path(ready, keys, owner)?
            .and_then(text)
            .ok_or(DecodeError::Shape("ready identity"))?;
        owner.bytes(value.len())?;
    }
    for page in pages {
        let Some(Document::Array(entries)) = path(page, &["result", "entries"], owner)? else {
            return Err(DecodeError::Shape("inventory entries"));
        };
        for entry in entries {
            let name = member(entry, "path", owner)?
                .and_then(text)
                .ok_or(DecodeError::Shape("entry path"))?;
            namespace_path(name, owner)?;
            owner.slots(2)?; // identity/path logical nodes
            let id = member(entry, "entryId", owner)?
                .and_then(text)
                .ok_or(DecodeError::Shape("entry identity"))?;
            owner.bytes(
                id.len()
                    .checked_add(name.len())
                    .ok_or(DecodeError::Limits)?,
            )?;
        }
    }
    Ok(())
}
fn prepare_protocol(
    wire: &WireMeasurements,
    frames: &[ParsedFrame],
    owner: &mut Decoder,
) -> Result<Result<ProtocolFacts, Fault>, DecodeError> {
    owner.ready()?;
    let bad = || Ok(Err(Fault::SocketFrame));
    owner.slots(wire.host.events.0.len())?;
    let mut exchanges = Vec::new();
    exchanges
        .try_reserve_exact(wire.host.events.0.len())
        .map_err(|_| DecodeError::Allocation)?;
    for frame in frames {
        if !matches!(
            wire.host.events.0[frame.event].event,
            SocketEvent::ReceivedText { .. }
        ) {
            continue;
        }
        let Some(doc) = &frame.document else {
            return bad();
        };
        let Some(method) = member(doc, "method", owner)?.and_then(text) else {
            return bad();
        };
        let prefix = "morphir.model-originals.";
        owner.bytes(
            method
                .len()
                .checked_add(prefix.len())
                .ok_or(DecodeError::Limits)?,
        )?;
        if !method.starts_with(prefix) {
            continue;
        }
        reparse_credit(doc, owner)?;
        reparse_credit(doc, owner)?;
        raw_credit(wire, frame.event, 1, owner)?;
        let Some(raw) = payload(wire, frame.event) else {
            return bad();
        };
        let Ok(request) = protocol::Request::parse(raw) else {
            return bad();
        };
        let connection = wire.host.events.0[frame.event].connection.get();
        let reply = (frame.event + 1..wire.host.events.0.len()).find(|&i| {
            wire.host.events.0[i].connection.get() == connection
                && matches!(
                    wire.host.events.0[i].event,
                    SocketEvent::PreparedSend { .. }
                )
        });
        let Some(reply) = reply else { return bad() };
        let Some(doc) = frames
            .iter()
            .find(|f| f.event == reply)
            .and_then(|f| f.document.as_ref())
        else {
            return bad();
        };
        reparse_credit(doc, owner)?;
        exchanges.push(ParsedExchange {
            request,
            reply,
            connection,
        });
    }
    let Some(first) = exchanges.first() else {
        return bad();
    };
    if exchanges.iter().any(|e| e.connection != first.connection) {
        return Ok(Err(Fault::SocketAssociation));
    }
    let borrow = |e| exchange(wire, e);
    raw_credit(wire, first.reply, 1, owner)?;
    let Ok(capture) = protocol::CaptureExpectation::from_exchange(
        &borrow(first),
        &wire.host.selection.session_id,
    ) else {
        return bad();
    };
    let mut end = 1;
    while end < exchanges.len()
        && matches!(
            exchanges[end].request.parameters(),
            protocol::Parameters::Inventory { .. }
        )
    {
        end += 1
    }
    let document = |event| {
        frames
            .iter()
            .find(|f| f.event == event)
            .and_then(|f| f.document.as_ref())
    };
    for e in &exchanges[1..end] {
        let Some(doc) = document(e.reply) else {
            return bad();
        };
        // Two actual page parses and two compact lexical passes in the same
        // verify_inventory/check_page core. Typed copied destinations separate.
        raw_credit(wire, e.reply, 4, owner)?;
        reparse_credit(doc, owner)?;
        if let Some(Document::Array(entries)) = path(doc, &["result", "entries"], owner)? {
            owner.slots(entries.len())?;
            for entry in entries {
                reparse_credit(entry, owner)?;
                reparse_credit(entry, owner)?;
                reparse_credit(entry, owner)?;
            }
        }
    }
    let Some(ready) = document(first.reply) else {
        return bad();
    };
    charge_inventory_metadata(
        &capture,
        ready,
        exchanges[1..end].iter().filter_map(|e| document(e.reply)),
        owner,
    )?;
    let Ok(inventory) = capture.verify_inventory_borrowed(exchanges[1..end].iter().map(borrow))
    else {
        return bad();
    };
    owner.slots(inventory.inventory().entries().len())?;
    let mut streams = Vec::new();
    streams
        .try_reserve_exact(inventory.inventory().entries().len())
        .map_err(|_| DecodeError::Allocation)?;
    while end < exchanges.len()
        && matches!(
            exchanges[end].request.parameters(),
            protocol::Parameters::Read { .. }
        )
    {
        if streams.len() >= inventory.inventory().entries().len() {
            return bad();
        }
        let protocol::Parameters::Read { target, .. } = exchanges[end].request.parameters() else {
            return bad();
        };
        let mut next = end + 1;
        while next < exchanges.len() {
            let protocol::Parameters::Read { target: other, .. } =
                exchanges[next].request.parameters()
            else {
                break;
            };
            if let (
                protocol::ReadTarget::Original { entry: a },
                protocol::ReadTarget::Original { entry: b },
            ) = (target, other)
            {
                owner.bytes(
                    a.as_str()
                        .len()
                        .checked_add(b.as_str().len())
                        .ok_or(DecodeError::Limits)?,
                )?;
            }
            if other != target {
                break;
            }
            next += 1;
        }
        let protocol::ReadTarget::Original { entry } = target else {
            return bad();
        };
        let mut metadata = None;
        for item in inventory.inventory().entries() {
            owner.bytes(
                item.id()
                    .as_str()
                    .len()
                    .checked_add(entry.as_str().len())
                    .ok_or(DecodeError::Limits)?,
            )?;
            if item.id() == entry {
                metadata = Some(item);
                break;
            }
        }
        let Some(metadata) = metadata else {
            return bad();
        };
        let protocol::inventory::EntryContent::File { byte_length, .. } = metadata.content() else {
            return bad();
        };
        owner.slots(*byte_length)?;
        owner.bytes(*byte_length)?;
        for e in &exchanges[end..next] {
            let Some(doc) = document(e.reply) else {
                return bad();
            };
            raw_credit(wire, e.reply, 1, owner)?;
            reparse_credit(doc, owner)?;
            if let Some(encoded) = path(doc, &["result", "content"], owner)?.and_then(text) {
                let estimate = encoded.len() / 4 * 3;
                owner.slots(estimate)?;
                owner.bytes(estimate)?;
                owner.bytes(encoded.len())?;
            }
        }
        let Ok(stream) =
            inventory.verify_stream_borrowed(target, exchanges[end..next].iter().map(borrow))
        else {
            return bad();
        };
        owner.bytes(metadata.path().len())?;
        let mut path = String::new();
        path.try_reserve_exact(metadata.path().len())
            .map_err(|_| DecodeError::Allocation)?;
        path.push_str(metadata.path());
        streams.push(StreamBytes {
            path,
            bytes: stream.into_bytes(),
        });
        end = next;
    }
    if exchanges.len() != end + 1 {
        return bad();
    }
    raw_credit(wire, exchanges[end].reply, 1, owner)?;
    if capture.verify_release(&borrow(&exchanges[end])).is_err() {
        return bad();
    }
    let first = exchanges
        .into_iter()
        .next()
        .ok_or(DecodeError::Shape("capture request"))?;
    Ok(Ok(ProtocolFacts {
        capture,
        inventory,
        streams,
        request: first.request,
    }))
}
