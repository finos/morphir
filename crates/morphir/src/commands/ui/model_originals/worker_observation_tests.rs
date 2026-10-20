//! Independent worker-prefix controls. No host-read completeness or role credit.
//! Install as a sibling test module of model_originals after root freezes RED.
use super::lifecycle::WorkerHooks;
use super::observation::{WorkerObservationLimits, WorkerObservationScope};
use super::*;
use cap_std::fs::Dir;
use std::{
    path::Path,
    sync::{Arc, Mutex, mpsc},
    time::Duration,
};

fn limits() -> WorkerObservationLimits {
    WorkerObservationLimits::new(64, 4096).unwrap()
}
fn observed(root: &Path, limits: WorkerObservationLimits) -> WorkerObservationScope {
    let held = Dir::open_ambient_dir(root, cap_std::ambient_authority()).unwrap();
    WorkerObservationScope::bind_workspace(&held, root, limits).unwrap()
}
fn fixture() -> (tempfile::TempDir, Dir) {
    let root = tempfile::tempdir().unwrap();
    let output = root.path().join(".morphir/out");
    std::fs::create_dir_all(output.join("compile.dest")).unwrap();
    std::fs::write(
        root.path().join("morphir.toml"),
        include_bytes!("worker_observation_fixtures/project.toml"),
    )
    .unwrap();
    std::fs::write(
        output.join("compile.dest/model.json"),
        include_bytes!("worker_observation_fixtures/primary.json"),
    )
    .unwrap();
    std::fs::write(
        output.join("compile.json"),
        include_bytes!("worker_observation_fixtures/private-record.json"),
    )
    .unwrap();
    std::fs::write(
        output.join("compile.dest/secret"),
        include_bytes!("worker_observation_fixtures/undeclared-sentinel.txt"),
    )
    .unwrap();
    let held = Dir::open_ambient_dir(output, cap_std::ambient_authority()).unwrap();
    (root, held)
}
fn start(
    owner: &ModelCaptureConnection,
    output: Dir,
    hook: Arc<dyn WorkerHooks>,
) -> PendingModelCapture {
    owner
        .start_with(
            output,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Complete,
            CaptureControl::new(),
            hook,
        )
        .unwrap()
}
struct Noop;
impl WorkerHooks for Noop {}

// The gate holds the ACTUAL blocking body. Its owner releases on assertion unwind.
struct GateHook {
    arrived: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    release: Mutex<mpsc::Receiver<()>>,
}
impl WorkerHooks for GateHook {
    fn before_capture(&self) {
        self.arrived
            .lock()
            .unwrap()
            .take()
            .unwrap()
            .send(())
            .unwrap();
        self.release
            .lock()
            .unwrap()
            .recv_timeout(Duration::from_secs(10))
            .unwrap();
    }
}
struct Gate {
    hook: Arc<GateHook>,
    arrived: Option<tokio::sync::oneshot::Receiver<()>>,
    release: Option<mpsc::Sender<()>>,
}
impl Gate {
    fn new() -> Self {
        let (send, arrived) = tokio::sync::oneshot::channel();
        let (release, recv) = mpsc::channel();
        Self {
            hook: Arc::new(GateHook {
                arrived: Mutex::new(Some(send)),
                release: Mutex::new(recv),
            }),
            arrived: Some(arrived),
            release: Some(release),
        }
    }
    async fn entered(&mut self) {
        tokio::time::timeout(Duration::from_secs(5), self.arrived.take().unwrap())
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

async fn finished(pending: &PendingModelCapture) {
    tokio::time::timeout(Duration::from_secs(5), async {
        while !pending.is_finished() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
}
async fn body_returned(view: &super::observation::WorkerAttemptObservation) {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let s = view.snapshot();
            if s.returned_ok() + s.returned_error() + s.panicked() == 1 {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
}
async fn credits_gone(capacity: &HostModelCaptureCapacity) {
    tokio::time::timeout(Duration::from_secs(5), async {
        while capacity.usage() != ModelCaptureUsage::default() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
}

#[test]
fn worker_scope_binding_checks_actual_root_identity_without_content_reads() {
    let a = tempfile::tempdir().unwrap();
    let b = tempfile::tempdir().unwrap();
    let held = Dir::open_ambient_dir(a.path(), cap_std::ambient_authority()).unwrap();
    assert!(WorkerObservationScope::bind_workspace(&held, b.path(), limits()).is_err());
    let scope = observed(a.path(), limits());
    let s = scope.snapshot();
    assert_eq!(s.scheduled(), 0);
    assert_eq!(s.owned_handles(), 0);
    assert!(
        s.require_joined_cleanup().is_err(),
        "no observed worker is not a zero-work proof"
    );
}

#[tokio::test]
async fn completed_but_held_actual_join_handle_is_owned_until_real_wait() {
    let (root, output) = fixture();
    let scope = observed(root.path(), limits());
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let pending = start(&owner, output, Arc::new(Noop));
    let attempt = pending.worker_observation();
    finished(&pending).await; // genuine JoinHandle::is_finished, not a body hook
    let s = scope.snapshot_for(&attempt).unwrap();
    assert_eq!(s.scheduled(), 1);
    assert_eq!(s.started(), 1);
    assert_eq!(s.returned_ok(), 1);
    assert_eq!(s.returned_error(), 0);
    assert_eq!(s.panicked(), 0);
    assert_eq!(s.owned_handles(), 1);
    assert_eq!(s.joined_ok(), 0);
    assert_eq!(s.dropped_unjoined(), 0);
    assert!(s.require_joined_cleanup().is_err());
    let id = pending.wait().await.unwrap().ready().unwrap();
    let s = scope.snapshot_for(&attempt).unwrap();
    assert_eq!(s.owned_handles(), 0);
    assert_eq!(s.joined_ok(), 1);
    s.require_joined_cleanup().unwrap();
    owner
        .inspect_owned(&id, |sources| {
            assert_eq!(sources.source_byte_length(), 111);
            assert_eq!(
                sources.file_bytes(sources.primary().path()).unwrap(),
                include_bytes!("worker_observation_fixtures/primary.json")
            );
        })
        .unwrap();
    assert_eq!(
        capacity.usage().captures(),
        1,
        "joined is not product release"
    );
    owner.release(&id).unwrap();
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn dropping_held_actual_worker_does_not_turn_handle_zero_into_join_or_exit() {
    let (root, output) = fixture();
    let scope = observed(root.path(), limits());
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let mut gate = Gate::new();
    let pending = start(&owner, output, gate.hook.clone());
    let attempt = pending.worker_observation();
    gate.entered().await;
    assert_eq!(attempt.snapshot().owned_handles(), 1);
    drop(pending);
    owner.close();
    let s = attempt.snapshot();
    assert_eq!(s.owned_handles(), 0);
    assert_eq!(s.dropped_unjoined(), 1);
    assert_eq!(s.started(), 1);
    assert_eq!(s.returned_ok() + s.returned_error() + s.panicked(), 0);
    assert_eq!(
        s.joined_ok() + s.joined_panicked() + s.joined_cancelled(),
        0
    );
    assert_eq!(
        capacity.usage().active_workers(),
        1,
        "real body still owns its permit"
    );
    assert!(s.require_joined_cleanup().is_err());
    gate.release();
    body_returned(&attempt).await;
    credits_gone(&capacity).await;
    let s = attempt.snapshot();
    assert_eq!(s.returned_error(), 1);
    assert_eq!(s.owned_handles(), 0);
    assert_eq!(
        s.joined_ok() + s.joined_panicked() + s.joined_cancelled(),
        0
    );
    assert!(
        s.require_joined_cleanup().is_err(),
        "returned body plus zero credits is still unjoined"
    );
}

#[tokio::test]
async fn dropping_completed_but_unjoined_handle_remains_explicitly_incomplete() {
    let (root, output) = fixture();
    let scope = observed(root.path(), limits());
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let pending = start(&owner, output, Arc::new(Noop));
    let attempt = pending.worker_observation();
    finished(&pending).await;
    drop(pending);
    owner.close();
    credits_gone(&capacity).await;
    let s = attempt.snapshot();
    assert_eq!(s.returned_ok(), 1);
    assert_eq!(s.owned_handles(), 0);
    assert_eq!(s.dropped_unjoined(), 1);
    assert_eq!(s.joined_ok(), 0);
    assert!(s.require_joined_cleanup().is_err());
}

#[tokio::test]
async fn actual_storage_early_error_is_returned_and_joined_without_success_forgery() {
    let (root, output) = fixture();
    std::fs::write(root.path().join(".morphir/out/compile.json"), b"{").unwrap();
    let scope = observed(root.path(), limits());
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let pending = start(&owner, output, Arc::new(Noop));
    let attempt = pending.worker_observation();
    assert!(pending.wait().await.is_err());
    let s = attempt.snapshot();
    assert_eq!(s.returned_error(), 1);
    assert_eq!(s.returned_ok(), 0);
    assert_eq!(
        s.joined_ok(),
        1,
        "JoinHandle Ok contains the actual business Err"
    );
    assert_eq!(s.panicked(), 0);
    assert_eq!(s.owned_handles(), 0);
    s.require_joined_cleanup().unwrap();
    owner.close();
    credits_gone(&capacity).await;
}

struct PanicBody;
impl WorkerHooks for PanicBody {
    fn before_capture(&self) {
        panic!("fixed worker observation panic");
    }
}
#[tokio::test]
async fn actual_worker_panic_has_join_error_and_no_normal_return() {
    let (root, output) = fixture();
    let scope = observed(root.path(), limits());
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let pending = start(&owner, output, Arc::new(PanicBody));
    let attempt = pending.worker_observation();
    assert!(matches!(
        pending.wait().await,
        Err(CaptureError::CaptureFailed)
    ));
    let s = attempt.snapshot();
    assert_eq!(s.started(), 1);
    assert_eq!(s.panicked(), 1);
    assert_eq!(s.returned_ok() + s.returned_error(), 0);
    assert_eq!(s.joined_panicked(), 1);
    assert_eq!(s.joined_ok(), 0);
    assert_eq!(s.owned_handles(), 0);
    s.require_joined_cleanup().unwrap();
    owner.close();
    credits_gone(&capacity).await;
}

#[tokio::test]
async fn same_spelling_same_root_foreign_scope_cannot_consume_an_attempt_witness() {
    let (root, output) = fixture();
    let a = observed(root.path(), limits());
    let b = observed(root.path(), limits());
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &a);
    let pending = start(&owner, output, Arc::new(Noop));
    let attempt = pending.worker_observation();
    assert!(b.snapshot_for(&attempt).is_err());
    let id = pending.wait().await.unwrap().ready().unwrap();
    a.snapshot_for(&attempt)
        .unwrap()
        .require_joined_cleanup()
        .unwrap();
    assert_eq!(b.snapshot().scheduled(), 0);
    assert!(b.snapshot().require_joined_cleanup().is_err());
    owner.release(&id).unwrap();
}

#[tokio::test]
async fn observer_overflow_never_becomes_a_business_quota_or_complete_zero() {
    let (root, output) = fixture();
    let scope = observed(root.path(), WorkerObservationLimits::new(1, 4096).unwrap());
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let id = start(&owner, output, Arc::new(Noop))
        .wait()
        .await
        .unwrap()
        .ready()
        .unwrap();
    owner.release(&id).unwrap();
    let output = Dir::open_ambient_dir(
        root.path().join(".morphir/out"),
        cap_std::ambient_authority(),
    )
    .unwrap();
    let id = start(&owner, output, Arc::new(Noop))
        .wait()
        .await
        .unwrap()
        .ready()
        .unwrap();
    owner.release(&id).unwrap();
    let s = scope.snapshot();
    assert_eq!(s.scheduled(), 1);
    assert!(
        s.require_joined_cleanup().is_err(),
        "second real successful business capture exceeds only observer bound"
    );
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}

use crate::commands::ui::{
    protocol::project_key,
    provider::{
        SessionCapabilities, WorkspaceCapability,
        current::CurrentSessionCapabilities,
        native::NativeWorkspaceProvider,
        originals::{OriginalsProvider, OriginalsSelection},
    },
};
use morphir_devkit::ConfigLoadOptions;
fn native(root: &Path) -> Arc<NativeWorkspaceProvider> {
    Arc::new(
        NativeWorkspaceProvider::discover_with_options(
            root,
            "same-source-label",
            ConfigLoadOptions::project_only(),
        )
        .unwrap()
        .authorize_originals_lookup(cap_std::ambient_authority())
        .unwrap(),
    )
}
fn registered(
    provider: &Arc<NativeWorkspaceProvider>,
    foreign: bool,
) -> (
    CurrentSessionCapabilities,
    crate::commands::ui::provider::originals::SelectedOriginalsOffer,
) {
    let session = CurrentSessionCapabilities::new(SessionCapabilities {
        workspace: Some(provider.clone()),
        ..Default::default()
    });
    session
        .register_originals(OriginalsProvider::Native(provider.clone()))
        .unwrap();
    let mut source = provider.initial_sources().pop().unwrap();
    if foreign {
        source.provider_id = "foreign-provider".into();
    }
    let selection = OriginalsSelection::parse(&source, &project_key(&source, ".")).unwrap();
    let offer = session.select_originals(selection).unwrap();
    (session, offer)
}
async fn provider_finished(pending: &PendingProviderCapture) {
    tokio::time::timeout(Duration::from_secs(5), async {
        while !pending.is_finished() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn genuine_registered_provider_keeps_completed_handle_until_actual_join_and_release() {
    let (root, _output) = fixture();
    // Scope exists before discovery. THIS cohort observes worker ownership only;
    // this old provider constructor does not certify host/SDK read completeness.
    let scope = observed(root.path(), limits());
    let provider = native(root.path());
    let (session, offer) = registered(&provider, false);
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let pending = owner
        .start_offered_provider(offer, CaptureScope::Complete)
        .unwrap();
    let attempt = pending.worker_observation();
    provider_finished(&pending).await;
    let s = attempt.snapshot();
    assert_eq!(s.returned_ok(), 1);
    assert_eq!(s.owned_handles(), 1);
    assert_eq!(s.joined_ok(), 0);
    assert!(s.require_joined_cleanup().is_err());
    assert_eq!(
        capacity.usage().active_workers(),
        0,
        "provider published Ready before the unjoined handle is consumed"
    );
    let id = pending.wait().await.unwrap().ready().unwrap();
    attempt.snapshot().require_joined_cleanup().unwrap();
    owner
        .inspect_owned(&id, |sources| {
            assert_eq!(sources.source_byte_length(), 111);
            assert_eq!(sources.record().byte_length(), 237);
            assert_eq!(
                sources.record().sha256(),
                &morphir_distribution::Sha256Digest::parse(
                    "8002319afb380077c229776ede0d60eb8634ae49308b74420461b34a59f626d1"
                )
                .unwrap()
            );
            assert_eq!(
                sources.source_version(),
                SourceVersionEvidence::Reported(morphir_core::format_version::ReleaseTriplet::new(
                    4, 0, 0
                ))
            );
        })
        .unwrap();
    owner.release(&id).unwrap();
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
    drop(session);
}

#[tokio::test]
async fn provider_early_not_compiled_return_is_seen_without_before_worker_exit_hook() {
    let (root, _output) = fixture();
    std::fs::remove_file(root.path().join(".morphir/out/compile.json")).unwrap();
    let scope = observed(root.path(), limits());
    let provider = native(root.path());
    let (session, offer) = registered(&provider, false);
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let pending = owner
        .start_offered_provider(offer, CaptureScope::Complete)
        .unwrap();
    let attempt = pending.worker_observation();
    assert!(matches!(
        pending.wait().await.unwrap(),
        ModelCaptureCompletion::Unavailable(CaptureUnavailable::NotCompiled)
    ));
    let s = attempt.snapshot();
    assert_eq!(s.returned_ok(), 1);
    assert_eq!(s.returned_error(), 0);
    assert_eq!(s.started(), 1);
    assert_eq!(s.joined_ok(), 1);
    assert_eq!(s.owned_handles(), 0);
    s.require_joined_cleanup().unwrap();
    owner.close();
    credits_gone(&capacity).await;
    drop(session);
}

#[tokio::test]
async fn genuine_provider_authority_error_and_panic_have_distinct_body_and_join_outcomes() {
    for panic in [false, true] {
        let (root, _output) = fixture();
        let scope = observed(root.path(), limits());
        let provider = native(root.path());
        let (session, offer) = registered(&provider, !panic);
        let capacity = HostModelCaptureCapacity::default();
        let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
        let hook: Arc<dyn WorkerHooks> = if panic {
            Arc::new(PanicBody)
        } else {
            Arc::new(Noop)
        };
        let pending = owner
            .start_offered_provider_with(offer, CaptureScope::Complete, CaptureControl::new(), hook)
            .unwrap();
        let attempt = pending.worker_observation();
        let actual = pending.wait().await;
        if panic {
            assert!(matches!(
                actual,
                Err(ProviderCaptureError::Capture(CaptureError::CaptureFailed))
            ));
        } else {
            assert!(matches!(actual, Err(ProviderCaptureError::Authority(_))));
        }
        let s = attempt.snapshot();
        assert_eq!(s.started(), 1);
        assert_eq!(s.owned_handles(), 0);
        assert_eq!(s.returned_ok(), 0);
        assert_eq!(s.returned_error(), u64::from(!panic));
        assert_eq!(s.panicked(), u64::from(panic));
        assert_eq!(s.joined_ok(), u64::from(!panic));
        assert_eq!(s.joined_panicked(), u64::from(panic));
        s.require_joined_cleanup().unwrap();
        owner.close();
        credits_gone(&capacity).await;
        drop(session);
    }
}

#[tokio::test]
async fn dropping_genuine_provider_pending_while_worker_held_does_not_fake_join() {
    let (root, _output) = fixture();
    let scope = observed(root.path(), limits());
    let provider = native(root.path());
    let (session, offer) = registered(&provider, false);
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let mut gate = Gate::new();
    let pending = owner
        .start_offered_provider_with(
            offer,
            CaptureScope::Complete,
            CaptureControl::new(),
            gate.hook.clone(),
        )
        .unwrap();
    let attempt = pending.worker_observation();
    gate.entered().await;
    drop(pending);
    owner.close();
    let s = attempt.snapshot();
    assert_eq!(s.owned_handles(), 0);
    assert_eq!(s.dropped_unjoined(), 1);
    assert_eq!(s.returned_error(), 0);
    assert_eq!(s.joined_ok(), 0);
    assert_eq!(capacity.usage().active_workers(), 1);
    assert!(s.require_joined_cleanup().is_err());
    gate.release();
    body_returned(&attempt).await;
    credits_gone(&capacity).await;
    let s = attempt.snapshot();
    assert_eq!(s.returned_error(), 1);
    assert_eq!(s.joined_ok(), 0);
    assert!(s.require_joined_cleanup().is_err());
    drop(session);
}

#[tokio::test]
async fn actual_connection_identity_is_not_global_same_scope_or_same_label_identity() {
    let (root, output) = fixture();
    let scope = observed(root.path(), limits());
    let capacity = HostModelCaptureCapacity::default();
    let a = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let b = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let a_view = a.worker_observation();
    let b_view = b.worker_observation();
    let pending = start(&a, output, Arc::new(Noop));
    let attempt = pending.worker_observation();
    assert!(b_view.snapshot_for(&attempt).is_err());
    let id = pending.wait().await.unwrap().ready().unwrap();
    a_view
        .snapshot_for(&attempt)
        .unwrap()
        .require_joined_cleanup()
        .unwrap();
    assert_eq!(b_view.snapshot().scheduled(), 0);
    assert!(b_view.snapshot().require_joined_cleanup().is_err());
    a.release(&id).unwrap();
}

#[tokio::test]
async fn ordinary_unobserved_pending_cannot_manufacture_observed_worker_zero() {
    let (root, output) = fixture();
    let scope = observed(root.path(), limits());
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(capacity.clone());
    let id = start(&owner, output, Arc::new(Noop))
        .wait()
        .await
        .unwrap()
        .ready()
        .unwrap();
    owner.release(&id).unwrap();
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
    let s = scope.snapshot();
    assert_eq!(s.scheduled(), 0);
    assert_eq!(s.owned_handles(), 0);
    assert!(s.require_joined_cleanup().is_err());
}

#[tokio::test]
async fn event_counter_exhaustion_preserves_real_capture_and_denies_complete_cleanup() {
    let (root, output) = fixture();
    let scope = observed(root.path(), WorkerObservationLimits::new(64, 1).unwrap());
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new_observed(capacity.clone(), &scope);
    let id = start(&owner, output, Arc::new(Noop))
        .wait()
        .await
        .unwrap()
        .ready()
        .unwrap();
    owner.release(&id).unwrap();
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
    assert!(
        scope.snapshot().require_joined_cleanup().is_err(),
        "lost events cannot certify cleanup"
    );
}
