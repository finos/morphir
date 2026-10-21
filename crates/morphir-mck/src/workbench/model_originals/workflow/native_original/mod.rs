//! Typed source-vintage native originals. DATA is not a runtime capability.
//! Actual original bytes have eleven limits and no provider configPolicy.
//! The live runner still needs an actual native adapter before qualification.
use super::*;
pub(super) mod decode;
mod plan;
pub(super) use plan::{
    NativeComparisonPlan, ValidatedRunIndex, WitnessMetadata, compile_native_plan,
    first_witness_metadata,
};

pub(super) const MEASUREMENT_PROFILE: &str =
    "morphir/mck/model-originals-native-server-measurements";
pub(super) const MEASUREMENT_VERSION: &str = "0.1.0-draft.1";

tagged! { OriginalProvider("kind") {
    Native => "native" {
        alias: FixtureAlias => "alias",
        grant: FixtureAlias => "grant",
        locator: Text<0, 4096> => "locator",
        projects: Items<input::ProjectBinding, 1, 64> => "projects",
    },
} }
record! { OriginalHostFixture {
    grants: Items<input::HostFixtureGrantsItem, 0, 128> => "grants",
    guests: Items<input::Guest, 0, 64> => "guests",
    providers: Items<OriginalProvider, 0, 64> => "providers",
    records: Items<input::HostFixtureRecordsItem, 0, 128> => "records",
    startup: input::HostFixtureStartup => "startup",
} }
tagged! { OriginalRun("role") {
    ModelOriginalsServer => "model-originals-server" {
        actions: Items<input::HostAction, 1, 8192> => "actions",
        fixture: OriginalHostFixture => "fixture",
    },
} }
record! { OriginalLimits {
    actions: input::Count => "actions",
    corpus_bytes: input::LimitsCorpusBytes => "corpusBytes",
    events: input::LimitsEvents => "events",
    evidence_bytes: input::LimitsEvidenceBytes => "evidenceBytes",
    expanded_decoded_and_read_bytes: input::Count => "expandedDecodedAndReadBytes",
    expanded_wire_bytes: input::Count => "expandedWireBytes",
    input_bytes: input::LimitsInputBytes => "inputBytes",
    metadata_bytes: input::Count => "metadataBytes",
    observations_bytes: input::LimitsObservationsBytes => "observationsBytes",
    observer_byte_visits: input::Count => "observerByteVisits",
    report_bytes: input::LimitsReportBytes => "reportBytes",
} }
record! { OriginalScenario {
    limits: OriginalLimits => "limits",
    origin: input::PacketRef => "origin",
    runs: Items<OriginalRun, 1, 2> => "runs",
} }
literal! { OriginalExpectationKind => "concrete-native-declaration-workflow-expectation" }
literal! { pub OriginalRole => "model-originals-server" }
literal! { OriginalDeclarationDeclared => "declared" }
literal! { OriginalAddressabilityNone => "none" }
record! { OriginalSource {
    companion_roots: Items<domain::Root, 0, 63> => "companionRoots",
    primary_root: domain::Root => "primaryRoot",
    source_format_version: domain::SourceHeader => "sourceFormatVersion",
} }
tagged! { OriginalCapture("kind") {
    Ready => "ready" {
        coverage: domain::CaptureCoverage => "coverage",
        file_sha256: ContentSha256 => "fileSha256",
        inventory_request_id: U64Token => "inventoryRequestId",
        originals: Items<input::Entry, 1, 100064> => "originals",
        projection: domain::ExpectedProjection => "projection",
        read_request_id: U64Token => "readRequestId",
        release_request_id: U64Token => "releaseRequestId",
        request_id: U64Token => "requestId",
        source: OriginalSource => "source",
        source_byte_length: domain::Count => "sourceByteLength",
    },
} }
record! { OriginalFinal {
    active_workers: domain::Count => "activeWorkers",
    capture_addressability: OriginalAddressabilityNone => "captureAddressability",
    metadata_bytes: domain::Count => "metadataBytes",
    projection_bytes: domain::Count => "projectionBytes",
    record_bytes: domain::Count => "recordBytes",
    slots: domain::Count => "slots",
    source_bytes: domain::Count => "sourceBytes",
    worker_handles: domain::Count => "workerHandles",
} }
record! { OriginalSourceAccess {
    ambient_reads: domain::Count => "ambientReads",
    compile_calls: domain::Count => "compileCalls",
    undeclared_sentinel_reads: domain::Count => "undeclaredSentinelReads",
    v1_open_calls: domain::Count => "v1OpenCalls",
} }
record! { OriginalRawRecord {
    byte_length: domain::Count => "byteLength",
    sha256: ContentSha256 => "sha256",
} }
record! { OriginalDeclaration {
    companions: Items<domain::Root, 0, 63> => "companions",
    coverage: domain::CaptureCoverage => "coverage",
    declaration: OriginalDeclarationDeclared => "declaration",
} }
record! { NativeDeclarationExpectation {
    capture: OriginalCapture => "capture",
    final_state: OriginalFinal => "final",
    kind: OriginalExpectationKind => "kind",
    origin: input::PacketRef => "origin",
    original_expected: OriginalDeclaration => "originalExpected",
    raw_record: OriginalRawRecord => "rawRecord",
    role: OriginalRole => "role",
    source_access: OriginalSourceAccess => "sourceAccess",
} }

// Number DATA only, never an observed scope or a live completion.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ObservedCount(pub u64);
impl serde::Serialize for ObservedCount {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_str(&self.0)
    }
}
record! { pub ReadCounts {
    attempts: ObservedCount => "attempts",
    read_calls: ObservedCount => "readCalls",
    returned_bytes: ObservedCount => "returnedBytes",
} }
record! { pub ReadPrefix {
    total: ReadCounts => "total",
    workspace: ReadCounts => "workspace",
    ambient: ReadCounts => "ambient",
} }
words! { pub FileRole {
    CompileRecord => "compile-record",
    OriginalPrimary => "original-primary",
    UndeclaredSentinel => "undeclared-sentinel",
} }
record! { pub FileCounts {
    role: FileRole => "role",
    path: SourcePath => "relativePath",
    reads: ReadCounts => "counts",
} }
words! { pub SourceIncomplete {
    UnknownRoute => "unknown-route",
    ForeignOwner => "foreign-owner",
    Overflow => "overflow",
    Poisoned => "poisoned",
    Unsealed => "unsealed",
    MixedLegacy => "mixed-legacy",
    LateWitness => "late-witness",
} }
tagged! { pub SourceMeasurements("kind") {
    Unobserved => "unobserved" {},
    OpenPrefix => "open-prefix" { counts: ReadPrefix => "counts" },
    Partial => "partial" {
        reason: SourceIncomplete => "reason",
        counts: ReadPrefix => "counts",
    },
    SealedComplete => "sealed-complete" {
        counts: ReadPrefix => "counts",
        files: Items<FileCounts, 1, 4096> => "files",
    },
} }
record! { pub WorkerCounts {
    scheduled: ObservedCount => "scheduled",
    started: ObservedCount => "started",
    returned_ok: ObservedCount => "returnedOk",
    returned_error: ObservedCount => "returnedError",
    panicked: ObservedCount => "panicked",
    joined_ok: ObservedCount => "joinedOk",
    joined_panicked: ObservedCount => "joinedPanicked",
    joined_cancelled: ObservedCount => "joinedCancelled",
    owned_handles: ObservedCount => "ownedHandles",
    dropped_unjoined: ObservedCount => "droppedUnjoined",
} }
tagged! { pub WorkerMeasurements("kind") {
    Unobserved => "unobserved" {},
    Partial => "partial" { counts: WorkerCounts => "counts" },
    ObservedPrefix => "observed-prefix" { counts: WorkerCounts => "counts" },
    JoinedCleanup => "joined-cleanup" { counts: WorkerCounts => "counts" },
} }
tagged! { pub EntryCoverage("kind") {
    Unobserved => "unobserved" {},
    Partial => "partial" {},
    Complete => "complete" {
        compile_calls: ObservedCount => "compileCalls",
        legacy_model_open_calls: ObservedCount => "legacyModelOpenCalls",
    },
} }
record! { pub NativeCheckpoint {
    name: FixtureAlias => "name",
    connection: FixtureAlias => "connection",
    offer: observed::OfferEvidence => "offer",
    state: observed::CaptureState => "state",
    resources: observed::ResourceEvidence => "resources",
    source: SourceMeasurements => "source",
    workers: WorkerMeasurements => "workers",
    entries: EntryCoverage => "entries",
} }
literal! { pub DeclaredVersion => "0.1.0-draft.1" }
tagged! { pub FrozenDeclaration("kind") {
    Missing => "missing" {},
    Declared => "declared" {
        version: DeclaredVersion => "version",
        companions: Items<domain::Root, 0, 63> => "companions",
    },
} }
record! { pub FrozenPrivateRecord {
    bytes: input::Bytes => "bytes",
    byte_length: ObservedCount => "byteLength",
    sha256: ContentSha256 => "sha256",
    declaration: FrozenDeclaration => "declaration",
} }
#[derive(Debug)]
pub struct MeasurementVersion(semver::Version);
impl MeasurementVersion {
    pub fn current() -> Result<Self, DataValueError> {
        semver::Version::parse(MEASUREMENT_VERSION)
            .map(Self)
            .map_err(|_| DataValueError::Version)
    }
}
impl serde::Serialize for MeasurementVersion {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_str(&self.0)
    }
}
literal! { pub MeasurementProfile => "morphir/mck/model-originals-native-server-measurements" }
record! { pub ResolvedSelectionData {
    connection: FixtureAlias => "connection",
    provider: FixtureAlias => "provider",
    project: FixtureAlias => "project",
    registration: FixtureAlias => "registration",
    session_id: crate::workbench::model_originals::SessionId => "sessionId",
    source: crate::workbench::model_originals::SourceIdentity => "source",
    project_id: crate::workbench::model_originals::ProjectId => "projectId",
    capture: FixtureAlias => "capture",
    capture_id: crate::workbench::model_originals::CaptureId => "captureId",
} }
record! { pub NativeDeclarationObservation {
    profile: MeasurementProfile => "profile",
    contract_version: MeasurementVersion => "contractVersion",
    role: OriginalRole => "role",
    resolved_selection: ResolvedSelectionData => "resolvedSelection",
    transcript: observed::MeasuredTranscript => "transcript",
    captures: Items<observed::CapturedEvidence, 0, 8192> => "captures",
    private_record: FrozenPrivateRecord => "privateRecord",
    checkpoints: Items<NativeCheckpoint, 1, 8192> => "checkpoints",
    outcome: observed::ScenarioOutcome => "outcome",
    teardown: observed::HarnessTeardown => "teardown",
} }
