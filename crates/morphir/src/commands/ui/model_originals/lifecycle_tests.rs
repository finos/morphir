use super::*;
use cap_std::fs::Dir;

fn fixture(bytes: &[u8]) -> (tempfile::TempDir, Dir) {
    let temp = tempfile::tempdir().unwrap();
    std::fs::create_dir(temp.path().join("compile.dest")).unwrap();
    std::fs::write(temp.path().join("compile.dest/model.json"), bytes).unwrap();
    std::fs::write(temp.path().join("compile.json"), br#"{"schema":1,"task":"compile","module":"","completedAt":"now","ir":{"path":"model.json","layout":"single-file","format":"json","version":"v4"}}"#).unwrap();
    let dir = Dir::open_ambient_dir(temp.path(), cap_std::ambient_authority()).unwrap();
    (temp, dir)
}

#[tokio::test]
async fn actual_capture_is_owner_scoped_until_release_or_disconnect() {
    let (_temp, dir) = fixture(b"original\r\n");
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(capacity.clone());
    let other = ModelCaptureConnection::new(capacity.clone());
    let capture = owner
        .start(
            dir,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Primary,
        )
        .unwrap()
        .wait()
        .await
        .unwrap()
        .ready()
        .unwrap();
    assert_eq!(owner.inspect(&capture).unwrap().source_byte_length(), 10);
    assert!(matches!(
        other.inspect(&capture),
        Err(CaptureError::UnknownHandle)
    ));
    assert!(matches!(
        other.release(&capture),
        Err(CaptureError::UnknownHandle)
    ));
    assert_eq!(capacity.usage().source_bytes(), 10);
    assert_eq!(capacity.usage().captures(), 1);
    assert_eq!(capacity.usage().active_workers(), 0);
    owner.release(&capture).unwrap();
    owner.release(&capture).unwrap();
    assert_eq!(capacity.usage().captures(), 0);
    assert_eq!(capacity.usage().source_bytes(), 0);
    assert_eq!(capacity.usage().metadata_bytes(), 0);
    assert!(matches!(
        owner.inspect(&capture),
        Err(CaptureError::UnknownHandle)
    ));
    owner.close();
    assert!(matches!(
        owner.release(&capture),
        Err(CaptureError::UnknownHandle)
    ));
}

use super::lifecycle::{HostLimits, WorkerHooks};
use std::{
    sync::{Arc, Mutex, mpsc},
    time::Duration,
};

enum HoldAt {
    Before,
    After,
}
struct HoldWorker {
    at: HoldAt,
    arrived: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    release: Mutex<mpsc::Receiver<()>>,
}
impl HoldWorker {
    fn block(&self) {
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
impl WorkerHooks for HoldWorker {
    fn before_capture(&self) {
        if matches!(self.at, HoldAt::Before) {
            self.block();
        }
    }
    fn after_capture(&self) {
        if matches!(self.at, HoldAt::After) {
            self.block();
        }
    }
}
fn held(
    at: HoldAt,
) -> (
    Arc<HoldWorker>,
    tokio::sync::oneshot::Receiver<()>,
    mpsc::Sender<()>,
) {
    let (sender, arrived) = tokio::sync::oneshot::channel();
    let (release, receiver) = mpsc::channel();
    (
        Arc::new(HoldWorker {
            at,
            arrived: Mutex::new(Some(sender)),
            release: Mutex::new(receiver),
        }),
        arrived,
        release,
    )
}
async fn workers_stopped(capacity: &HostModelCaptureCapacity) {
    tokio::time::timeout(Duration::from_secs(5), async {
        while capacity.usage().active_workers() != 0 {
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
    })
    .await
    .unwrap();
}
async fn run(owner: &ModelCaptureConnection, dir: Dir) -> Result<CaptureId, CaptureError> {
    Ok(owner
        .start(
            dir,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Primary,
        )?
        .wait()
        .await?
        .ready()
        .unwrap())
}

#[tokio::test]
async fn reserves_slot_and_work_before_effects_and_refusal_never_opens_storage() {
    let (temp, dir) = fixture(b"bytes");
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(capacity.clone());
    let (hook, arrived, release) = held(HoldAt::Before);
    let pending = owner
        .start_with(
            dir,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    assert_eq!(capacity.usage().captures(), 1);
    assert_eq!(capacity.usage().active_workers(), 1);
    assert_eq!(capacity.usage().source_bytes(), 0);
    assert!(!temp.path().join("compile.lock").exists());
    let other = ModelCaptureConnection::new(capacity.clone());
    let empty = tempfile::tempdir().unwrap();
    let dir = Dir::open_ambient_dir(empty.path(), cap_std::ambient_authority()).unwrap();
    assert!(matches!(
        other.start(
            dir,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Primary
        ),
        Err(CaptureError::Capacity)
    ));
    assert!(!empty.path().join("compile.lock").exists());
    let dir = Dir::open_ambient_dir(empty.path(), cap_std::ambient_authority()).unwrap();
    assert!(matches!(
        owner.start(
            dir,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Primary
        ),
        Err(CaptureError::ActiveCapture)
    ));
    release.send(()).unwrap();
    let id = pending.wait().await.unwrap().ready().unwrap();
    assert_eq!(owner.inspect(&id).unwrap().source_byte_length(), 5);
    assert_eq!(capacity.usage().active_workers(), 0);
}

#[tokio::test]
async fn cancelled_copy_keeps_work_bytes_and_metadata_until_worker_exits() {
    let (_temp, dir) = fixture(b"held-originals");
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(capacity.clone());
    let (hook, arrived, release) = held(HoldAt::After);
    let pending = owner
        .start_with(
            dir,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    let reserved = capacity.usage();
    assert_eq!(reserved.source_bytes(), 14);
    assert!(reserved.metadata_bytes() > 0);
    pending.cancel();
    assert!(matches!(pending.wait().await, Err(CaptureError::Timeout)));
    assert_eq!(capacity.usage(), reserved);
    owner.close();
    assert_eq!(capacity.usage(), reserved);
    let other = ModelCaptureConnection::new(capacity.clone());
    let (_temp, dir) = fixture(b"new");
    assert!(matches!(
        other.start(
            dir,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Primary
        ),
        Err(CaptureError::Capacity)
    ));
    release.send(()).unwrap();
    workers_stopped(&capacity).await;
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
    let (_temp, dir) = fixture(b"new");
    let id = run(&other, dir).await.unwrap();
    assert_eq!(other.inspect(&id).unwrap().source_byte_length(), 3);
}

#[tokio::test]
async fn disconnect_while_copy_is_held_cannot_publish_or_free_another_owner() {
    let capacity = HostModelCaptureCapacity::default();
    let stable = ModelCaptureConnection::new(capacity.clone());
    let (_stable_temp, stable_dir) = fixture(b"stable");
    let stable_id = run(&stable, stable_dir).await.unwrap();
    let baseline = capacity.usage();
    let abandoned = ModelCaptureConnection::new(capacity.clone());
    let (_temp, dir) = fixture(b"abandoned");
    let (hook, arrived, release) = held(HoldAt::After);
    let pending = abandoned
        .start_with(
            dir,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    drop(abandoned);
    assert_eq!(capacity.usage().captures(), 2);
    assert_eq!(capacity.usage().active_workers(), 1);
    assert_eq!(stable.inspect(&stable_id).unwrap().source_byte_length(), 6);
    assert!(matches!(pending.wait().await, Err(CaptureError::Timeout)));
    release.send(()).unwrap();
    workers_stopped(&capacity).await;
    assert_eq!(capacity.usage(), baseline);
    assert!(stable.inspect(&stable_id).is_ok());
}

#[tokio::test]
async fn dropped_wait_future_cancels_only_its_own_attempt_and_holds_credits() {
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(capacity.clone());
    let (_temp, dir) = fixture(b"held");
    let (hook, arrived, release) = held(HoldAt::After);
    let pending = owner
        .start_with(
            dir,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    let waiter = tokio::spawn(pending.wait());
    waiter.abort();
    assert!(waiter.await.unwrap_err().is_cancelled());
    assert_eq!(capacity.usage().active_workers(), 1);
    assert_eq!(capacity.usage().source_bytes(), 4);
    release.send(()).unwrap();
    workers_stopped(&capacity).await;
    let (_temp, dir) = fixture(b"replacement");
    let id = run(&owner, dir).await.unwrap();
    assert_eq!(owner.inspect(&id).unwrap().source_byte_length(), 11);
}

#[tokio::test]
async fn stale_pending_drop_cannot_clear_a_later_ready_attempt_on_same_connection() {
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(capacity.clone());
    let (_temp, dir) = fixture(b"first");
    let (hook, arrived, release) = held(HoldAt::After);
    let pending = owner
        .start_with(
            dir,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Primary,
            CaptureControl::new(),
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    pending.cancel();
    release.send(()).unwrap();
    workers_stopped(&capacity).await;
    let (_temp, dir) = fixture(b"second");
    let id = run(&owner, dir).await.unwrap();
    drop(pending); // its completion is deliberately not received first
    assert_eq!(owner.inspect(&id).unwrap().source_byte_length(), 6);
    assert_eq!(capacity.usage().captures(), 1);
}

#[tokio::test]
async fn exact_host_byte_capacity_and_zero_byte_captures_have_distinct_credits() {
    let capacity = HostModelCaptureCapacity::with_limits(HostLimits {
        bytes: 3,
        ..Default::default()
    });
    let first = ModelCaptureConnection::new(capacity.clone());
    let (_temp, dir) = fixture(b"abc");
    let first_id = run(&first, dir).await.unwrap();
    let second = ModelCaptureConnection::new(capacity.clone());
    let (_temp, dir) = fixture(b"x");
    assert!(matches!(
        run(&second, dir).await,
        Err(CaptureError::Capacity)
    ));
    assert_eq!(capacity.usage().source_bytes(), 3);
    assert_eq!(capacity.usage().captures(), 1);
    let (_temp, dir) = fixture(b"");
    let zero = run(&second, dir).await.unwrap();
    assert_eq!(second.inspect(&zero).unwrap().source_byte_length(), 0);
    assert_eq!(capacity.usage().captures(), 2);
    first.release(&first_id).unwrap();
    assert_eq!(capacity.usage().source_bytes(), 0);
    assert_eq!(capacity.usage().captures(), 1);
    second.release(&zero).unwrap();
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn host_metadata_exact_and_one_over_rollback_source_slot_and_work() {
    // Independently authored from compact root35B + entry175B, using a literal
    // UUID36 and digest64. One-digit byte length; never derived from host output.
    let metadata = 210;
    for bound in [metadata - 1, metadata] {
        let capacity = HostModelCaptureCapacity::with_limits(HostLimits {
            metadata: bound,
            ..Default::default()
        });
        let owner = ModelCaptureConnection::new(capacity.clone());
        let (_temp, dir) = fixture(b"bytes");
        let result = run(&owner, dir).await;
        if bound == metadata {
            let id = result.unwrap();
            assert_eq!(capacity.usage().metadata_bytes(), metadata);
            owner.release(&id).unwrap();
        } else {
            assert!(matches!(result, Err(CaptureError::Capacity)));
        }
        assert_eq!(capacity.usage(), ModelCaptureUsage::default());
    }
}

#[tokio::test]
async fn all_64_zero_byte_capture_slots_are_real_and_65th_has_no_effects() {
    let capacity = HostModelCaptureCapacity::default();
    let mut owners = Vec::new();
    for _ in 0..MAX_HOST_CAPTURES {
        let owner = ModelCaptureConnection::new(capacity.clone());
        let (_temp, dir) = fixture(b"");
        let id = run(&owner, dir).await.unwrap();
        owners.push((owner, id));
    }
    assert_eq!(capacity.usage().captures(), MAX_HOST_CAPTURES);
    assert_eq!(capacity.usage().source_bytes(), 0);
    assert!(capacity.usage().metadata_bytes() > 0);
    let extra = ModelCaptureConnection::new(capacity.clone());
    let empty = tempfile::tempdir().unwrap();
    let dir = Dir::open_ambient_dir(empty.path(), cap_std::ambient_authority()).unwrap();
    assert!(matches!(
        extra.start(
            dir,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Primary
        ),
        Err(CaptureError::Capacity)
    ));
    assert!(!empty.path().join("compile.lock").exists());
    let (first, id) = owners.remove(0);
    first.release(&id).unwrap();
    let (_temp, dir) = fixture(b"");
    run(&extra, dir).await.unwrap();
    assert_eq!(capacity.usage().captures(), MAX_HOST_CAPTURES);
    drop(owners);
    drop(extra);
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}

#[tokio::test]
async fn io_and_declaration_failures_return_all_credits_and_allow_next_capture() {
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(capacity.clone());
    let (temp, dir) = fixture(b"data");
    std::fs::remove_file(temp.path().join("compile.dest/model.json")).unwrap();
    assert!(matches!(
        run(&owner, dir).await,
        Err(CaptureError::CaptureFailed)
    ));
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
    let (_temp, dir) = fixture(b"data");
    assert!(matches!(
        owner
            .start(
                dir,
                SelectedModule::parse("").unwrap(),
                CaptureScope::Complete
            )
            .unwrap()
            .wait()
            .await
            .unwrap(),
        ModelCaptureCompletion::Unavailable(CaptureUnavailable::CompanionsUndeclared)
    ));
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
    let (temp, dir) = fixture(b"data");
    let path = temp.path().join("compile.json");
    let record = std::fs::read_to_string(&path).unwrap();
    let record = record.strip_suffix('}').unwrap().to_owned()
        + r#", "morphirModelOriginals":{"contractVersion":"wrong","companions":[]}}"#;
    std::fs::write(path, record).unwrap();
    assert!(matches!(
        owner
            .start(
                dir,
                SelectedModule::parse("").unwrap(),
                CaptureScope::Complete
            )
            .unwrap()
            .wait()
            .await,
        Err(CaptureError::InvalidDeclaration)
    ));
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
    let (_temp, dir) = fixture(b"next");
    run(&owner, dir).await.unwrap();
}

#[tokio::test]
async fn release_tombstone_is_local_idempotent_and_retired_by_next_capture() {
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(capacity);
    let (_temp, dir) = fixture(b"one");
    let first = run(&owner, dir).await.unwrap();
    owner.release(&first).unwrap();
    owner.release(&first).unwrap();
    let (_temp, dir) = fixture(b"two");
    let next = run(&owner, dir).await.unwrap();
    assert_ne!(first, next);
    assert!(matches!(
        owner.release(&first),
        Err(CaptureError::UnknownHandle)
    ));
    assert!(owner.inspect(&next).is_ok());
    owner.close();
    owner.close();
    assert!(matches!(
        owner.inspect(&next),
        Err(CaptureError::UnknownHandle)
    ));
}

#[tokio::test]
async fn timeout_returns_to_waiter_but_retains_held_workers_actual_credits() {
    let capacity = HostModelCaptureCapacity::default();
    let owner = ModelCaptureConnection::new(capacity.clone());
    let (_temp, dir) = fixture(b"timed-out");
    let (hook, arrived, release) = held(HoldAt::After);
    let control = CaptureControl::with_timeout(Duration::from_secs(1));
    let pending = owner
        .start_with(
            dir,
            SelectedModule::parse("").unwrap(),
            CaptureScope::Primary,
            control,
            hook,
        )
        .unwrap();
    arrived.await.unwrap();
    let held = capacity.usage();
    assert_eq!(held.source_bytes(), 9);
    assert_eq!(held.active_workers(), 1);
    assert!(matches!(pending.wait().await, Err(CaptureError::Timeout)));
    assert_eq!(capacity.usage(), held);
    release.send(()).unwrap();
    workers_stopped(&capacity).await;
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
    let (_temp, dir) = fixture(b"after-timeout");
    run(&owner, dir).await.unwrap();
}

#[tokio::test]
async fn metadata_capacity_is_aggregate_across_real_capture_owners() {
    let (_temp, dir) = fixture(b"x");
    let metadata = 210; // root35B + entry175B, independently authored above
    let capacity = HostModelCaptureCapacity::with_limits(HostLimits {
        metadata: 2 * metadata - 1,
        ..Default::default()
    });
    let first = ModelCaptureConnection::new(capacity.clone());
    let id = run(&first, dir).await.unwrap();
    assert_eq!(first.inspect(&id).unwrap().metadata_byte_length(), metadata);
    let baseline = capacity.usage();
    let second = ModelCaptureConnection::new(capacity.clone());
    let (_temp, dir) = fixture(b"x");
    assert!(matches!(
        run(&second, dir).await,
        Err(CaptureError::Capacity)
    ));
    assert_eq!(capacity.usage(), baseline);
    assert!(first.inspect(&id).is_ok());
    first.release(&id).unwrap();
    let (_temp, dir) = fixture(b"x");
    run(&second, dir).await.unwrap();
}

#[tokio::test]
async fn actual_128mib_host_capacity_accepts_two_64mib_owners_then_refuses_one_byte() {
    let capacity = HostModelCaptureCapacity::default();
    let mut owners = Vec::new();
    for _ in 0..2 {
        let (temp, dir) = fixture(b"");
        std::fs::File::create(temp.path().join("compile.dest/model.json"))
            .unwrap()
            .set_len(MAX_SOURCE_BYTES as u64)
            .unwrap();
        let owner = ModelCaptureConnection::new(capacity.clone());
        let id = run(&owner, dir).await.unwrap();
        owners.push((owner, id));
    }
    assert_eq!(capacity.usage().source_bytes(), MAX_HOST_CAPTURE_BYTES);
    let baseline = capacity.usage();
    let third = ModelCaptureConnection::new(capacity.clone());
    let (_temp, dir) = fixture(b"x");
    assert!(matches!(
        run(&third, dir).await,
        Err(CaptureError::Capacity)
    ));
    assert_eq!(capacity.usage(), baseline);
    let (_temp, dir) = fixture(b"");
    let zero = run(&third, dir).await.unwrap();
    assert_eq!(capacity.usage().source_bytes(), MAX_HOST_CAPTURE_BYTES);
    assert_eq!(capacity.usage().captures(), 3);
    assert_eq!(third.inspect(&zero).unwrap().source_byte_length(), 0);
    drop(owners);
    drop(third);
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}
