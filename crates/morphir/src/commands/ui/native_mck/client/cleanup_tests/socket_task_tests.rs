//! Real authenticated upgrades cancelled while a genuine provider worker is held.
use super::*;
use crate::commands::ui::socket_tasks::{SocketCleanupError, SocketDrainOutcome};

async fn exercise(panic: bool) {
    let fixture = Fixture::new();
    let mut gate = HeldCapture::new();
    let mut actual = Actual::start_with_capture_hook(&fixture, Some(gate.hook.clone())).await;
    actual.begin_held_capture().await;
    gate.entered(&actual.scope).await;
    let owner = actual
        .host
        .socket_cleanup
        .owner_mut()
        .expect("real socket cleanup owner");
    if panic {
        owner.panic_tasks();
        tokio::time::timeout(WAIT, async {
            while !owner.tasks_finished() {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
    }
    let sockets = owner.drain(Instant::now() + WAIT).await;
    let retained_sockets = owner.retained_tasks();
    // The peer is deliberately still open while its actual server task joins.
    let peer_open = actual.host.socket.is_some();
    let before = actual.scope.snapshot();
    let before_workers = before.workers();
    let before_usage = actual.usage.usage();
    let read_attempts = before
        .reads()
        .counts_for(&actual.record)
        .unwrap()
        .content_attempts();
    let retained = match &actual.host.capture_cleanup {
        CaptureCleanup::Pending(owner) => owner.retained_handles(),
        CaptureCleanup::Joined => 0,
    };
    let bounded = match &mut actual.host.capture_cleanup {
        CaptureCleanup::Pending(owner) => {
            owner
                .drain_retained(Instant::now() + Duration::from_millis(20))
                .await
        }
        CaptureCleanup::Joined => Ok(()),
    };
    // Always release/drain the real worker before any oracle can fail.
    gate.release();
    let drained = match &mut actual.host.capture_cleanup {
        CaptureCleanup::Pending(owner) => owner.drain_retained(Instant::now() + WAIT).await,
        CaptureCleanup::Joined => Ok(()),
    };
    let after = actual.scope.snapshot().workers();
    let stopped = actual.host.stop(Instant::now() + WAIT).await;
    drop(actual.host);
    let usage = actual.usage.usage();
    assert_eq!(
        sockets,
        if panic {
            SocketDrainOutcome::JoinedWithFault(SocketCleanupError::TaskPanicked)
        } else {
            SocketDrainOutcome::Joined
        }
    );
    assert_eq!(retained_sockets, 0);
    assert!(peer_open);
    assert_eq!(before_workers.started(), 1);
    assert_eq!(before_workers.owned_handles(), 1);
    assert_eq!(before_workers.dropped_unjoined(), 0);
    assert_eq!(before_workers.joined_ok(), 0);
    assert_eq!(retained, 1);
    assert_eq!(before_usage.active_workers(), 1);
    assert!(before_usage.metadata_bytes() > 0);
    assert_eq!(read_attempts, 0);
    assert!(bounded.is_err());
    assert!(drained.is_ok());
    assert_eq!(after.joined_ok(), 1);
    assert_eq!(after.owned_handles(), 0);
    assert_eq!(after.dropped_unjoined(), 0);
    if panic {
        assert!(stopped.is_err());
    } else {
        assert!(stopped.is_ok());
    }
    assert_eq!(usage, ModelCaptureUsage::default());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn whole_upgrade_abort_hands_off_before_dispatch_drop() {
    exercise(false).await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn whole_upgrade_panic_hands_off_before_dispatch_drop() {
    exercise(true).await;
}
