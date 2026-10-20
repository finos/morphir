//! Proposed child of installed_mck. Synthetic process purpose, REAL host/TCP/
//! WebSocket/process ownership. No Git/canonical success DATA or role credit.
use super::*;
use crate::commands::ui::installed_observation::{
    HostEventKind, InstalledCollectedTestDiagnostic, SendOutcome,
};
use futures_util::{SinkExt as _, StreamExt as _};
use morphir_mck::{
    transport::process::ProcessProgress,
    workbench::{
        RunConfiguration,
        model_originals::installed::{
            InstalledMetadataQuery, InstalledProcessFinish, InstalledProcessPurpose,
        },
        run_configured_with_installed_client_adapter,
    },
};
use serde_json::{Value, json};
use std::{ffi::OsString, time::Duration};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{Message, client::IntoClientRequest as _},
};

const CASES: &[u8] =
    include_bytes!("../model_originals/capture/installed_host_tests/fixtures/cases24.json");
const CHECKER: &str =
    include_str!("../model_originals/capture/installed_host_tests/fixtures/checker-policy.json");
const CHILD: &str = "commands::ui::installed_mck::tail_tests::actual_tail_peer_child";
const CHILD_MARKER: &str = "actual-tail-peer-read-reply-v1";
const WAIT: Duration = Duration::from_secs(10);

// Existing explicit component policy, unchanged fixture/checker bytes. This
// callback intentionally returns no measurement and cannot qualify a role.
fn configuration() -> RunConfiguration {
    RunConfiguration::from_json(&json!({"kind":"model-originals-installed-client",
        "checker":serde_json::from_str::<Value>(CHECKER).unwrap(),
        "observation":{"source":{"attempts":8192,"readCalls":8192,"returnedBytes":67108864,"files":16},"workers":{"attempts":64,"updates":8192},"host":{"updates":8192}},
        "privateRecord":{"retainedBytes":67108864},
        "installedObservation":{"rpcFrames":"checker-capture","retainedBytes":16777216,"stdoutPrefixBytes":1048576,"stderrPrefixBytes":1048576,"snapshotReadBytes":16777216,"byteVisits":67108864,"records":8192}
    }).to_string()).unwrap()
}

#[test]
#[ignore = "Test-only self-peer; selected by exact parent argv with private launch input"]
fn actual_tail_peer_child() {
    let launch = std::env::var("MORPHIR_TEST_TAIL_LAUNCH").expect("explicit child launch input");
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap().block_on(async {
        tokio::time::timeout(WAIT, async {
            let client = reqwest::Client::builder().redirect(reqwest::redirect::Policy::none()).build().unwrap();
            let launched = client.get(&launch).send().await.unwrap();
            assert_eq!(launched.status(), reqwest::StatusCode::SEE_OTHER);
            let cookie = launched.headers()["set-cookie"].to_str().unwrap().split(';').next().unwrap().to_owned();
            let base = launch.split_once("/launch?").unwrap().0;
            let session: Value = client.get(format!("{base}/api/session")).header("cookie", &cookie).send().await.unwrap().json().await.unwrap();
            let mut request = format!("{}/rpc", base.replacen("http://", "ws://", 1)).into_client_request().unwrap();
            request.headers_mut().insert("origin", base.parse().unwrap());
            request.headers_mut().insert("cookie", cookie.parse().unwrap());
            let (mut socket, _) = connect_async(request).await.unwrap();
            socket.send(Message::Text(json!({"jsonrpc":"2.0","id":1,"method":"morphir.session.initialize","params":{"protocolVersion":1,"sessionId":session["sessionId"]}}).to_string().into())).await.unwrap();
            let reply = socket.next().await.unwrap().unwrap().into_text().unwrap();
            let reply: Value = serde_json::from_str(&reply).unwrap();
            assert_eq!(reply["id"], 1);
            assert_eq!(reply["result"]["protocolVersion"], 1);
            // The real physical reply was read. Do not wait for the server's
            // collector ACK; dropping this actual peer permits genuine exit.
            println!("{CHILD_MARKER}");
            drop(socket);
        }).await.unwrap();
    });
}

async fn settle_actual_child(
    mut process: RunningInstalledProcess,
    end: Instant,
) -> morphir_mck::workbench::model_originals::installed::FinishedInstalledProcess {
    loop {
        match process.advance() {
            ProcessProgress::ExitObserved(_) | ProcessProgress::Faulted(_) => {
                let _ = process.request_termination();
            }
            ProcessProgress::Working | ProcessProgress::Finished(_) => {}
        }
        process.reap_retained().unwrap();
        match process.try_finish() {
            InstalledProcessFinish::Finished(finished) => return finished,
            InstalledProcessFinish::Pending(same) => process = same,
        }
        assert!(Instant::now() < end, "actual self-peer must settle");
        tokio::time::sleep_until(end.min(Instant::now() + Duration::from_millis(1))).await;
    }
}

#[derive(Debug, PartialEq, Eq)]
enum TailCase {
    SingleFileExplicitCompanion,
}
// Bounded test evidence, not a join capability or a successful measurement.
// Created only after real cleanup and every original end-phase assertion.
struct TailEvidence {
    source_case: TailCase,
    offered: crate::commands::ui::installed_observation::EventKey,
    collected: crate::commands::ui::installed_observation::EventKey,
    prepared: crate::commands::ui::installed_observation::EventKey,
    outcome_prepared: Option<crate::commands::ui::installed_observation::EventKey>,
    child_status: Option<i32>,
}
struct TailProbe {
    evidence: Option<TailEvidence>,
}
impl InstalledClientAdapter for TailProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        let source_case = match run.source().case_id() {
            "single-file-explicit-companion-preserves-opaque-bytes" => {
                TailCase::SingleFileExplicitCompanion
            }
            actual => panic!("tail callback entered an unexpected actual case: {actual}"),
        };
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
                    // Explicit test-only purpose. Its stdout is NEVER recorded as
                    // an actual Git query or canonical successful command DATA.
                    InstalledProcessPurpose::Metadata(InstalledMetadataQuery::Revision),
                    &std::env::current_exe().unwrap(),
                    arguments.iter().map(|arg| arg.as_os_str()),
                    &fixture.base,
                    &environment,
                    Limits {
                        max_frame: 1_048_576,
                        ..Limits::DEFAULT
                    },
                )
                .unwrap();
            // The third successful COLLECT releases the actual PreparedSend.
            // Deliberately DO NOT receive/claim the real final SendOutcome.
            for expected in [
                HostEventKind::AuthenticatedConnection,
                HostEventKind::ReceivedText,
                HostEventKind::PreparedSend,
            ] {
                let event = tokio::time::timeout_at(end, host.runtime.events.next())
                    .await
                    .unwrap()
                    .unwrap();
                assert_eq!(event.kind(), expected);
                event.collect(&mut run).unwrap();
            }
            let finished = settle_actual_child(process, end).await;
            let child_status = finished.outcome().status().code();
            let process_ok = child_status == Some(0) && finished.outcome().first_fault().is_none();
            let stdout = String::from_utf8_lossy(finished.outcome().stdout());
            let exact_one = stdout.contains("running 1 test") && stdout.contains(CHILD_MARKER);
            // Readonly SAME-slot observation, never a claim or ACK. The child
            // is actually Finished/reaped/readers-joined BEFORE this phase.
            let offered: InstalledCollectedTestDiagnostic = tokio::time::timeout_at(end, async {
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
            // BASELINE call against existing production API. After genuine
            // behavioral RED only, mechanical caller successor adds &mut run
            // here so production completion can COLLECT under the SAME owner.
            let stopped = host.complete(&mut run, end).await;
            let records: Vec<_> = recorded.try_iter().collect();
            let final_slot = host
                .scope
                .lease()
                .installed_slot()
                .offered_test_diagnostic();
            let real_sockets_joined = matches!(
                &host.runtime.socket_cleanup,
                super::super::socket_tasks::SocketCleanup::Joined
            );
            // Actual child is already consumed to Finished. stop has attempted
            // listener, actual driver/upgrade joins and capture cleanup. Drop
            // real remaining fixture/startup/receiver owners before assertions.
            drop(finished);
            drop(host);
            drop(fixture);
            assert!(process_ok);
            assert!(exact_one, "zero-test child cannot calibrate this control");
            assert_eq!(offered.kind, HostEventKind::SendOutcome);
            assert!(
                !offered.slot_checked_out,
                "tail must remain actually Offered before stop"
            );
            assert!(
                stopped.is_ok(),
                "healthy tail completion must not use a generic incomplete result"
            );
            assert!(real_sockets_joined);
            assert_eq!(
                records.len(),
                4,
                "the actual final send must be COLLECTED, never discarded by stop"
            );
            let prepared = &records[2];
            let tail = &records[3];
            assert_eq!(prepared.kind, HostEventKind::PreparedSend);
            assert_eq!(tail.kind, HostEventKind::SendOutcome);
            assert_eq!(tail.key, offered.key);
            assert_eq!(tail.prepared, Some(prepared.key));
            assert_eq!(tail.outcome, Some(SendOutcome::Completed));
            assert!(
                tail.slot_checked_out,
                "successful SAME-run cache precedes ACK"
            );
            assert!(final_slot.is_none());
            TailEvidence {
                source_case,
                offered: offered.key,
                collected: tail.key,
                prepared: prepared.key,
                outcome_prepared: tail.prepared,
                child_status,
            }
        });
        self.evidence = Some(evidence);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_child_exit_cannot_discard_final_send_outcome_before_collect_and_join() {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut probe = TailProbe { evidence: None };
    let report = tokio::task::block_in_place(|| {
        run_configured_with_installed_client_adapter(kit.path(), &configuration(), &mut probe)
    })
    .unwrap();
    let evidence = probe.evidence.expect(
        "actual canonical callback must complete child/host cleanup and all intended tail assertions",
    );
    assert_eq!(evidence.source_case, TailCase::SingleFileExplicitCompanion);
    assert_eq!(evidence.child_status, Some(0));
    assert_eq!(evidence.collected, evidence.offered);
    assert_eq!(evidence.outcome_prepared, Some(evidence.prepared));
    assert!(!report.qualified());
    assert!(!report.to_json().contains("client-process-measured"));
}

mod natural_publisher_tests;

mod source_seal_tests;
