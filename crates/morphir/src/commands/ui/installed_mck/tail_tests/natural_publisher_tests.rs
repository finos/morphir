//! Additive child of installed_mck::tail_tests. ACTUAL child, offered publisher
//! and whole upgrade handle. Existing baseline/helper/policy bytes unchanged.
use super::*;
use crate::commands::ui::socket_tasks::SocketDrainOutcome;
use std::{future::Future as _, task::Poll};

struct PublisherEvidence {
    handle: tokio::task::Id,
    after_cancel: tokio::task::Id,
    after_deadline: tokio::task::Id,
    offered: crate::commands::ui::installed_observation::EventKey,
    collected: crate::commands::ui::installed_observation::EventKey,
    prepared: crate::commands::ui::installed_observation::EventKey,
    actual_prepared: Option<crate::commands::ui::installed_observation::EventKey>,
}
struct PublisherProbe {
    evidence: Option<PublisherEvidence>,
}
impl InstalledClientAdapter for PublisherProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert_eq!(
            run.source().case_id(),
            "single-file-explicit-companion-preserves-opaque-bytes"
        );
        let evidence = tokio::runtime::Handle::current().block_on(async {
            let end = Instant::now() + WAIT;
            let interrupted = AtomicBool::new(false);
            let fixture = fixture::Fixture::materialize(&mut run, end, &interrupted).unwrap();
            let mut host = RunningHost::start(&mut run, &fixture, end, &interrupted)
                .await
                .unwrap();
            let (observed, recorded) = std::sync::mpsc::channel();
            host.scope
                .lease()
                .installed_slot()
                .set_after_collect_test_probe(observed);
            let arguments = [
                OsString::from("--exact"),
                OsString::from(CHILD),
                OsString::from("--ignored"),
                OsString::from("--nocapture"),
            ];
            let environment = [(
                OsString::from("MORPHIR_TEST_TAIL_LAUNCH"),
                OsString::from(&host.runtime.launch_url),
            )];
            let process = run
                .spawn_process(
                    InstalledProcessPurpose::Metadata(InstalledMetadataQuery::Revision),
                    &std::env::current_exe().unwrap(),
                    arguments.iter().map(|arg| arg.as_os_str()),
                    &fixture.base,
                    &environment,
                    // Exact accepted prefix correction, same existing explicit
                    // component policy; no hidden positive policy/default change.
                    Limits {
                        max_frame: 1_048_576,
                        ..Limits::DEFAULT
                    },
                )
                .unwrap();
            for expected in [
                HostEventKind::AuthenticatedConnection,
                HostEventKind::ReceivedText,
                HostEventKind::PreparedSend,
            ] {
                let actual = tokio::time::timeout_at(end, host.runtime.events.next())
                    .await
                    .unwrap()
                    .unwrap();
                assert_eq!(actual.kind(), expected);
                actual.collect(&mut run).unwrap();
            }
            let finished = settle_actual_child(process, end).await;
            let child_ok = finished.outcome().status().code() == Some(0)
                && finished.outcome().first_fault().is_none();
            let output = String::from_utf8_lossy(finished.outcome().stdout());
            let exact_one = output.contains("running 1 test") && output.contains(CHILD_MARKER);
            let offered = tokio::time::timeout_at(end, async {
                loop {
                    if let Some(actual) = host
                        .scope
                        .lease()
                        .installed_slot()
                        .offered_test_diagnostic()
                    {
                        break actual;
                    }
                    tokio::task::yield_now().await;
                }
            })
            .await
            .unwrap();
            host.runtime.socket_cleanup.stop_accepting_upgrades();
            let listener_join = host.stop_listener(end).await;
            // Real child exit has closed its HTTP peers. Consume those actual
            // completed joins while repeatedly cancelling REAL borrowed natural
            // waits, until only the offered event's live publisher remains.
            // No detached driver ID or synthetic pending future is substituted.
            tokio::time::timeout_at(end, async {
                loop {
                    let pending = {
                        let wait = host.runtime.socket_cleanup.wait_naturally(end);
                        tokio::pin!(wait);
                        std::future::poll_fn(|cx| Poll::Ready(wait.as_mut().poll(cx).is_pending()))
                            .await
                    };
                    let remaining = host
                        .runtime
                        .socket_cleanup
                        .owner_mut()
                        .map(|owner| owner.retained_tasks());
                    if pending && remaining == Some(1) {
                        break;
                    }
                    tokio::time::sleep_until(end.min(Instant::now() + Duration::from_millis(1)))
                        .await;
                }
            })
            .await
            .unwrap();
            let handle = host
                .runtime
                .socket_cleanup
                .owner_mut()
                .and_then(|owner| owner.actual_task_id());
            let cancelled = {
                let wait = host.runtime.socket_cleanup.wait_naturally(end);
                tokio::pin!(wait);
                std::future::poll_fn(|cx| Poll::Ready(wait.as_mut().poll(cx).is_pending())).await
                // Actual checked-out handle restored by dropping SAME future.
            };
            let after_cancel = host
                .runtime
                .socket_cleanup
                .owner_mut()
                .and_then(|owner| owner.actual_task_id());
            let after_cancel_event = host
                .scope
                .lease()
                .installed_slot()
                .offered_test_diagnostic();
            // One fixed explicit short caller deadline. Healthy final retry
            // uses the ORIGINAL enclosing end; it is never recomputed/reset.
            let wait_end = (Instant::now() + Duration::from_millis(20)).min(end);
            let deadline = host.runtime.socket_cleanup.wait_naturally(wait_end).await;
            let after_deadline = host
                .runtime
                .socket_cleanup
                .owner_mut()
                .and_then(|owner| owner.actual_task_id());
            let after_deadline_event = host
                .scope
                .lease()
                .installed_slot()
                .offered_test_diagnostic();
            let before_ack = recorded.try_iter().collect::<Vec<_>>();
            // ACTUAL production completion must collect/cache this SAME event
            // before ACK, allow the real publisher to return and join it.
            let completed = host.complete(&mut run, end).await;
            let cleanup = if completed.is_err() {
                host.stop(end).await
            } else {
                Ok(())
            };
            let after_ack = recorded.try_iter().collect::<Vec<_>>();
            let joined = matches!(
                &host.runtime.socket_cleanup,
                crate::commands::ui::socket_tasks::SocketCleanup::Joined
            );
            let final_slot = host
                .scope
                .lease()
                .installed_slot()
                .offered_test_diagnostic();
            drop(finished);
            drop(host);
            drop(fixture);
            // All intended preservation oracles follow real child/listener/
            // driver/upgrade/capture cleanup. Setup panics remain separately
            // classified and are not certified cleanup paths.
            assert!(child_ok);
            assert!(exact_one);
            assert!(listener_join.is_ok());
            assert_eq!(offered.kind, HostEventKind::SendOutcome);
            assert!(!offered.slot_checked_out);
            assert!(cancelled);
            assert!(handle.is_some());
            assert_eq!(after_cancel, handle);
            assert_eq!(after_deadline, handle);
            for actual in [after_cancel_event, after_deadline_event] {
                let actual = actual.expect("SAME genuine tail remains Offered");
                assert_eq!(actual.key, offered.key);
                assert_eq!(actual.prepared, offered.prepared);
                assert_eq!(actual.outcome, Some(SendOutcome::Completed));
                assert!(!actual.slot_checked_out);
            }
            assert_eq!(deadline, SocketDrainOutcome::Pending { first_fault: None });
            assert_eq!(
                before_ack.len(),
                3,
                "natural waiting cannot receive or ACK the tail"
            );
            assert!(
                completed.is_ok(),
                "actual healthy completion must collect then join"
            );
            assert!(cleanup.is_ok());
            assert!(joined);
            assert_eq!(after_ack.len(), 1);
            let prepared = &before_ack[2];
            let actual = &after_ack[0];
            assert_eq!(prepared.kind, HostEventKind::PreparedSend);
            assert_eq!(actual.kind, HostEventKind::SendOutcome);
            assert_eq!(actual.key, offered.key);
            assert_eq!(actual.prepared, Some(prepared.key));
            assert_eq!(actual.outcome, Some(SendOutcome::Completed));
            assert!(actual.slot_checked_out);
            assert!(final_slot.is_none());
            PublisherEvidence {
                handle: handle.unwrap(),
                after_cancel: after_cancel.unwrap(),
                after_deadline: after_deadline.unwrap(),
                offered: offered.key,
                collected: actual.key,
                prepared: prepared.key,
                actual_prepared: actual.prepared,
            }
        });
        self.evidence = Some(evidence);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_offered_tail_publisher_survives_natural_wait_cancel_and_deadline() {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut adapter = PublisherProbe { evidence: None };
    let report = tokio::task::block_in_place(|| {
        run_configured_with_installed_client_adapter(kit.path(), &configuration(), &mut adapter)
    })
    .unwrap();
    let evidence = adapter
        .evidence
        .expect("actual callback must complete every publisher preservation/cleanup oracle");
    assert_eq!(evidence.handle, evidence.after_cancel);
    assert_eq!(evidence.handle, evidence.after_deadline);
    assert_eq!(evidence.collected, evidence.offered);
    assert_eq!(evidence.actual_prepared, Some(evidence.prepared));
    assert!(!report.qualified());
    assert!(!report.to_json().contains("client-process-measured"));
}
