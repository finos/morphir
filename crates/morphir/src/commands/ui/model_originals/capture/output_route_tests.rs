//! Child of the actual capture module. Source-first controls, no test runner.
use super::*;
use crate::commands::ui::{
    model_originals::{
        HostModelCaptureCapacity,
        observation::{
            HostObservationLimits, HostSourceObservationScope, HostSourceSnapshot,
            WorkerObservationLimits,
        },
    },
    protocol::project_key,
    provider::{
        WorkspaceCapability,
        native::NativeWorkspaceProvider,
        originals::{
            OriginalsProvider, OriginalsSelection, OutputLocation, ResolvedProjectSource,
            SourceResolution,
        },
    },
};
use morphir_common::config::observation::{FileReadWitness, ReadLimits, ReadSnapshot};
use morphir_devkit::ConfigLoadOptions;
use std::path::PathBuf;

const PRIMARY: &[u8] = include_bytes!("cancellation_fixtures/primary.json");
const RECORD: &[u8] = include_bytes!("cancellation_fixtures/private-record.json");
const SENTINEL: &[u8] = include_bytes!("cancellation_fixtures/undeclared-sentinel.txt");

struct Fixture {
    _outer: tempfile::TempDir,
    root: PathBuf,
}
impl Fixture {
    fn new() -> Self {
        assert_eq!(PRIMARY.len(), 111);
        assert_eq!(RECORD.len(), 237);
        let outer = tempfile::tempdir().unwrap();
        let root = outer.path().join("workspace");
        std::fs::create_dir_all(root.join(".morphir/out/compile.dest")).unwrap();
        let root = std::fs::canonicalize(root).unwrap();
        for (path, bytes) in [
            (
                "morphir.toml",
                include_bytes!("cancellation_fixtures/project.toml").as_slice(),
            ),
            (".morphir/out/compile.json", RECORD),
            (".morphir/out/compile.dest/model.json", PRIMARY),
            (".morphir/out/compile.dest/secret", SENTINEL),
        ] {
            std::fs::write(root.join(path), bytes).unwrap();
        }
        Self {
            _outer: outer,
            root,
        }
    }
    fn held(&self) -> Dir {
        Dir::open_ambient_dir(&self.root, cap_std::ambient_authority()).unwrap()
    }
}
struct Witnesses {
    primary: FileReadWitness,
    record: FileReadWitness,
    sentinel: FileReadWitness,
}
struct ActualSource {
    scope: HostSourceObservationScope,
    resolved: ResolvedProjectSource,
    provider: OriginalsProvider,
    capacity: HostModelCaptureCapacity,
    files: Witnesses,
}
impl ActualSource {
    async fn new(fixture: &Fixture, output: &Path) -> Self {
        let scope = HostSourceObservationScope::bind_native_ui(
            &fixture.held(),
            &fixture.root,
            ReadLimits::new(1_000_000, 1_000_000, 16_777_216, 8).unwrap(),
            WorkerObservationLimits::new(8, 128).unwrap(),
            HostObservationLimits::new(128).unwrap(),
        )
        .unwrap();
        // Registration is metadata-use, before the first discovery/content call.
        let source = scope.source_scope();
        let held = fixture.held();
        let files = Witnesses {
            primary: source
                .register_file(&held, Path::new(".morphir/out/compile.dest/model.json"))
                .unwrap(),
            record: source
                .register_file(&held, Path::new(".morphir/out/compile.json"))
                .unwrap(),
            sentinel: source
                .register_file(&held, Path::new(".morphir/out/compile.dest/secret"))
                .unwrap(),
        };
        let native = NativeWorkspaceProvider::discover_observed(
            fixture.held(),
            &fixture.root,
            "actual-cancellation-source",
            ConfigLoadOptions::project_only(),
            &scope,
        )
        .unwrap()
        .with_out_overrides(crate::commands::out_context::OutOverrides {
            flag: Some(output.to_owned()),
            env: None,
        })
        .authorize_originals_lookup(cap_std::ambient_authority())
        .unwrap();
        let actual_source = native.initial_sources().pop().unwrap();
        let selection =
            OriginalsSelection::parse(&actual_source, &project_key(&actual_source, ".")).unwrap();
        let provider = OriginalsProvider::Native(Arc::new(native));
        let capacity = HostModelCaptureCapacity::default();
        let SourceResolution::Compiled(resolved) =
            provider.resolve(&selection, &capacity).await.unwrap()
        else {
            panic!("fixed actual native compiled source must resolve");
        };
        let SourceResolution::Compiled(current) =
            provider.resolve(&selection, &capacity).await.unwrap()
        else {
            panic!("actual same-provider revalidation must remain compiled");
        };
        assert!(resolved.same_authority(&current));
        drop(current);
        assert!(resolved.source_observation().is_some());
        assert!(matches!(
            resolved.content_binding().location(),
            OutputLocation::Workspace(_)
        ));
        assert_eq!(resolved.module().as_str(), "");
        let snapshot = scope.snapshot();
        assert_counts(snapshot.reads(), &files.record, 0, 0, 0);
        assert_counts(snapshot.reads(), &files.primary, 0, 0, 0);
        assert_counts(snapshot.reads(), &files.sentinel, 0, 0, 0);
        Self {
            scope,
            resolved,
            provider,
            capacity,
            files,
        }
    }
    fn capture(&self, control: &CaptureControl) -> Result<CaptureResult, CaptureError> {
        capture_resolved_accounted(
            &self.resolved,
            CaptureScope::Complete,
            control,
            Limits::default(),
            &mut PerCaptureOnly,
        )
    }
    fn seal(self) -> (HostSourceSnapshot, Witnesses) {
        let Self {
            scope,
            resolved,
            provider,
            capacity,
            files,
        } = self;
        drop(resolved);
        drop(provider);
        assert_eq!(capacity.usage().metadata_bytes(), 0);
        let snapshot = match scope.try_seal() {
            Ok(snapshot) => snapshot,
            Err(_) => panic!("all genuine source writer leases were dropped"),
        };
        // This component deliberately omits playground/server startup.
        // A final SDK-prefix seal is not whole-host completeness.
        assert!(snapshot.require_source_complete().is_err());
        snapshot.reads().require_complete().unwrap();
        (snapshot, files)
    }
}
fn assert_counts(
    reads: &ReadSnapshot,
    file: &FileReadWitness,
    attempts: u64,
    calls: u64,
    bytes: u64,
) {
    let counts = reads.counts_for(file).unwrap();
    assert_eq!(counts.content_attempts(), attempts);
    assert_eq!(counts.read_calls(), calls);
    assert_eq!(counts.returned_bytes(), bytes);
}
async fn assert_actual_override_preserves_ready(spelling: &str) {
    let fixture = Fixture::new();
    let output = fixture.root.join(spelling);
    let actual = ActualSource::new(&fixture, &output).await;
    // Preserve the independently selected business label. Only the internal
    // validated route may be reconstructed from its Normal components.
    assert_eq!(
        actual.resolved.content_binding().label().as_os_str(),
        output.as_os_str()
    );
    let CaptureResult::Ready(captured) = actual.capture(&CaptureControl::new()).unwrap() else {
        panic!("valid existing output override must preserve complete originals");
    };
    assert_eq!(captured.coverage(), CaptureScope::Complete);
    assert!(captured.companions().is_empty());
    assert_eq!(captured.record().byte_length(), 237);
    assert_eq!(
        captured.record().sha256().as_bytes().as_slice(),
        &Sha256::digest(RECORD)[..]
    );
    assert_eq!(captured.source_byte_length(), 111);
    assert_eq!(
        captured.file_bytes(&SourcePath::parse("model.json").unwrap()),
        Some(PRIMARY)
    );
    assert_eq!(captured.entries().len(), 1);
    drop(captured);
    let (snapshot, files) = actual.seal();
    assert_counts(snapshot.reads(), &files.record, 1, 2, 237);
    assert_counts(snapshot.reads(), &files.primary, 1, 2, 111);
    assert_counts(snapshot.reads(), &files.sentinel, 0, 0, 0);
}

#[tokio::test]
async fn actual_redundant_separator_override_keeps_selected_complete_originals() {
    assert_actual_override_preserves_ready(".morphir//out").await;
}

#[tokio::test]
async fn actual_dot_component_override_keeps_selected_complete_originals() {
    assert_actual_override_preserves_ready(".morphir/./out").await;
}
