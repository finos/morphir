//! Independently frozen real worker connection/issuance/unwind controls.
//! Worker-prefix evidence only. Harness blocking tasks are not model workers.
use super::lifecycle::WorkerHooks;
use super::observation::{WorkerObservationLimits, WorkerObservationScope};
use super::*;
use cap_std::fs::Dir;
use std::{
    path::Path,
    sync::{Arc, Mutex, mpsc},
    time::Duration,
};

const WAIT: Duration = Duration::from_secs(10);

fn fixture() -> (tempfile::TempDir, Dir) {
    let root = tempfile::tempdir().unwrap();
    let output = root.path().join(".morphir/out");
    std::fs::create_dir_all(output.join("compile.dest")).unwrap();
    std::fs::write(
        output.join("compile.json"),
        include_bytes!("worker_boundary_fixtures/private-record.json"),
    )
    .unwrap();
    std::fs::write(
        output.join("compile.dest/model.json"),
        include_bytes!("worker_boundary_fixtures/primary.json"),
    )
    .unwrap();
    let held = Dir::open_ambient_dir(output, cap_std::ambient_authority()).unwrap();
    (root, held)
}

fn scope(root: &Path, attempts: u64, updates: u64) -> WorkerObservationScope {
    let held = Dir::open_ambient_dir(root, cap_std::ambient_authority()).unwrap();
    WorkerObservationScope::bind_workspace(
        &held,
        root,
        WorkerObservationLimits::new(attempts, updates).unwrap(),
    )
    .unwrap()
}

struct Noop;
impl WorkerHooks for Noop {}

fn start(
    owner: &ModelCaptureConnection,
    output: Dir,
    hooks: Arc<dyn WorkerHooks>,
) -> PendingModelCapture {
    owner
        .start_with(
            output,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Complete,
            CaptureControl::new(),
            hooks,
        )
        .unwrap()
}

#[tokio::test]
async fn retained_empty_connection_views_exhaust_separate_connection_record_bound() {
    let (root, output) = fixture();
    // One connection record and one attempt record each have their own capacity1.
    let scope = scope(root.path(), 1, 4096);
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let mut retained = vec![owner.worker_observation()];
    let id = start(&owner, output, Arc::new(Noop))
        .wait()
        .await
        .unwrap()
        .ready()
        .unwrap();
    owner.release(&id).unwrap();
    scope.snapshot().require_joined_cleanup().unwrap();
    drop(owner);

    // Genuine business owners are created and dropped, while actual read-only
    // connection views remain retained. No additional worker attempt is started.
    for _ in 0..3 {
        let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
        retained.push(owner.worker_observation());
        drop(owner);
    }
    assert_eq!(retained.len(), 4);
    let snapshot = scope.snapshot();
    assert_eq!(snapshot.scheduled(), 1);
    assert_eq!(snapshot.joined_ok(), 1);
    assert_eq!(snapshot.owned_handles(), 0);
    assert!(
        snapshot.require_joined_cleanup().is_err(),
        "finite observer capacity cannot silently allocate unlimited empty connection records"
    );
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn zero_observer_bounds_preserve_actual_capture_without_complete_evidence() {
    let (root, output) = fixture();
    let scope = scope(root.path(), 0, 0);
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let view = owner.worker_observation();
    let id = start(&owner, output, Arc::new(Noop))
        .wait()
        .await
        .unwrap()
        .ready()
        .unwrap();
    owner
        .inspect_owned(&id, |sources| {
            assert_eq!(sources.source_byte_length(), 111);
            assert_eq!(
                sources.file_bytes(sources.primary().path()).unwrap(),
                include_bytes!("worker_boundary_fixtures/primary.json")
            );
        })
        .unwrap();
    owner.release(&id).unwrap();
    assert_eq!(scope.snapshot().scheduled(), 0);
    assert!(scope.snapshot().require_joined_cleanup().is_err());
    assert!(view.snapshot().require_joined_cleanup().is_err());
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}

struct Release(Option<mpsc::Sender<()>>);
impl Release {
    fn now(&mut self) {
        if let Some(send) = self.0.take() {
            let _ = send.send(());
        }
    }
}
impl Drop for Release {
    fn drop(&mut self) {
        self.now();
    }
}

fn one_blocking_thread_runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .max_blocking_threads(1)
        .enable_all()
        .build()
        .unwrap()
}

async fn occupy_blocking_pool() -> (tokio::task::JoinHandle<()>, Release) {
    let (arrived, entered) = tokio::sync::oneshot::channel();
    let (release, wait) = mpsc::channel();
    let release = Release(Some(release));
    let task = tokio::task::spawn_blocking(move || {
        arrived.send(()).unwrap();
        wait.recv_timeout(WAIT).unwrap();
    });
    tokio::time::timeout(WAIT, entered).await.unwrap().unwrap();
    (task, release)
}

struct InstallationGate {
    entered: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    release: Mutex<mpsc::Receiver<()>>,
}
impl WorkerHooks for InstallationGate {
    // New private phase callback, defaultNoop in ordinary hooks. It runs on the
    // actual spawning caller after spawn returns its genuine JoinHandle and
    // before TrackedJoin installation, outside all observation/domain locks.
    fn after_spawn_before_tracking(&self) {
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

#[test]
fn prior_joined_prefix_cannot_hide_actual_handle_awaiting_tracking_installation() {
    one_blocking_thread_runtime().block_on(async {
        let (root, output) = fixture();
        let scope = scope(root.path(), 8, 4096);
        let capacity = HostModelCaptureCapacity::default();
        let owner = Arc::new(ModelCaptureConnection::new_observed(
            capacity.clone(),
            &scope,
        ));
        let id = start(&owner, output, Arc::new(Noop))
            .wait()
            .await
            .unwrap()
            .ready()
            .unwrap();
        owner.release(&id).unwrap();
        scope.snapshot().require_joined_cleanup().unwrap();
        let connection = owner.worker_observation();
        let (blocker, mut unblock_body) = occupy_blocking_pool().await;
        let (entered, gate_entered) = tokio::sync::oneshot::channel();
        let (release, wait) = mpsc::channel();
        let mut unblock_installation = Release(Some(release));
        let hooks = Arc::new(InstallationGate {
            entered: Mutex::new(Some(entered)),
            release: Mutex::new(wait),
        });
        let caller = owner.clone();
        let output = Dir::open_ambient_dir(
            root.path().join(".morphir/out"),
            cap_std::ambient_authority(),
        )
        .unwrap();
        let starting = tokio::spawn(async move { start(&caller, output, hooks) });
        tokio::time::timeout(WAIT, gate_entered)
            .await
            .unwrap()
            .unwrap();

        // The actual second handle exists, but its body cannot enter while the
        // genuine one-slot blocking pool is held by the harness blocker.
        let snapshot = scope.snapshot();
        assert_eq!(snapshot.started(), 1);
        assert_eq!(snapshot.joined_ok(), 1);
        assert_eq!(capacity.usage().active_workers(), 1);
        assert!(snapshot.require_joined_cleanup().is_err());
        assert!(connection.snapshot().require_joined_cleanup().is_err());

        unblock_installation.now();
        let pending = tokio::time::timeout(WAIT, starting).await.unwrap().unwrap();
        unblock_body.now();
        blocker.await.unwrap();
        let id = pending.wait().await.unwrap().ready().unwrap();
        owner.release(&id).unwrap();
        scope.snapshot().require_joined_cleanup().unwrap();
        connection.snapshot().require_joined_cleanup().unwrap();
        assert_eq!(capacity.usage(), ModelCaptureUsage::default());
    });
}

struct PanicOnFinalHookDrop;
impl WorkerHooks for PanicOnFinalHookDrop {}
impl Drop for PanicOnFinalHookDrop {
    fn drop(&mut self) {
        panic!("independently fixed final worker hook drop panic");
    }
}

#[test]
fn actual_final_hook_drop_panic_is_a_whole_body_panic_before_join() {
    one_blocking_thread_runtime().block_on(async {
        let (root, output) = fixture();
        let scope = scope(root.path(), 8, 4096);
        let capacity = HostModelCaptureCapacity::default();
        let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
        let (blocker, mut release) = occupy_blocking_pool().await;
        // No caller retains a hook Arc. Queueing until start() returns ensures
        // any short-lived caller-side phase-hook clone is also already dropped.
        let pending = start(&owner, output, Arc::new(PanicOnFinalHookDrop));
        let attempt = pending.worker_observation();
        release.now();
        blocker.await.unwrap();
        tokio::time::timeout(WAIT, async {
            while !pending.is_finished() {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        // The genuine handle is complete but still unconsumed. The storage
        // product is Prepared until the armed Pending's failed wait drops it.
        assert_eq!(capacity.usage().captures(), 1);
        assert!(matches!(
            pending.wait().await,
            Err(CaptureError::CaptureFailed)
        ));
        let snapshot = attempt.snapshot();
        assert_eq!(snapshot.started(), 1);
        assert_eq!(snapshot.returned_ok(), 0);
        assert_eq!(snapshot.returned_error(), 0);
        assert_eq!(snapshot.panicked(), 1);
        assert_eq!(snapshot.joined_panicked(), 1);
        assert_eq!(snapshot.joined_ok(), 0);
        assert_eq!(snapshot.owned_handles(), 0);
        snapshot.require_joined_cleanup().unwrap();
        // wait_prepared's JoinError return leaves armed=true. Existing Pending
        // Drop calls abandon and releases Prepared resources before wait returns.
        assert_eq!(capacity.usage(), ModelCaptureUsage::default());
        owner.close();
        assert_eq!(capacity.usage(), ModelCaptureUsage::default());
    });
}
