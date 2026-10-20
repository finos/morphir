//! Child of socket_tasks::tests. Reuses its actual task/destructor fixtures.
use super::*;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn unbounded_socket_join_cancel_preserves_same_actual_handle() {
    let capacity = HostModelCaptureCapacity::default();
    let (registry, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
    let release = Release::new();
    let entered = Arc::new(Notify::new());
    held_task(&registry, &release, entered.clone());
    tokio::time::timeout(Duration::from_secs(1), entered.notified())
        .await
        .unwrap();
    let id = first_id(&registry);
    let first_pending = {
        let join = owner.join();
        tokio::pin!(join);
        std::future::poll_fn(|cx| Poll::Ready(join.as_mut().poll(cx).is_pending())).await
    };
    let restored_id = match &registry.state().slots[0] {
        TaskSlot::Retained(actual) => Some(actual.id()),
        _ => None,
    };
    let before = owner.retained_tasks();
    // Resolve actual destruction and cleanup before evaluating the new oracles.
    release.release();
    let joined = tokio::time::timeout(Duration::from_secs(5), owner.join()).await;
    let after = owner.retained_tasks();
    drop(owner);
    drop(registry);
    let usage = capacity.usage();
    assert!(first_pending);
    assert_eq!(restored_id, Some(id));
    assert_eq!(before, 1);
    assert_eq!(joined, Ok(SocketDrainOutcome::Joined));
    assert_eq!(after, 0);
    assert_eq!(usage.metadata_bytes(), 0);
    assert_eq!(usage.source_bytes(), 0);
    assert_eq!(usage.captures(), 0);
    assert_eq!(usage.active_workers(), 0);
}
