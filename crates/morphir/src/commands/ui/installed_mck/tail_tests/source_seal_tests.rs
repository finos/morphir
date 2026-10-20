//! Actual startup-provider writer and SAME source-seal owner. No measured DATA.
use super::*;

struct SealProbe {
    completed: bool,
}
impl InstalledClientAdapter for SealProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.completed);
        assert_eq!(
            run.source().case_id(),
            "single-file-explicit-companion-preserves-opaque-bytes"
        );
        tokio::runtime::Handle::current().block_on(async {
            let end = Instant::now() + WAIT;
            let interrupted = AtomicBool::new(false);
            let fixture = fixture::Fixture::materialize(&mut run, end, &interrupted).unwrap();
            let mut host = RunningHost::start(&mut run, &fixture, end, &interrupted)
                .await
                .unwrap();
            // This is an actual production startup provider, not an artificial
            // observation lease or a counter standing in for a source writer.
            let held_provider = host.runtime._startup.workspace_provider();
            let weak = host.scope.invocation_projection();
            let stopped = host.complete(&mut run, end).await;
            let scope = host.into_source_scope().unwrap();
            let mut sealed = scope.try_seal();
            let actual_holder_kept_pending = sealed.is_err();
            drop(held_provider);
            let snapshot = loop {
                match sealed {
                    Ok(snapshot) => break snapshot,
                    Err(pending) => {
                        let same_scope = pending.into_scope();
                        tokio::task::yield_now().await;
                        sealed = same_scope.try_seal();
                        assert!(
                            Instant::now() < end,
                            "all actual host writers must be released"
                        );
                    }
                }
            };
            let source_complete = snapshot.require_source_complete();
            let scheduled_workers = snapshot.workers().scheduled();
            let joined_cleanup = snapshot.workers().require_joined_cleanup();
            let old_weak_is_dead = weak.upgrade().is_none();
            drop(snapshot);
            drop(fixture);
            assert!(stopped.is_ok());
            assert!(
                actual_holder_kept_pending,
                "actual provider must retain the SAME source owner"
            );
            assert!(source_complete.is_ok());
            assert_eq!(scheduled_workers, 0);
            assert!(
                joined_cleanup.is_err(),
                "this holder-only control must not claim a real capture worker joined"
            );
            assert!(old_weak_is_dead);
        });
        self.completed = true;
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_startup_provider_blocks_same_scope_seal_until_host_writer_release() {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut probe = SealProbe { completed: false };
    let report = tokio::task::block_in_place(|| {
        run_configured_with_installed_client_adapter(kit.path(), &configuration(), &mut probe)
    })
    .unwrap();
    assert!(
        probe.completed,
        "genuine complete24 callback must finish actual cleanup and seal assertions"
    );
    assert!(!report.qualified());
    assert!(!report.to_json().contains("client-process-measured"));
}
