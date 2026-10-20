use super::*;
use std::sync::atomic::{AtomicBool, Ordering};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn natural_completion_retains_same_task_across_cancel_deadline_and_final_destructor() {
    let capacity = HostModelCaptureCapacity::default();
    let (registry, owner) = SocketTaskRegistry::new(&capacity).unwrap();
    let mut cleanup = SocketCleanup::Pending(owner);
    let release = Release::new();
    let body_entered = Arc::new(Notify::new());
    let body_release = Arc::new(Notify::new());
    let destructor_entered = Arc::new(Notify::new());
    let completed = Arc::new(AtomicBool::new(false));
    let final_drop = HeldFinalDrop {
        entered: destructor_entered.clone(),
        release: release.0.clone(),
    };
    let entered = body_entered.clone();
    let proceed = body_release.clone();
    let finished_body = completed.clone();
    registry
        .spawn_upgrade(async move {
            entered.notify_one();
            proceed.notified().await;
            finished_body.store(true, Ordering::Release);
            tokio::task::block_in_place(|| drop(final_drop));
        })
        .unwrap();
    body_entered.notified().await;
    let id = first_id(&registry);
    let first = cleanup
        .wait_naturally(Instant::now() + Duration::from_millis(20))
        .await;
    let after_deadline = first_id(&registry);
    {
        let waiting = cleanup.wait_naturally(Instant::now() + Duration::from_secs(1));
        tokio::pin!(waiting);
        std::future::poll_fn(|cx| {
            assert!(waiting.as_mut().poll(cx).is_pending());
            Poll::Ready(())
        })
        .await;
    }
    let after_cancel = first_id(&registry);
    body_release.notify_one();
    destructor_entered.notified().await;
    let finalizing = cleanup
        .wait_naturally(Instant::now() + Duration::from_millis(20))
        .await;
    let during_destructor = first_id(&registry);
    release.release();
    let joined = cleanup
        .wait_naturally(Instant::now() + Duration::from_secs(1))
        .await;
    let body_completed = completed.load(Ordering::Acquire);
    drop(cleanup);
    drop(registry);
    assert_eq!(first, SocketDrainOutcome::Pending { first_fault: None });
    assert_eq!(
        finalizing,
        SocketDrainOutcome::Pending { first_fault: None }
    );
    assert_eq!(after_deadline, id);
    assert_eq!(after_cancel, id);
    assert_eq!(during_destructor, id);
    assert!(
        body_completed,
        "natural completion must not abort the actual task"
    );
    assert_eq!(joined, SocketDrainOutcome::Joined);
    assert_eq!(capacity.usage().metadata_bytes(), 0);
}
