//! Additive actual-host budget-phase lock observation. No simulated deadlock.
use super::*;
struct Probe;
impl InstalledClientAdapter for Probe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        tokio::runtime::Handle::current().block_on(async {
            let mut host = LiveHost::new(&mut run, None).await;
            host.scope
                .lease()
                .installed_slot()
                .set_retention_probe(|slot| slot.retention_state_is_unlocked());
            let socket = host.connect(None).await.unwrap();
            let pending = tokio::time::timeout(WAIT, host.events.next())
                .await
                .unwrap()
                .unwrap();
            assert_eq!(pending.kind(), HostEventKind::AuthenticatedConnection);
            let retained = pending.retain(&mut run);
            // Always finish actual host cleanup before asserting the probe.
            // Refusal/slot close is bounded, never a stranded stdMutex lock.
            drop(socket);
            host.stop().await;
            assert!(
                retained.is_ok(),
                "actual receiving-budget phase must not hold the slot mutex"
            );
        });
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[tokio::test(flavor = "multi_thread")]
async fn actual_host_retention_budget_phase_has_no_slot_guard() {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let report = tokio::task::block_in_place(|| {
        run_configured_with_installed_client_adapter(
            kit.path(),
            &config(Scenario::LiteralAuth),
            &mut Probe,
        )
    })
    .unwrap();
    assert!(!report.qualified());
}
