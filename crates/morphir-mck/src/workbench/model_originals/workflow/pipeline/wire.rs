//! Selected Report wire data only. These types grant no source or runtime proof.
use super::super::installed_measurements::InstalledClientMeasurements;
use super::super::native_original::NativeDeclarationObservation;
use super::super::pairing::{PairedRun, PairedWorkflow};
use super::super::source_compile::CompiledExecution;
use super::super::{Decode, DecodeError, Decoder, Fields, Natural, UniqueKey, input, string};
use super::raw::VERSION;
use crate::json::strict::Document;
use crate::workbench::report::WorkflowExchangeRecord;
use serde::{Serialize, Serializer};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub(super) enum Role {
    #[serde(rename = "model-originals-server")]
    Server,
    #[serde(rename = "model-originals-client")]
    Client,
}
impl Role {
    pub(super) fn of(run: PairedRun<'_>) -> Self {
        match run {
            PairedRun::Server { .. } => Self::Server,
            PairedRun::Client { .. } => Self::Client,
        }
    }
    pub(super) fn text(self) -> &'static str {
        match self {
            Self::Server => "model-originals-server",
            Self::Client => "model-originals-client",
        }
    }
    fn decode(doc: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        match string(doc, owner)? {
            "model-originals-server" => Ok(Self::Server),
            "model-originals-client" => Ok(Self::Client),
            _ => Err(DecodeError::Shape("workflow role")),
        }
    }
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Capabilities {
    suite: String,
    contract_version: String,
    binding: String,
    language: String,
    operations: Vec<Role>,
    formats: [&'static str; 1],
}
impl Capabilities {
    pub(super) fn matches(&self, other: &Self, owner: &mut Decoder) -> Result<bool, DecodeError> {
        for (left, right) in [
            (&self.suite, &other.suite),
            (&self.contract_version, &other.contract_version),
            (&self.binding, &other.binding),
            (&self.language, &other.language),
        ] {
            owner.bytes(
                left.len()
                    .checked_add(right.len())
                    .ok_or(DecodeError::Limits)?,
            )?;
            if left != right {
                return Ok(false);
            }
        }
        if self.operations.len() != other.operations.len() {
            return Ok(false);
        }
        for (left, right) in self.operations.iter().zip(&other.operations) {
            owner.bytes(
                left.text()
                    .len()
                    .checked_add(right.text().len())
                    .ok_or(DecodeError::Limits)?,
            )?;
            if left != right {
                return Ok(false);
            }
        }
        Ok(self.formats == other.formats)
    }
    pub(super) fn supports(&self, role: Role) -> bool {
        self.operations.contains(&role)
    }
    pub(super) fn decode(
        doc: &Document,
        with_id: bool,
        owner: &mut Decoder,
    ) -> Result<Self, DecodeError> {
        let fields = Fields::new(
            doc,
            if with_id {
                &[
                    "id",
                    "suite",
                    "contractVersion",
                    "binding",
                    "language",
                    "operations",
                    "formats",
                ]
            } else {
                &[
                    "suite",
                    "contractVersion",
                    "binding",
                    "language",
                    "operations",
                    "formats",
                ]
            },
            owner,
        )?;
        if with_id {
            fields.field::<Natural<1, { u64::MAX }>>("id", owner)?;
        }
        let mut copy = |name| -> Result<String, DecodeError> {
            let s = string(fields.document(name, owner)?, owner)?;
            if matches!(name, "binding" | "language") {
                crate::workbench::contract::model_originals_identity(s)
                    .map_err(DecodeError::Value)?;
            }
            owner.bytes(s.len())?;
            Ok(s.to_owned())
        };
        let suite = copy("suite")?;
        let contract_version = copy("contractVersion")?;
        let binding = copy("binding")?;
        let language = copy("language")?;
        if suite != "workbench" || contract_version != VERSION {
            return Err(DecodeError::Shape("capabilities version/suite"));
        }
        let Document::Array(values) = fields.document("operations", owner)? else {
            return Err(DecodeError::Shape("capabilities operations"));
        };
        if !(1..=2).contains(&values.len()) {
            return Err(DecodeError::Shape("capabilities operation count"));
        }
        owner.slots(values.len())?;
        let mut operations = Vec::new();
        operations
            .try_reserve_exact(values.len())
            .map_err(|_| DecodeError::Allocation)?;
        for value in values {
            let role = Role::decode(value, owner)?;
            if operations.contains(&role) {
                return Err(DecodeError::Shape("duplicate capability"));
            }
            operations.push(role);
        }
        let Document::Array(formats) = fields.document("formats", owner)? else {
            return Err(DecodeError::Shape("formats"));
        };
        if formats.len() != 1 || string(&formats[0], owner)? != "json" {
            return Err(DecodeError::Shape("selected json format"));
        }
        Ok(Self {
            suite,
            contract_version,
            binding,
            language,
            operations,
            formats: ["json"],
        })
    }
}
struct DigestRef<'a>(&'a [u8; 32]);
impl Serialize for DigestRef<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut bytes = [0u8; 64];
        let hex = b"0123456789abcdef";
        for (i, b) in self.0.iter().enumerate() {
            bytes[2 * i] = hex[usize::from(b >> 4)];
            bytes[2 * i + 1] = hex[usize::from(b & 15)];
        }
        s.serialize_str(std::str::from_utf8(&bytes).map_err(serde::ser::Error::custom)?)
    }
}
#[derive(Serialize)]
struct OriginRef<'a> {
    packet: &'a str,
    sha256: DigestRef<'a>,
    id: &'a str,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ExecutionRef<'a> {
    origin: OriginRef<'a>,
    role: Role,
    run_index: usize,
}
impl<'a> ExecutionRef<'a> {
    pub(super) fn from_compiled(case: &'a CompiledExecution<'_, '_, '_, '_>) -> Self {
        let origin = case.origin();
        Self {
            origin: OriginRef {
                packet: origin.packet.key(),
                sha256: DigestRef(&origin.sha256.0),
                id: &origin.id.0,
            },
            role: match case {
                CompiledExecution::Current(value) => Role::of(value.source().paired().run()),
                CompiledExecution::Native(_) => Role::Server,
            },
            run_index: case.run_index(),
        }
    }
    pub(super) fn from_pair(pair: &'a PairedWorkflow<'a>) -> Self {
        let origin = &pair.scenario().origin;
        Self {
            origin: OriginRef {
                packet: origin.packet.key(),
                sha256: DigestRef(&origin.sha256.0),
                id: &origin.id.0,
            },
            role: Role::of(pair.run()),
            run_index: pair.run_index(),
        }
    }
}
pub(super) struct ExecutionKey {
    origin: input::PacketRef,
    role: Role,
    run_index: usize,
}
impl ExecutionKey {
    pub(super) fn matches_compiled(
        &self,
        case: &CompiledExecution<'_, '_, '_, '_>,
        owner: &mut Decoder,
    ) -> Result<bool, DecodeError> {
        let expected = ExecutionRef::from_compiled(case);
        owner.ready()?;
        owner.bytes(
            self.origin
                .packet
                .key()
                .len()
                .checked_add(expected.origin.packet.len())
                .ok_or(DecodeError::Limits)?,
        )?;
        owner.bytes(
            self.origin
                .id
                .0
                .len()
                .checked_add(expected.origin.id.len())
                .ok_or(DecodeError::Limits)?,
        )?;
        owner.bytes(64)?;
        Ok(self.origin.packet.key() == expected.origin.packet
            && self.origin.sha256.0 == *expected.origin.sha256.0
            && self.origin.id.0 == expected.origin.id
            && self.role == expected.role
            && self.run_index == expected.run_index)
    }
    fn decode(doc: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let fields = Fields::new(doc, &["origin", "role", "runIndex"], owner)?;
        Ok(Self {
            origin: fields.field("origin", owner)?,
            role: Role::decode(fields.document("role", owner)?, owner)?,
            run_index: usize::try_from(
                fields
                    .field::<Natural<0, { u64::MAX }>>("runIndex", owner)?
                    .0,
            )
            .map_err(|_| DecodeError::Shape("run index representation"))?,
        })
    }
    pub(super) fn matches(
        &self,
        pair: &PairedWorkflow<'_>,
        owner: &mut Decoder,
    ) -> Result<bool, DecodeError> {
        owner.ready()?;
        let actual = &pair.scenario().origin;
        owner.bytes(
            self.origin
                .packet
                .key()
                .len()
                .checked_add(actual.packet.key().len())
                .ok_or(DecodeError::Limits)?,
        )?;
        owner.bytes(
            self.origin
                .id
                .0
                .len()
                .checked_add(actual.id.0.len())
                .ok_or(DecodeError::Limits)?,
        )?;
        owner.bytes(64)?;
        Ok(self.origin.packet.key() == actual.packet.key()
            && self.origin.id.0 == actual.id.0
            && self.origin.sha256 == actual.sha256
            && self.role == Role::of(pair.run())
            && self.run_index == pair.run_index())
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub(super) struct FailureSummary {
    pub(super) phase: &'static str,
    pub(super) code: &'static str,
    pub(super) message: &'static str,
}
pub(super) struct SavedFailure {
    phase: String,
    code: String,
    message: String,
}
impl SavedFailure {
    pub(super) fn matches(&self, summary: FailureSummary) -> bool {
        self.phase == summary.phase && self.code == summary.code && self.message == summary.message
    }
}
#[derive(Serialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub(super) enum Verdict {
    Checked,
    Failed {
        #[serde(rename = "failureIndex")]
        failure_index: usize,
    },
}
#[derive(Serialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub(super) enum Evidence {
    ClientProcessMeasured {
        measurement: ClientProcessMeasurement,
        verdict: Verdict,
    },
    NativeMeasured {
        measurement: NativeMeasurement,
        verdict: Verdict,
    },
    Captured {
        exchange: WorkflowExchangeRecord,
        verdict: Verdict,
    },
    AttemptFailed {
        #[serde(rename = "failureIndex")]
        failure_index: usize,
    },
    NotAttempted {
        #[serde(rename = "priorFailureIndex")]
        prior_failure_index: usize,
    },
}
/// One immutable factual measurement, retained fallibly. The closed private
/// constructor keeps exactly one value. Indirection avoids reserving the large
/// native header for every not-attempted row; no unsafe/fallible-Box shim is
/// needed. The existing decoder charges the actual extra storage slot first.
pub(super) struct NativeMeasurement(Vec<NativeDeclarationObservation>);
/// Exactly one fallibly retained factual DATA value; no live issuer.
pub(super) struct ClientProcessMeasurement(Vec<InstalledClientMeasurements>);
impl ClientProcessMeasurement {
    pub(super) fn retain(
        value: InstalledClientMeasurements,
        owner: &mut Decoder,
    ) -> Result<Self, DecodeError> {
        owner.slots(1)?;
        let mut values = Vec::new();
        values
            .try_reserve_exact(1)
            .map_err(|_| DecodeError::Allocation)?;
        values.push(value);
        Ok(Self(values))
    }
    pub(super) fn value(&self) -> &InstalledClientMeasurements {
        &self.0[0]
    }
}
impl Serialize for ClientProcessMeasurement {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.value().serialize(serializer)
    }
}
impl NativeMeasurement {
    pub(super) fn retain(
        value: NativeDeclarationObservation,
        owner: &mut Decoder,
    ) -> Result<Self, DecodeError> {
        owner.slots(1)?;
        let mut values = Vec::new();
        values
            .try_reserve_exact(1)
            .map_err(|_| DecodeError::Allocation)?;
        values.push(value);
        Ok(Self(values))
    }
    pub(super) fn value(&self) -> &NativeDeclarationObservation {
        &self.0[0]
    }
}
impl Serialize for NativeMeasurement {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.value().serialize(serializer)
    }
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct RuntimeRecord<'a> {
    pub(super) case_id: &'a str,
    pub(super) execution: ExecutionRef<'a>,
    pub(super) evidence: Evidence,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct RuntimeReport<'a> {
    pub(super) format_version: &'static str,
    pub(super) suite: &'static str,
    pub(super) corpus_hash: &'a str,
    pub(super) capabilities: Option<Capabilities>,
    pub(super) records: Vec<RuntimeRecord<'a>>,
    pub(super) negotiation: Option<WorkflowExchangeRecord>,
    pub(super) errors: Vec<FailureSummary>,
    pub(super) qualified: bool,
}
pub(super) struct SavedRecord {
    pub(super) case_id: String,
    pub(super) execution: ExecutionKey,
    pub(super) evidence: Evidence,
}
pub(super) struct SavedReport {
    pub(super) corpus_hash: String,
    pub(super) capabilities: Option<Capabilities>,
    pub(super) records: Vec<SavedRecord>,
    pub(super) errors: Vec<SavedFailure>,
    pub(super) qualified: bool,
    pub(super) negotiation: Option<WorkflowExchangeRecord>,
}
pub(super) enum SavedError {
    Report(DecodeError),
    Negotiation(DecodeError),
}
impl From<DecodeError> for SavedError {
    fn from(error: DecodeError) -> Self {
        Self::Report(error)
    }
}

// Move already-budgeted Document strings into saved evidence without another
// Value deserialize or private-marker interpretation. This is wire extraction,
// never a second semantic observation checker.
fn take(
    fields: &mut Vec<(String, Document)>,
    name: &str,
    owner: &mut Decoder,
) -> Result<Document, DecodeError> {
    owner.ready()?;
    let mut found = None;
    for (i, (key, _)) in fields.iter().enumerate() {
        owner.bytes(key.len().saturating_add(name.len()))?;
        if key == name {
            found = Some(i);
            break;
        }
    }
    let i = found.ok_or(DecodeError::Shape("required report member"))?;
    Ok(fields.remove(i).1)
}
fn object(
    doc: Document,
    names: &[&str],
    owner: &mut Decoder,
) -> Result<Vec<(String, Document)>, DecodeError> {
    Fields::new(&doc, names, owner)?;
    let Document::Object(fields) = doc else {
        return Err(DecodeError::Shape("object"));
    };
    Ok(fields)
}
fn owned_text(doc: Document, owner: &mut Decoder) -> Result<String, DecodeError> {
    let Document::String(s) = doc else {
        return Err(DecodeError::Shape("string"));
    };
    owner.bytes(s.len())?;
    Ok(s)
}
fn index(doc: &Document, owner: &mut Decoder) -> Result<usize, DecodeError> {
    usize::try_from(Natural::<0, { u64::MAX }>::decode(doc, owner)?.0)
        .map_err(|_| DecodeError::Shape("report index"))
}
fn boolean(doc: Document) -> Result<bool, DecodeError> {
    let Document::Bool(v) = doc else {
        return Err(DecodeError::Shape("boolean"));
    };
    Ok(v)
}
fn array(doc: Document, maximum: usize, owner: &mut Decoder) -> Result<Vec<Document>, DecodeError> {
    let Document::Array(values) = doc else {
        return Err(DecodeError::Shape("array"));
    };
    if values.len() > maximum {
        return Err(DecodeError::Shape("report array bound"));
    }
    owner.slots(values.len())?;
    Ok(values)
}
fn evidence(doc: Document, owner: &mut Decoder) -> Result<Evidence, DecodeError> {
    let Document::Object(mut fields) = doc else {
        return Err(DecodeError::Shape("evidence"));
    };
    let kind = owned_text(take(&mut fields, "kind", owner)?, owner)?;
    match kind.as_str() {
        "client-process-measured" if fields.len() == 2 => {
            let measurement = InstalledClientMeasurements::decode(
                &take(&mut fields, "measurement", owner)?,
                owner,
            )?;
            let measurement = ClientProcessMeasurement::retain(measurement, owner)?;
            let verdict = verdict(take(&mut fields, "verdict", owner)?, owner)?;
            Ok(Evidence::ClientProcessMeasured {
                measurement,
                verdict,
            })
        }
        "native-measured" if fields.len() == 2 => {
            let measurement = NativeDeclarationObservation::decode(
                &take(&mut fields, "measurement", owner)?,
                owner,
            )?;
            let measurement = NativeMeasurement::retain(measurement, owner)?;
            let verdict = verdict(take(&mut fields, "verdict", owner)?, owner)?;
            Ok(Evidence::NativeMeasured {
                measurement,
                verdict,
            })
        }
        "captured" => {
            if fields.len() != 2 {
                return Err(DecodeError::Shape("captured fields"));
            }
            let exchange = exchange(take(&mut fields, "exchange", owner)?, owner)?;
            let verdict = verdict(take(&mut fields, "verdict", owner)?, owner)?;
            Ok(Evidence::Captured { exchange, verdict })
        }
        "attempt-failed" if fields.len() == 1 => Ok(Evidence::AttemptFailed {
            failure_index: index(&take(&mut fields, "failureIndex", owner)?, owner)?,
        }),
        "not-attempted" if fields.len() == 1 => Ok(Evidence::NotAttempted {
            prior_failure_index: index(&take(&mut fields, "priorFailureIndex", owner)?, owner)?,
        }),
        _ => Err(DecodeError::Shape("closed evidence")),
    }
}
fn verdict(doc: Document, owner: &mut Decoder) -> Result<Verdict, DecodeError> {
    let Document::Object(mut fields) = doc else {
        return Err(DecodeError::Shape("verdict"));
    };
    let kind = owned_text(take(&mut fields, "kind", owner)?, owner)?;
    match kind.as_str() {
        "checked" if fields.is_empty() => Ok(Verdict::Checked),
        "failed" if fields.len() == 1 => Ok(Verdict::Failed {
            failure_index: index(&take(&mut fields, "failureIndex", owner)?, owner)?,
        }),
        _ => Err(DecodeError::Shape("closed verdict")),
    }
}
fn exchange(doc: Document, owner: &mut Decoder) -> Result<WorkflowExchangeRecord, DecodeError> {
    let mut fields = object(doc, &["sentPayload", "receivedPayload"], owner)?;
    let sent = owned_text(take(&mut fields, "sentPayload", owner)?, owner)?;
    let received = owned_text(take(&mut fields, "receivedPayload", owner)?, owner)?;
    Ok(WorkflowExchangeRecord::from_decoded_payloads(
        sent, received,
    ))
}
pub(super) fn saved(doc: Document, owner: &mut Decoder) -> Result<SavedReport, SavedError> {
    let Document::Object(mut fields) = doc else {
        return Err(DecodeError::Shape("report object").into());
    };
    let negotiation = take(&mut fields, "negotiation", owner).map_err(SavedError::Negotiation)?;
    let negotiation = if matches!(negotiation, Document::Null) {
        None
    } else {
        Some(exchange(negotiation, owner).map_err(SavedError::Negotiation)?)
    };
    let mut fields = object(
        Document::Object(fields),
        &[
            "formatVersion",
            "suite",
            "corpusHash",
            "capabilities",
            "records",
            "errors",
            "qualified",
        ],
        owner,
    )?;
    if owned_text(take(&mut fields, "formatVersion", owner)?, owner)? != VERSION
        || owned_text(take(&mut fields, "suite", owner)?, owner)? != "workbench"
    {
        return Err(DecodeError::Shape("report header").into());
    }
    let corpus_hash = owned_text(take(&mut fields, "corpusHash", owner)?, owner)?;
    if !crate::kit::hash::is_sha256_hex(&corpus_hash) {
        return Err(DecodeError::Shape("corpus digest").into());
    }
    let caps = take(&mut fields, "capabilities", owner)?;
    let capabilities = if matches!(caps, Document::Null) {
        None
    } else {
        Some(Capabilities::decode(&caps, false, owner)?)
    };
    let values = array(take(&mut fields, "records", owner)?, 1024, owner)?;
    let mut records = Vec::new();
    records
        .try_reserve_exact(values.len())
        .map_err(|_| DecodeError::Allocation)?;
    for value in values {
        let mut row = object(value, &["caseId", "execution", "evidence"], owner)?;
        let case_id = owned_text(take(&mut row, "caseId", owner)?, owner)?;
        crate::workbench::contract::identity(&case_id, 128).map_err(DecodeError::Value)?;
        let execution = ExecutionKey::decode(&take(&mut row, "execution", owner)?, owner)?;
        let evidence = evidence(take(&mut row, "evidence", owner)?, owner)?;
        records.push(SavedRecord {
            case_id,
            execution,
            evidence,
        });
    }
    let values = array(take(&mut fields, "errors", owner)?, 3, owner)?;
    let mut errors = Vec::new();
    errors
        .try_reserve_exact(values.len())
        .map_err(|_| DecodeError::Allocation)?;
    for value in values {
        let mut row = object(value, &["phase", "code", "message"], owner)?;
        let phase = owned_text(take(&mut row, "phase", owner)?, owner)?;
        let code = owned_text(take(&mut row, "code", owner)?, owner)?;
        let message = owned_text(take(&mut row, "message", owner)?, owner)?;
        if message.chars().count() > 4096 {
            return Err(DecodeError::Shape("failure message bound").into());
        }
        errors.push(SavedFailure {
            phase,
            code,
            message,
        });
    }
    let qualified = boolean(take(&mut fields, "qualified", owner)?)?;
    Ok(SavedReport {
        corpus_hash,
        capabilities,
        records,
        errors,
        qualified,
        negotiation,
    })
}
