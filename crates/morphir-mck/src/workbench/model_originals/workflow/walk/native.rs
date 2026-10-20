//! Original native source uses the SAME alias traversal/compiler meanings.
//! Provider/fixture/run links deliberately use their common descriptor names;
//! no configPolicy or ledger limit is inserted into the original DATA.
use super::super::native_original::*;
use super::*;

mod source {
    use super::super::super::native_original::{
        OriginalHostFixture as HostFixture, OriginalProvider as Provider, OriginalRun as Run,
        OriginalScenario as Scenario,
    };
    use super::*;
    const OPERAND: Operand = Operand::Input;
    record! { Scenario {
        limits: OriginalLimits => "limits",
        origin: input::PacketRef => "origin",
        runs: Items<Run, 1, 2> => "runs",
    } }
    tagged! { Run("role") {
        ModelOriginalsServer => "model-originals-server" {
            actions: Items<input::HostAction, 1, 8192> => "actions",
            fixture: HostFixture => "fixture",
        },
    } }
    record! { HostFixture {
        grants: Items<input::HostFixtureGrantsItem, 0, 128> => "grants",
        guests: Items<input::Guest, 0, 64> => "guests",
        providers: Items<Provider, 0, 64> => "providers",
        records: Items<input::HostFixtureRecordsItem, 0, 128> => "records",
        startup: input::HostFixtureStartup => "startup",
    } }
    tagged! { Provider("kind") {
        Native => "native" {
            alias: FixtureAlias => "alias",
            grant: FixtureAlias => "grant",
            locator: Text<0, 4096> => "locator",
            projects: Items<input::ProjectBinding, 1, 64> => "projects",
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
}
mod expected {
    use super::*;
    const OPERAND: Operand = Operand::Expected;
    plain!(
        OriginalExpectationKind,
        OriginalRole,
        OriginalDeclarationDeclared,
        OriginalAddressabilityNone
    );
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
}
