//! Source-first real pending receiver across canonical callback revocation.
//! Child of installed_host_tests; test-owned task/channel only, no new host API.
use super::*;
use std::task::Poll;

#[derive(Debug, PartialEq, Eq)]
enum ReceiverCompletion {
    RevokedWithoutEvent,
    UnexpectedEvent,
    TimedOut,
    ReadyBeforeCallbackSeal,
}
struct PendingReceiverAdapter {
    task: Option<tokio::task::JoinHandle<ReceiverCompletion>>,
    actual_pending_received: bool,
}
impl InstalledClientAdapter for PendingReceiverAdapter {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        let (task, pending) = tokio::runtime::Handle::current().block_on(async {
            let mut host = LiveHost::new(&mut run, None).await;
            let (entered, observed_pending) = tokio::sync::oneshot::channel();
            // The ENTIRE genuine host is owned by this test task. Only the
            // callback-borrowed run stays here. No fabricated gate/state/fact.
            let task = tokio::spawn(async move {
                let completion = {
                    let next = host.events.next();
                    tokio::pin!(next);
                    // First poll of this SAME pinned future actually registers
                    // its real Notify waiter. Do not replace it after seal.
                    let initial =
                        std::future::poll_fn(|context| match next.as_mut().poll(context) {
                            Poll::Pending => Poll::Ready(None),
                            Poll::Ready(event) => Poll::Ready(Some(event)),
                        })
                        .await;
                    match initial {
                        None => {
                            // Canonical callback cannot return before this
                            // genuine first Pending poll has happened.
                            let _ = entered.send(());
                            match tokio::time::timeout(WAIT, next.as_mut()).await {
                                Ok(None) => ReceiverCompletion::RevokedWithoutEvent,
                                Ok(Some(event)) => {
                                    drop(event);
                                    ReceiverCompletion::UnexpectedEvent
                                }
                                Err(_) => ReceiverCompletion::TimedOut,
                            }
                        }
                        Some(event) => {
                            drop(event);
                            ReceiverCompletion::ReadyBeforeCallbackSeal
                        }
                    }
                };
                // Timeout/early-event paths still drop the pending borrow and
                // run the SAME actual host cleanup BEFORE any test assertion.
                host.stop().await;
                completion
            });
            let pending = matches!(
                tokio::time::timeout(WAIT, observed_pending).await,
                Ok(Ok(()))
            );
            (task, pending)
        });
        self.task = Some(task);
        self.actual_pending_received = pending;
        // Actual canonical engine guard now revokes and wakes the SAME gate.
        // Do not issue a test lifecycle transition, fake event or measurement.
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn same_pending_real_receiver_wakes_to_none_after_canonical_callback_seal() {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut adapter = PendingReceiverAdapter {
        task: None,
        actual_pending_received: false,
    };
    let report = tokio::task::block_in_place(|| {
        run_configured_with_installed_client_adapter(
            kit.path(),
            &config(Scenario::LiteralAuth),
            &mut adapter,
        )
    });
    // The worker future has bounded next() and existing bounded host.stop().
    // Join the actual TEST task before assertions/report inspection. This is
    // not a join handle for Axum's separate upgraded tasks, and claims no such
    // join or full source Complete. Old next() times out, then cleans up here.
    let completion = adapter.task.take().unwrap().await.unwrap();
    assert!(adapter.actual_pending_received);
    assert_eq!(completion, ReceiverCompletion::RevokedWithoutEvent);
    let report = report.unwrap();
    assert!(!report.qualified());
    assert!(!report.to_json().contains("client-process-measured"));
}

#[derive(Debug, PartialEq, Eq)]
enum KindAfterClose {
    Returned(HostEventKind),
    Panicked,
}
struct StaleKindAdapter {
    observed: Option<(KindAfterClose, bool)>,
}
impl InstalledClientAdapter for StaleKindAdapter {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.observed = Some(tokio::runtime::Handle::current().block_on(async {
            let mut host = LiveHost::new(&mut run, None).await;
            // Actual launch-exchanged cookie, actual Host/Origin and actual
            // socket entry yield the first real AuthenticatedConnection.
            let socket = host.connect(None).await.unwrap();
            let pending = tokio::time::timeout(WAIT, host.events.next())
                .await
                .unwrap()
                .unwrap();
            host.events.close();
            // Old kind() inspects the now-closed shared slot and panics.
            // Catch it solely to guarantee actual cleanup before the oracle.
            let kind =
                match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| pending.kind())) {
                    Ok(kind) => KindAfterClose::Returned(kind),
                    Err(_) => KindAfterClose::Panicked,
                };
            // Stable diagnostic DATA is never permission to acknowledge or
            // adopt a stale event. Actual receiving must still refuse.
            let refused = pending.retain(&mut run).is_err();
            drop(socket);
            host.stop().await;
            (kind, refused)
        }));
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn real_pending_kind_is_stable_after_close_but_retention_is_still_refused() {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut adapter = StaleKindAdapter { observed: None };
    let report = tokio::task::block_in_place(|| {
        run_configured_with_installed_client_adapter(
            kit.path(),
            &config(Scenario::LiteralAuth),
            &mut adapter,
        )
    });
    // Callback already completed the SAME actual host.stop cleanup, including
    // on old kind() panic. No production permission or success is synthesized.
    let (kind, refused) = adapter.observed.take().unwrap();
    assert!(refused);
    assert_eq!(
        kind,
        KindAfterClose::Returned(HostEventKind::AuthenticatedConnection)
    );
    let report = report.unwrap();
    assert!(!report.qualified());
    assert!(!report.to_json().contains("client-process-measured"));
}
