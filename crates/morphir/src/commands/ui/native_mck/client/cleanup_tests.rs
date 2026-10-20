//! Source-first RunningHost controls. No fabricated measurement or join event.
//! Install as native_mck::client::cleanup_tests after guarded root review.
use super::*;
use crate::commands::{
    out_context::OutOverrides,
    ui::{
        model_originals::{
            ModelCaptureUsage,
            observation::{
                HostObservationLimits, HostSourceObservationScope, WorkerObservationLimits,
            },
        },
        native_startup::{PreparedNativeUi, prepare_native_ui_observed},
        protocol::project_key,
        provider::WorkspaceCapability as _,
    },
};
use base64::Engine as _;
use cap_std::fs::Dir;
use morphir_common::config::observation::{FileReadWitness, ReadLimits};
use morphir_devkit::ConfigLoadOptions;
use std::{path::Path, time::Duration};

const PRIMARY: &[u8] =
    include_bytes!("../../model_originals/capture/private_record_fixtures/primary.json");
const RECORD: &[u8] =
    include_bytes!("../../model_originals/capture/private_record_fixtures/private-record.json");
const SENTINEL: &[u8] =
    include_bytes!("../../model_originals/capture/private_record_fixtures/undeclared-sentinel.txt");
const CONFIG: &[u8] =
    include_bytes!("../../model_originals/capture/private_record_fixtures/project.toml");
const WAIT: Duration = Duration::from_secs(5);

mod main_shutdown_tests;
mod ordinary_host_tests;
#[cfg(test)]
mod socket_task_tests;

struct Fixture {
    _temporary: tempfile::TempDir,
    root: std::path::PathBuf,
}
impl Fixture {
    fn new() -> Self {
        assert_eq!(PRIMARY.len(), 111);
        assert_eq!(RECORD.len(), 237);
        let temporary = tempfile::tempdir().unwrap();
        let root = temporary.path().join("workspace");
        std::fs::create_dir_all(root.join(".morphir/out/compile.dest")).unwrap();
        std::fs::create_dir(root.join("home")).unwrap();
        let root = root.canonicalize().unwrap();
        for (relative, bytes) in [
            ("morphir.toml", CONFIG),
            (".morphir/out/compile.json", RECORD),
            (".morphir/out/compile.dest/model.json", PRIMARY),
            (".morphir/out/compile.dest/secret", SENTINEL),
        ] {
            std::fs::write(root.join(relative), bytes).unwrap();
        }
        Self {
            _temporary: temporary,
            root,
        }
    }
    fn held(&self) -> Dir {
        Dir::open_ambient_dir(&self.root, cap_std::ambient_authority()).unwrap()
    }
    fn compile_lock(&self) -> std::fs::File {
        let lock = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(self.root.join(".morphir/out/compile.lock"))
            .unwrap();
        fs2::FileExt::lock_exclusive(&lock).unwrap();
        lock
    }
}
struct Actual {
    host: RunningHost,
    prepared: PreparedNativeUi,
    scope: HostSourceObservationScope,
    usage: crate::commands::ui::model_originals::ModelCaptureUsageObserver,
    record: FileReadWitness,
    primary: FileReadWitness,
    sentinel: FileReadWitness,
    source: Value,
    project: String,
    deadline: Deadline,
}
impl Actual {
    async fn start(fixture: &Fixture) -> Self {
        Self::start_with_capture_hook(fixture, None).await
    }
    async fn start_with_capture_hook(
        fixture: &Fixture,
        hook: Option<crate::commands::ui::model_originals::CaptureWorkerTestHook>,
    ) -> Self {
        let scope = HostSourceObservationScope::bind_native_ui(
            &fixture.held(),
            &fixture.root,
            ReadLimits::new(1_000_000, 1_000_000, 134_217_728, 8).unwrap(),
            WorkerObservationLimits::new(8, 1024).unwrap(),
            HostObservationLimits::new(1024).unwrap(),
        )
        .unwrap();
        let held = fixture.held();
        let register = |relative: &str| {
            scope
                .source_scope()
                .register_file(&held, Path::new(relative))
                .unwrap()
        };
        let record = register(".morphir/out/compile.json");
        let primary = register(".morphir/out/compile.dest/model.json");
        let sentinel = register(".morphir/out/compile.dest/secret");
        // This component fixture explicitly supplies its caller home. The
        // production producer still resolves the genuine process home.
        let prepared = prepare_native_ui_observed(
            fixture.held(),
            &fixture.root,
            "running-host-cleanup",
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
        let selected = prepared
            .workspace_provider()
            .initial_sources()
            .pop()
            .unwrap();
        let project = project_key(&selected, ".");
        let source = serde_json::to_value(selected).unwrap();
        let (host, _records) = match hook {
            None => {
                BoundUiHost::bind_record_observed(
                    "running-host-cleanup".into(),
                    prepared.capabilities(),
                    Some(prepared.originals_provider()),
                    &scope,
                )
                .await
            }
            Some(hook) => {
                BoundUiHost::bind_record_observed_with_capture_hook(
                    "running-host-cleanup".into(),
                    prepared.capabilities(),
                    Some(prepared.originals_provider()),
                    &scope,
                    hook,
                )
                .await
            }
        }
        .unwrap();
        let usage = host.model_originals_observer();
        let deadline = Deadline::new(
            Limits {
                request_timeout: WAIT,
                session_timeout: Duration::from_secs(20),
                ..Limits::DEFAULT
            },
            Arc::new(AtomicBool::new(false)),
        )
        .unwrap();
        let mut host = RunningHost::start(host).unwrap();
        host.connect(&deadline).await.unwrap();
        let (initialized, _) = host
            .request(
                &deadline,
                1,
                "morphir.session.initialize",
                json!({"protocolVersion":1,"sessionId":"running-host-cleanup"}),
            )
            .await
            .unwrap();
        assert_eq!(initialized["result"]["protocolVersion"], 1);
        let (opened, _) = host
            .request(
                &deadline,
                2,
                "morphir.workspace.open",
                json!({"source":source}),
            )
            .await
            .unwrap();
        assert!(
            opened["result"]["snapshot"]["projects"]
                .as_array()
                .unwrap()
                .iter()
                .any(|p| p["id"] == project)
        );
        Self {
            host,
            prepared,
            scope,
            usage,
            record,
            primary,
            sentinel,
            source,
            project,
            deadline,
        }
    }
    fn capture_params(&self) -> Value {
        json!({"contractVersion":"0.1.0-draft.1","source":{"providerId":self.source["providerId"],"locator":self.source["locator"]},"projectId":self.project,"scope":"complete","semantic":"none"})
    }
    async fn begin_held_capture(&mut self) {
        let frame = json!({"jsonrpc":"2.0","id":3,"method":"morphir.model-originals.capture","params":self.capture_params()}).to_string();
        self.host
            .socket
            .as_mut()
            .unwrap()
            .send(Message::Text(frame.into()))
            .await
            .unwrap();
        tokio::time::timeout(WAIT, async {
            while self.scope.snapshot().workers().started() != 1 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        assert_eq!(self.usage.usage().active_workers(), 1);
        assert_eq!(
            self.scope
                .snapshot()
                .reads()
                .counts_for(&self.record)
                .unwrap()
                .content_attempts(),
            0
        );
    }
}

struct HeldCapture {
    hook: crate::commands::ui::model_originals::CaptureWorkerTestHook,
    entered: Option<tokio::sync::oneshot::Receiver<()>>,
    release: Option<std::sync::mpsc::Sender<()>>,
}
impl HeldCapture {
    fn new() -> Self {
        let (send, entered) = tokio::sync::oneshot::channel();
        let (release, receive) = std::sync::mpsc::channel();
        let send = std::sync::Mutex::new(Some(send));
        let receive = std::sync::Mutex::new(receive);
        let hook =
            crate::commands::ui::model_originals::CaptureWorkerTestHook::new(Arc::new(move || {
                send.lock().unwrap().take().unwrap().send(()).unwrap();
                receive.lock().unwrap().recv_timeout(WAIT).unwrap();
            }));
        Self {
            hook,
            entered: Some(entered),
            release: Some(release),
        }
    }
    async fn entered(&mut self, scope: &HostSourceObservationScope) {
        tokio::time::timeout(WAIT, self.entered.take().unwrap())
            .await
            .unwrap()
            .unwrap();
        // Started can precede genuine TrackedJoin installation. Require the
        // actual owned-handle witness too before exercising stop or cancellation.
        tokio::time::timeout(WAIT, async {
            while scope.snapshot().workers().owned_handles() != 1 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
    }
    fn release(&mut self) {
        self.release.take().unwrap().send(()).unwrap();
    }
}
impl Drop for HeldCapture {
    fn drop(&mut self) {
        // A failing assertion must release the genuine blocking body too.
        if let Some(release) = self.release.take() {
            let _ = release.send(());
        }
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn normal_authenticated_capture_release_stop_joins_before_source_seal() {
    let fixture = Fixture::new();
    let mut actual = Actual::start(&fixture).await;
    let parameters = actual.capture_params();
    let (ready, _) = actual
        .host
        .request(
            &actual.deadline,
            3,
            "morphir.model-originals.capture",
            parameters,
        )
        .await
        .unwrap();
    assert_eq!(ready["result"]["status"], "ready");
    let id = ready["result"]["captureId"].as_str().unwrap();
    let (inventory, _) = actual.host.request(&actual.deadline, 4, "morphir.model-originals.inventory", json!({"contractVersion":"0.1.0-draft.1","captureId":id,"startIndex":0,"maxEntries":256})).await.unwrap();
    let entries = inventory["result"]["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0]["path"], "model.json");
    let (bytes, _) = actual.host.request(&actual.deadline, 5, "morphir.model-originals.read", json!({"contractVersion":"0.1.0-draft.1","captureId":id,"target":{"kind":"original","entryId":entries[0]["entryId"]},"offset":0,"maxBytes":65536})).await.unwrap();
    assert_eq!(
        base64::engine::general_purpose::STANDARD
            .decode(bytes["result"]["content"].as_str().unwrap())
            .unwrap(),
        PRIMARY
    );
    let (release, _) = actual
        .host
        .request(
            &actual.deadline,
            6,
            "morphir.model-originals.release",
            json!({"contractVersion":"0.1.0-draft.1","captureId":id}),
        )
        .await
        .unwrap();
    assert_eq!(release["result"]["status"], "released");
    actual.host.stop(Instant::now() + WAIT).await.unwrap();
    let workers = actual.scope.snapshot().workers();
    assert_eq!(workers.started(), 1);
    assert_eq!(workers.joined_ok(), 1);
    assert_eq!(workers.owned_handles(), 0);
    assert_eq!(workers.dropped_unjoined(), 0);
    workers.require_joined_cleanup().unwrap();
    let reads = actual.scope.snapshot();
    assert_eq!(
        reads
            .reads()
            .counts_for(&actual.record)
            .unwrap()
            .returned_bytes(),
        237
    );
    assert_eq!(
        reads
            .reads()
            .counts_for(&actual.primary)
            .unwrap()
            .returned_bytes(),
        111
    );
    assert_eq!(
        reads
            .reads()
            .counts_for(&actual.sentinel)
            .unwrap()
            .content_attempts(),
        0
    );
    assert_eq!(actual.usage.usage(), ModelCaptureUsage::default());
    drop(actual.host);
    drop(actual.prepared);
    let end = Instant::now() + WAIT;
    let mut scope = actual.scope;
    let sealed = loop {
        match scope.try_seal() {
            Ok(sealed) => break sealed,
            Err(pending) => {
                scope = pending.into_scope();
                assert!(Instant::now() < end, "real source writers did not retire");
                tokio::task::yield_now().await;
            }
        }
    };
    sealed.require_source_complete().unwrap();
    sealed.workers().require_joined_cleanup().unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn held_compile_lock_stop_refuses_then_same_host_retries_actual_join() {
    let fixture = Fixture::new();
    let mut gate = HeldCapture::new();
    let mut actual = Actual::start_with_capture_hook(&fixture, Some(gate.hook.clone())).await;
    let lock = fixture.compile_lock();
    actual.begin_held_capture().await;
    gate.entered(&actual.scope).await;
    let refused = tokio::time::timeout(
        Duration::from_secs(1),
        actual.host.stop(Instant::now() + Duration::from_millis(50)),
    )
    .await
    .unwrap();
    assert!(
        matches!(refused, Err(NativeAdapterError::Cleanup)),
        "held actual worker cannot be declared stopped: {refused:?}"
    );
    let pending = actual.scope.snapshot().workers();
    assert_eq!(pending.owned_handles(), 1);
    assert_eq!(pending.joined_ok(), 0);
    assert_eq!(pending.dropped_unjoined(), 0);
    assert!(pending.require_joined_cleanup().is_err());
    assert!(actual.usage.usage().metadata_bytes() > 0);
    fs2::FileExt::unlock(&lock).unwrap();
    gate.release();
    actual.host.stop(Instant::now() + WAIT).await.unwrap();
    let joined = actual.scope.snapshot().workers();
    assert_eq!(joined.started(), 1);
    assert_eq!(joined.returned_error(), 1);
    assert_eq!(joined.joined_ok(), 1);
    assert_eq!(joined.owned_handles(), 0);
    assert_eq!(joined.dropped_unjoined(), 0);
    joined.require_joined_cleanup().unwrap();
    assert_eq!(actual.usage.usage(), ModelCaptureUsage::default());
    assert_eq!(
        actual
            .scope
            .snapshot()
            .reads()
            .counts_for(&actual.record)
            .unwrap()
            .content_attempts(),
        0
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn explicitly_dropping_held_shutdown_owner_does_not_fabricate_a_join() {
    let fixture = Fixture::new();
    let mut gate = HeldCapture::new();
    let mut actual = Actual::start_with_capture_hook(&fixture, Some(gate.hook.clone())).await;
    let lock = fixture.compile_lock();
    actual.begin_held_capture().await;
    gate.entered(&actual.scope).await;
    // This control concerns explicit abandonment, not the stop-result oracle
    // covered above. It first exercises the actual bounded shutdown attempt.
    let _result = tokio::time::timeout(
        Duration::from_secs(1),
        actual.host.stop(Instant::now() + Duration::from_millis(50)),
    )
    .await
    .unwrap();
    drop(actual.host);
    let held = actual.scope.snapshot().workers();
    assert_eq!(held.joined_ok(), 0);
    assert!(held.require_joined_cleanup().is_err());
    fs2::FileExt::unlock(&lock).unwrap();
    gate.release();
    tokio::time::timeout(WAIT, async {
        loop {
            let workers = actual.scope.snapshot().workers();
            if workers.returned_error() == 1 && workers.dropped_unjoined() == 1 {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    let abandoned = actual.scope.snapshot().workers();
    assert_eq!(abandoned.started(), 1);
    assert_eq!(abandoned.joined_ok(), 0);
    assert_eq!(abandoned.dropped_unjoined(), 1);
    assert!(abandoned.require_joined_cleanup().is_err());
    assert_eq!(actual.usage.usage(), ModelCaptureUsage::default());
    assert_eq!(
        actual
            .scope
            .snapshot()
            .reads()
            .counts_for(&actual.record)
            .unwrap()
            .content_attempts(),
        0
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn cancelling_stop_future_keeps_same_actual_cleanup_owner_for_retry() {
    let fixture = Fixture::new();
    let mut gate = HeldCapture::new();
    let mut actual = Actual::start_with_capture_hook(&fixture, Some(gate.hook.clone())).await;
    let lock = fixture.compile_lock();
    actual.begin_held_capture().await;
    gate.entered(&actual.scope).await;
    // Cancel the actual stop future BEFORE its own shutdown deadline. This
    // must not drop the unique controller or its actual retained JoinHandle.
    let cancelled = tokio::time::timeout(
        Duration::from_millis(50),
        actual.host.stop(Instant::now() + WAIT),
    )
    .await;
    assert!(
        cancelled.is_err(),
        "held actual drain must outlive the outer caller timeout, not return success: {cancelled:?}"
    );
    let held = actual.scope.snapshot().workers();
    assert_eq!(held.started(), 1);
    assert_eq!(held.owned_handles(), 1);
    assert_eq!(held.joined_ok(), 0);
    assert_eq!(held.dropped_unjoined(), 0);
    assert!(held.require_joined_cleanup().is_err());
    assert!(actual.usage.usage().metadata_bytes() > 0);
    fs2::FileExt::unlock(&lock).unwrap();
    gate.release();
    actual.host.stop(Instant::now() + WAIT).await.unwrap();
    let joined = actual.scope.snapshot().workers();
    assert_eq!(joined.started(), 1);
    assert_eq!(joined.returned_error(), 1);
    assert_eq!(joined.joined_ok(), 1);
    assert_eq!(joined.owned_handles(), 0);
    assert_eq!(joined.dropped_unjoined(), 0);
    joined.require_joined_cleanup().unwrap();
    assert_eq!(actual.usage.usage(), ModelCaptureUsage::default());
    assert_eq!(
        actual
            .scope
            .snapshot()
            .reads()
            .counts_for(&actual.record)
            .unwrap()
            .content_attempts(),
        0
    );
}
