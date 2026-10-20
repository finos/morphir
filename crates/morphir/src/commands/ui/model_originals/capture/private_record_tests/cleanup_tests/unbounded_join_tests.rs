//! Child of private_record_tests::cleanup_tests. Uses the genuine provider body.
use super::*;
use std::future::Future as _;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn unbounded_capture_join_cancel_preserves_same_actual_handle() {
    let fixture = Fixture::new(RECORD);
    let mut actual = Actual::new(&fixture);
    let registry =
        super::super::super::super::lifecycle::CleanupRegistry::new(&actual.capacity).unwrap();
    actual.connection.attach_cleanup_registry(&registry);
    let mut cleanup = registry.control().into_pending();
    let mut gate = Gate::new();
    let attempt = cancelled_while_held(&actual, &mut gate).await;
    let id = cleanup
        .actual_task_id()
        .expect("genuine retained provider task");
    let first_pending = {
        let join = cleanup.join_retained();
        tokio::pin!(join);
        std::future::poll_fn(|cx| std::task::Poll::Ready(join.as_mut().poll(cx).is_pending())).await
    };
    let restored_id = cleanup.actual_task_id();
    let before = attempt.snapshot();
    let held_usage = actual.capacity.usage();
    let retained = cleanup.retained_handles();
    let capacity = actual.capacity.clone();
    let record = actual.observer.clone();
    gate.release();
    let joined = tokio::time::timeout(WAIT, cleanup.join_retained()).await;
    let after = attempt.snapshot();
    let remaining = cleanup.retained_handles();
    drop(cleanup);
    drop(registry);
    drop(actual);
    let usage = capacity.usage();
    assert!(first_pending);
    assert_eq!(restored_id, Some(id));
    assert_eq!(retained, 1);
    assert_eq!(before.owned_handles(), 1);
    assert_eq!(before.joined_ok(), 0);
    assert_eq!(before.dropped_unjoined(), 0);
    assert_eq!(held_usage.active_workers(), 1);
    assert!(held_usage.metadata_bytes() > 0);
    assert!(matches!(joined, Ok(Ok(()))));
    assert_eq!(remaining, 0);
    assert_eq!(after.joined_ok(), 1);
    assert_eq!(after.owned_handles(), 0);
    assert_eq!(after.dropped_unjoined(), 0);
    assert_joined_error(&attempt);
    assert_eq!(usage, ModelCaptureUsage::default());
    assert_eq!(record.snapshot().retained_bytes(), 0);
    assert_eq!(record.snapshot().retained_capacity(), 0);
}
