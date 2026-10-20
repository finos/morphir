//! Source-first real-parent component controls. Mount as capture's test child.
//! The configured engine issues the only NativeOriginalRun. These tests return
//! ObservationIncomplete, never authored successful NativeOriginalMeasurements.
use super::*;
use crate::commands::{
    out_context::OutOverrides,
    ui::{
        model_originals::{
            HostModelCaptureCapacity, ModelCaptureConnection, ModelCaptureUsage,
            PendingProviderCapture, ProviderCaptureError,
            lifecycle::{PrivateRecordObservationError, WorkerHooks},
            observation::{
                HostObservationLimits, HostSourceObservationScope, WorkerObservationLimits,
            },
        },
        native_startup::prepare_native_ui_observed,
        protocol::project_key,
        provider::{
            WorkspaceCapability, current::CurrentSessionCapabilities, originals::OriginalsSelection,
        },
    },
};
use morphir_common::config::observation::{FileReadWitness, ReadLimits};
use morphir_devkit::ConfigLoadOptions;
use morphir_mck::workbench::{
    RunConfiguration,
    model_originals::native::{
        NativeAdapterError, NativeOriginalAdapter, NativeOriginalMeasurements, NativeOriginalRun,
        PrivateRecordError, data,
    },
    run_configured_with_native_adapter,
};
use std::{path::PathBuf, sync::Mutex, time::Duration};

const PRIMARY: &[u8] = include_bytes!("private_record_fixtures/primary.json");
const RECORD: &[u8] = include_bytes!("private_record_fixtures/private-record.json");
const SENTINEL: &[u8] = include_bytes!("private_record_fixtures/undeclared-sentinel.txt");
const CASES: &[u8] = include_bytes!("private_record_fixtures/cases24.json");
const POLICY: &str = include_str!("private_record_fixtures/native-policy.json");
const WAIT: Duration = Duration::from_secs(5);
mod cleanup_tests;
mod socket_tests;

struct Fixture {
    outer: tempfile::TempDir,
    root: PathBuf,
}
impl Fixture {
    fn new(record: &[u8]) -> Self {
        assert_eq!(PRIMARY.len(), 111);
        assert_eq!(RECORD.len(), 237);
        let outer = tempfile::tempdir().unwrap();
        let root = outer.path().join("workspace");
        std::fs::create_dir_all(root.join(".morphir/out/compile.dest")).unwrap();
        // Provider discovery uses the canonical root. Preserve that genuine
        // authority before writes, including on macOS /var -> /private/var.
        let root = std::fs::canonicalize(root).unwrap();
        for (path, bytes) in [
            (
                "morphir.toml",
                include_bytes!("private_record_fixtures/project.toml").as_slice(),
            ),
            (".morphir/out/compile.json", record),
            (".morphir/out/compile.dest/model.json", PRIMARY),
            (".morphir/out/compile.dest/secret", SENTINEL),
        ] {
            std::fs::write(root.join(path), bytes).unwrap();
        }
        std::fs::create_dir(root.join("home")).unwrap();
        Self { outer, root }
    }
    fn held(&self) -> Dir {
        Dir::open_ambient_dir(&self.root, cap_std::ambient_authority()).unwrap()
    }
}
struct Actual {
    scope: HostSourceObservationScope,
    record: FileReadWitness,
    primary: FileReadWitness,
    sentinel: FileReadWitness,
    capacity: HostModelCaptureCapacity,
    connection: ModelCaptureConnection,
    observer: super::super::lifecycle::PrivateRecordObserver,
    current: CurrentSessionCapabilities,
    // Genuine providers remain alive for the same scope and Current registration.
    _startup: crate::commands::ui::native_startup::PreparedNativeUi,
}
impl Actual {
    fn new(fixture: &Fixture) -> Self {
        let scope = HostSourceObservationScope::bind_native_ui(
            &fixture.held(),
            &fixture.root,
            ReadLimits::new(1_000_000, 1_000_000, 134_217_728, 8).unwrap(),
            WorkerObservationLimits::new(8, 1024).unwrap(),
            HostObservationLimits::new(1024).unwrap(),
        )
        .unwrap();
        let held = fixture.held();
        let record = scope
            .source_scope()
            .register_file(&held, Path::new(".morphir/out/compile.json"))
            .unwrap();
        let primary = scope
            .source_scope()
            .register_file(&held, Path::new(".morphir/out/compile.dest/model.json"))
            .unwrap();
        let sentinel = scope
            .source_scope()
            .register_file(&held, Path::new(".morphir/out/compile.dest/secret"))
            .unwrap();
        let startup = prepare_native_ui_observed(
            fixture.held(),
            &fixture.root,
            "same-spelling-session",
            crate::home::MorphirHome::resolve_from(
                Some(fixture.root.join("home").as_os_str()),
                None,
            )
            .unwrap(),
            ConfigLoadOptions::default(),
            OutOverrides::default(),
            &scope,
        )
        .unwrap();
        let current = CurrentSessionCapabilities::new(startup.capabilities());
        current
            .register_originals(startup.originals_provider())
            .unwrap();
        let capacity = HostModelCaptureCapacity::default();
        let (connection, observer) =
            ModelCaptureConnection::new_record_observed(capacity.clone(), &scope);
        Self {
            scope,
            record,
            primary,
            sentinel,
            capacity,
            connection,
            observer,
            current,
            _startup: startup,
        }
    }
    fn start(&self, control: CaptureControl, hook: Arc<dyn WorkerHooks>) -> PendingProviderCapture {
        let source = self
            ._startup
            .workspace_provider()
            .initial_sources()
            .pop()
            .unwrap();
        let selection = OriginalsSelection::parse(&source, &project_key(&source, ".")).unwrap();
        let offer = self.current.select_originals(selection).unwrap();
        self.connection
            .start_offered_provider_with(offer, CaptureScope::Complete, control, hook)
            .unwrap()
    }
    async fn ready(&self) -> super::super::CaptureId {
        tokio::time::timeout(
            WAIT,
            self.start(CaptureControl::new(), Arc::new(Noop)).wait(),
        )
        .await
        .unwrap()
        .unwrap()
        .ready()
        .unwrap()
    }
    fn assert_file_counts(&self, record_length: u64, record_calls: u64) {
        let snapshot = self.scope.snapshot();
        for (witness, attempts, calls, bytes) in [
            (&self.record, 1, record_calls, record_length),
            (&self.primary, 1, 2, 111),
            (&self.sentinel, 0, 0, 0),
        ] {
            let counts = snapshot.reads().counts_for(witness).unwrap();
            assert_eq!(counts.content_attempts(), attempts);
            assert_eq!(counts.read_calls(), calls);
            assert_eq!(counts.returned_bytes(), bytes);
        }
    }
    fn assert_raw(&self, length: usize, capacity: usize) {
        let snapshot = self.observer.snapshot();
        assert_eq!(snapshot.retained_bytes(), length);
        assert_eq!(snapshot.retained_capacity(), capacity);
    }
    fn assert_zero(&self) {
        self.assert_raw(0, 0);
        assert_eq!(self.capacity.usage(), ModelCaptureUsage::default());
        self.scope
            .snapshot()
            .workers()
            .require_joined_cleanup()
            .unwrap();
    }
}
struct Noop;
impl WorkerHooks for Noop {}
struct PanicAfterCapture;
impl WorkerHooks for PanicAfterCapture {
    fn before_source_header(&self) {
        panic!("independent actual worker panic after capture");
    }
}
struct CancelAfterCapture(CaptureControl);
impl WorkerHooks for CancelAfterCapture {
    fn before_source_header(&self) {
        self.0.cancel();
    }
}
struct HoldBody {
    entered: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    release: Mutex<std::sync::mpsc::Receiver<()>>,
}
impl WorkerHooks for HoldBody {
    fn before_capture(&self) {
        self.entered
            .lock()
            .unwrap()
            .take()
            .unwrap()
            .send(())
            .unwrap();
        self.release.lock().unwrap().recv_timeout(WAIT).unwrap();
    }
}
struct Gate {
    hook: Arc<HoldBody>,
    entered: Option<tokio::sync::oneshot::Receiver<()>>,
    release: Option<std::sync::mpsc::Sender<()>>,
}
impl Gate {
    fn new() -> Self {
        let (send, entered) = tokio::sync::oneshot::channel();
        let (release, recv) = std::sync::mpsc::channel();
        Self {
            hook: Arc::new(HoldBody {
                entered: Mutex::new(Some(send)),
                release: Mutex::new(recv),
            }),
            entered: Some(entered),
            release: Some(release),
        }
    }
    async fn entered(&mut self) {
        tokio::time::timeout(WAIT, self.entered.take().unwrap())
            .await
            .unwrap()
            .unwrap();
    }
    fn release(&mut self) {
        if let Some(send) = self.release.take() {
            let _ = send.send(());
        }
    }
}
impl Drop for Gate {
    fn drop(&mut self) {
        self.release();
    }
}
async fn finished(pending: &PendingProviderCapture) {
    tokio::time::timeout(WAIT, async {
        while !pending.is_finished() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
}
async fn zero_after_exit(actual: &Actual) {
    tokio::time::timeout(WAIT, async {
        while actual.capacity.usage() != ModelCaptureUsage::default() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
}
fn utf8(data: &data::Bytes) -> &str {
    let data::Bytes::Utf8 { text } = data else {
        panic!("same validated UTF8 representation required");
    };
    text.as_str()
}

#[derive(Clone, Copy)]
enum Scenario {
    Socket,
    HeldJoin,
    CapacityBeforeTake,
    Adopt,
    SpareCapacity,
    Foreign,
    Abandoned,
    EarlyError,
    Cancel,
    Panic,
    DroppedWaiter,
    RetireSlot,
    RetireCheckedOut,
    Unsupported,
    PrivateOnly,
}
struct Adapter {
    scenario: Scenario,
    called: bool,
}
impl NativeOriginalAdapter for Adapter {
    fn observe(
        &mut self,
        mut run: NativeOriginalRun<'_>,
    ) -> Result<NativeOriginalMeasurements, NativeAdapterError> {
        assert!(!self.called);
        self.called = true;
        assert_eq!(
            run.source().case_id(),
            "explicit-empty-companion-declaration-is-complete"
        );
        assert_eq!(run.actions().len(), 10);
        tokio::runtime::Handle::current().block_on(component(self.scenario, &mut run));
        // These are ownership components, not a complete measured host workflow.
        Err(NativeAdapterError::ObservationIncomplete)
    }
}
async fn exercise(scenario: Scenario, retained_bytes: u64) {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut policy: serde_json::Value = serde_json::from_str(POLICY).unwrap();
    policy["privateRecord"]["retainedBytes"] = retained_bytes.into();
    // This scenario must reach SAME Text validator after both actual span visits.
    if matches!(scenario, Scenario::Unsupported) {
        policy["checker"]["comparison"]["comparisonBytes"] = 2_097_154u64.into();
    }
    let configuration = RunConfiguration::from_json(&policy.to_string()).unwrap();
    assert_eq!(
        configuration
            .private_record_limits()
            .unwrap()
            .retained_bytes(),
        retained_bytes
    );
    let mut adapter = Adapter {
        scenario,
        called: false,
    };
    let report = tokio::task::block_in_place(|| {
        run_configured_with_native_adapter(kit.path(), &configuration, &mut adapter)
    })
    .unwrap();
    assert!(
        adapter.called,
        "only the real engine can issue this invocation"
    );
    assert!(!report.qualified());
    assert!(
        !report.to_json().contains("\"native-measured\""),
        "no successful measurement may be invented for a component"
    );
}

async fn component(scenario: Scenario, run: &mut NativeOriginalRun<'_>) {
    let record = match scenario {
        Scenario::SpareCapacity => {
            include_bytes!("private_record_fixtures/spare-record.json").as_slice()
        }
        Scenario::Unsupported => {
            include_bytes!("private_record_fixtures/unsupported-record.json").as_slice()
        }
        Scenario::EarlyError => b"not valid JSON".as_slice(),
        _ => RECORD,
    };
    let fixture = Fixture::new(record);
    let actual = Actual::new(&fixture);
    match scenario {
        Scenario::Socket => socket_tests::component(&actual, run).await,
        Scenario::HeldJoin => {
            let pending = actual.start(CaptureControl::new(), Arc::new(Noop));
            let attempt = pending.worker_observation();
            finished(&pending).await;
            let work = attempt.snapshot();
            assert_eq!(work.returned_ok(), 1);
            assert_eq!(work.owned_handles(), 1);
            assert_eq!(work.joined_ok(), 0);
            let raw = actual.observer.snapshot();
            assert_eq!(raw.retained_bytes(), 237);
            assert!(raw.retained_capacity() >= 237);
            assert_eq!(actual.capacity.usage().active_workers(), 1);
            let id = pending.wait().await.unwrap().ready().unwrap();
            let work = attempt.snapshot();
            assert_eq!(work.owned_handles(), 0);
            assert_eq!(work.joined_ok(), 1);
            work.require_joined_cleanup().unwrap();
            assert_eq!(
                actual.capacity.usage().active_workers(),
                1,
                "same raw WorkPermit still retained after real join"
            );
            actual.connection.release(&id).unwrap();
            actual.assert_zero();
        }
        Scenario::EarlyError => {
            let result = tokio::time::timeout(
                WAIT,
                actual.start(CaptureControl::new(), Arc::new(Noop)).wait(),
            )
            .await
            .unwrap();
            assert!(matches!(
                result,
                Err(ProviderCaptureError::Capture(CaptureError::InvalidRecord))
            ));
            actual.assert_zero();
        }
        Scenario::Cancel => {
            let control = CaptureControl::new();
            let pending = actual.start(control.clone(), Arc::new(CancelAfterCapture(control)));
            assert!(matches!(
                tokio::time::timeout(WAIT, pending.wait()).await.unwrap(),
                Err(ProviderCaptureError::Capture(CaptureError::Timeout))
            ));
            actual.assert_file_counts(237, 2);
            assert!(
                actual
                    .connection
                    .drain_cleanup(tokio::time::Instant::now() + WAIT)
                    .await
                    .is_ok(),
                "actual awaited cancellation must drain its owned handle before final joined proof"
            );
            actual.assert_zero();
        }
        Scenario::Panic => {
            let pending = actual.start(CaptureControl::new(), Arc::new(PanicAfterCapture));
            let attempt = pending.worker_observation();
            assert!(
                tokio::time::timeout(WAIT, pending.wait())
                    .await
                    .unwrap()
                    .is_err()
            );
            let work = attempt.snapshot();
            assert_eq!(work.panicked(), 1);
            assert_eq!(work.joined_panicked(), 1);
            assert_eq!(work.joined_ok(), 0);
            actual.assert_zero();
        }
        Scenario::DroppedWaiter => {
            let mut gate = Gate::new();
            let pending = actual.start(CaptureControl::new(), gate.hook.clone());
            let attempt = pending.worker_observation();
            gate.entered().await;
            drop(pending);
            actual.connection.close();
            actual.assert_raw(0, 0);
            assert_eq!(
                actual.capacity.usage().active_workers(),
                1,
                "actual held body still owns its permit"
            );
            assert_eq!(attempt.snapshot().dropped_unjoined(), 1);
            assert!(attempt.snapshot().require_joined_cleanup().is_err());
            gate.release();
            zero_after_exit(&actual).await;
            assert!(
                attempt.snapshot().require_joined_cleanup().is_err(),
                "actual body exit is not resolved join"
            );
        }
        _ => {
            let id = actual.ready().await;
            let (pointer, length, capacity) = actual
                .observer
                .with_ready_record(&id, |raw| (raw.as_ptr(), raw.len(), raw.capacity()))
                .unwrap();
            assert_eq!(length, record.len());
            actual.assert_raw(length, capacity);
            assert_eq!(actual.capacity.usage().active_workers(), 1);
            actual.assert_file_counts(
                length as u64,
                (length / 65536 + 1) as u64 + u64::from(length % 65536 != 0),
            );
            match scenario {
                Scenario::CapacityBeforeTake | Scenario::SpareCapacity => {
                    if matches!(scenario, Scenario::SpareCapacity) {
                        assert_eq!(length, 65_537);
                        assert!(
                            capacity > length,
                            "actual bounded read loop must calibrate a spare-capacity allocation"
                        );
                    }
                    let first = actual
                        .observer
                        .with_ready_record(&id, |raw| {
                            match run.prepare_private_record_adoption(raw) {
                                Err(error) => error,
                                Ok(_) => panic!(
                                    "actual capacity must be reserved before taking host bytes"
                                ),
                            }
                        })
                        .unwrap();
                    let expected_limit = if matches!(scenario, Scenario::SpareCapacity) {
                        65_537
                    } else {
                        236
                    };
                    assert!(
                        matches!(first, PrivateRecordError::Capacity { limit, used: 0, requested } if *limit == expected_limit && *requested == capacity as u64)
                    );
                    actual
                        .observer
                        .with_ready_record(&id, |raw| {
                            assert_eq!(
                                (raw.as_ptr(), raw.len(), raw.capacity()),
                                (pointer, length, capacity)
                            );
                        })
                        .unwrap();
                    actual.assert_raw(length, capacity);
                    assert_eq!(actual.capacity.usage().active_workers(), 1);
                    assert_eq!(run.private_record_retention_usage().reserved_bytes(), 0);
                    actual.connection.release(&id).unwrap();
                    actual.assert_zero();
                }
                Scenario::Adopt => {
                    let ticket = actual
                        .observer
                        .with_ready_record(&id, |raw| run.prepare_private_record_adoption(raw))
                        .unwrap()
                        .unwrap();
                    assert_eq!(ticket.usage().reserved_bytes(), capacity as u64);
                    actual.assert_raw(length, capacity);
                    let lease = actual.observer.take(&id).unwrap();
                    assert_eq!(
                        (
                            lease.buffer().as_ptr(),
                            lease.buffer().len(),
                            lease.buffer().capacity()
                        ),
                        (pointer, length, capacity)
                    );
                    actual.assert_raw(length, capacity);
                    let data = lease.adopt(ticket).unwrap();
                    assert_eq!(utf8(&data).as_bytes(), RECORD);
                    assert_eq!(
                        utf8(&data).as_ptr(),
                        pointer,
                        "same Vec allocation must be moved through String/Text"
                    );
                    actual.assert_raw(0, 0);
                    assert_eq!(actual.capacity.usage().active_workers(), 0);
                    assert_eq!(
                        run.private_record_retention_usage().reserved_bytes(),
                        capacity as u64
                    );
                    drop(data);
                    assert_eq!(
                        run.private_record_retention_usage().reserved_bytes(),
                        capacity as u64,
                        "cumulative receiver work is not refunded"
                    );
                    actual.connection.release(&id).unwrap();
                    actual.assert_zero();
                }
                Scenario::Foreign => {
                    let other_fixture = Fixture::new(RECORD);
                    let other = Actual::new(&other_fixture);
                    let other_id = other.ready().await;
                    assert!(matches!(
                        actual.observer.take(&other_id),
                        Err(PrivateRecordObservationError::NotOwned)
                    ));
                    actual.assert_raw(length, capacity);
                    let ticket = actual
                        .observer
                        .with_ready_record(&id, |raw| run.prepare_private_record_adoption(raw))
                        .unwrap()
                        .unwrap();
                    let foreign = other.observer.take(&other_id).unwrap();
                    assert_eq!(foreign.buffer().len(), length);
                    assert_eq!(foreign.buffer().capacity(), capacity);
                    assert_ne!(foreign.buffer().as_ptr(), pointer);
                    assert!(matches!(
                        foreign.adopt(ticket),
                        Err(PrivateRecordError::AllocationMismatch)
                    ));
                    other.assert_raw(0, 0);
                    assert_eq!(
                        other.capacity.usage().active_workers(),
                        0,
                        "foreign consumed bytes are dropped before its permit"
                    );
                    actual.assert_raw(length, capacity);
                    actual.connection.release(&id).unwrap();
                    other.connection.release(&other_id).unwrap();
                    actual.assert_zero();
                    other.assert_zero();
                }
                Scenario::Abandoned => {
                    let ticket = actual
                        .observer
                        .with_ready_record(&id, |raw| run.prepare_private_record_adoption(raw))
                        .unwrap()
                        .unwrap();
                    drop(ticket);
                    assert_eq!(
                        run.private_record_retention_usage().reserved_bytes(),
                        capacity as u64
                    );
                    let error = actual
                        .observer
                        .with_ready_record(&id, |raw| {
                            match run.prepare_private_record_adoption(raw) {
                                Err(error) => error,
                                Ok(_) => panic!("abandoned ticket must latch the first error"),
                            }
                        })
                        .unwrap();
                    assert!(matches!(error, PrivateRecordError::Abandoned));
                    actual.assert_raw(length, capacity);
                    actual.connection.release(&id).unwrap();
                    actual.assert_zero();
                }
                Scenario::RetireSlot => {
                    actual.connection.close();
                    actual.assert_zero();
                    assert!(actual.observer.take(&id).is_err());
                }
                Scenario::RetireCheckedOut => {
                    let lease = actual.observer.take(&id).unwrap();
                    actual.connection.close();
                    actual.assert_raw(length, capacity);
                    assert_eq!(
                        actual.capacity.usage().active_workers(),
                        1,
                        "closed connection cannot free an actual held lease"
                    );
                    drop(lease);
                    actual.assert_zero();
                }
                Scenario::Unsupported => {
                    assert_eq!(length, 1_048_577);
                    let ticket = actual
                        .observer
                        .with_ready_record(&id, |raw| run.prepare_private_record_adoption(raw))
                        .unwrap()
                        .unwrap();
                    let lease = actual.observer.take(&id).unwrap();
                    assert!(matches!(
                        lease.adopt(ticket),
                        Err(PrivateRecordError::UnsupportedRepresentation)
                    ));
                    actual.assert_raw(0, 0);
                    assert_eq!(actual.capacity.usage().active_workers(), 0);
                    assert_eq!(
                        run.private_record_retention_usage().reserved_bytes(),
                        capacity as u64
                    );
                    actual.connection.release(&id).unwrap();
                    actual.assert_zero();
                }
                Scenario::PrivateOnly => {
                    actual
                        .connection
                        .inspect_owned(&id, |sources| {
                            assert_eq!(sources.record().byte_length(), 237);
                            assert_eq!(sources.entries().len(), 1);
                            assert_eq!(
                                sources.file_bytes(&SourcePath::parse("model.json").unwrap()),
                                Some(PRIMARY)
                            );
                            assert!(
                                sources
                                    .file_bytes(&SourcePath::parse("compile.json").unwrap())
                                    .is_none()
                            );
                            assert!(
                                sources
                                    .file_bytes(&SourcePath::parse("secret").unwrap())
                                    .is_none()
                            );
                        })
                        .unwrap();
                    actual
                        .observer
                        .with_ready_record(&id, |raw| assert_eq!(raw.as_slice(), RECORD))
                        .unwrap();
                    actual.connection.release(&id).unwrap();
                    actual.assert_zero();
                }
                _ => unreachable!(),
            }
        }
    }
    // A component never certifies the unbound host's final source coverage.
    assert!(actual.scope.snapshot().require_source_complete().is_err());
    drop(actual);
    drop(fixture.outer);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r01_real_authenticated_socket_issues_host_bound_raw_observer_and_adopts() {
    exercise(Scenario::Socket, 67_108_864).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r02_completed_actual_join_handle_and_raw_credit_remain_distinct() {
    exercise(Scenario::HeldJoin, 67_108_864).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r03_receiver_capacity_refusal_precedes_taking_actual_host_buffer() {
    exercise(Scenario::CapacityBeforeTake, 236).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r04_actual_record_moves_without_copy_after_capacity_precharge() {
    exercise(Scenario::Adopt, 67_108_864).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r04_actual_spare_capacity_is_charged_instead_of_record_length() {
    exercise(Scenario::SpareCapacity, 65_537).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r05_foreign_same_spelling_connection_and_allocation_are_denied() {
    exercise(Scenario::Foreign, 67_108_864).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r05_abandoned_ticket_keeps_cumulative_charge_and_host_buffer() {
    exercise(Scenario::Abandoned, 67_108_864).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r06_actual_early_error_has_no_adoptable_record() {
    exercise(Scenario::EarlyError, 67_108_864).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r06_actual_cancel_after_record_read_drops_raw_before_permit() {
    exercise(Scenario::Cancel, 67_108_864).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r06_actual_worker_panic_drops_record_before_permit_release() {
    exercise(Scenario::Panic, 67_108_864).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r07_dropped_waiter_does_not_release_actual_held_worker() {
    exercise(Scenario::DroppedWaiter, 67_108_864).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r07_connection_close_retires_unconsumed_private_record() {
    exercise(Scenario::RetireSlot, 67_108_864).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r07_checked_out_actual_lease_remains_measured_until_drop() {
    exercise(Scenario::RetireCheckedOut, 67_108_864).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r08_actual_business_record_above_text_character_limit_refuses_adoption() {
    exercise(Scenario::Unsupported, 67_108_864).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn r09_retained_private_record_is_not_an_inventory_download() {
    exercise(Scenario::PrivateOnly, 67_108_864).await;
}
