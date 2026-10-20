//! Actual host compatibility: L-1 refuses, L retains known UTF8 by one copy.
use super::*;
const REQUEST: &str = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"morphir.session.initialize\",\"params\":{\"protocolVersion\":1,\"sessionId\":\"same-session-spelling\"}}";
#[derive(Clone, Copy)]
enum CallerWork {
    InsufficientCopy,
    ExactCopy,
}
struct Probe {
    work: CallerWork,
    retained: Option<bool>,
    visits: Option<(u64, u64)>,
}
impl InstalledClientAdapter for Probe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        let observed = tokio::runtime::Handle::current().block_on(async {
            let mut host = LiveHost::new(&mut run, None).await;
            let (mut socket, _) = connect(&mut host, &mut run).await;
            assert_eq!(run.installed_observation_usage().byte_visits(), 0);
            socket.send(Message::Text(REQUEST.into())).await.unwrap();
            let pending = tokio::time::timeout(WAIT, host.events.next())
                .await
                .unwrap()
                .unwrap();
            assert_eq!(pending.kind(), HostEventKind::ReceivedText);
            pending.with_text(|raw| assert_eq!(raw, REQUEST)).unwrap();
            let result = pending.retain(&mut run);
            let before_getters = run.installed_observation_usage().byte_visits();
            if let Ok(fact) = &result {
                assert_eq!(fact.body(), Some(REQUEST));
                assert_eq!(fact.body(), Some(REQUEST));
            }
            let after_getters = run.installed_observation_usage().byte_visits();
            let retained = result.is_ok();
            drop(result);
            drop(socket);
            host.stop().await;
            (retained, (before_getters, after_getters))
        });
        self.retained = Some(observed.0);
        self.visits = Some(observed.1);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn caller_configuration(work: CallerWork) -> RunConfiguration {
    let visits = match work {
        CallerWork::InsufficientCopy => REQUEST.len() - 1,
        CallerWork::ExactCopy => REQUEST.len(),
    };
    RunConfiguration::from_json(&json!({"kind":"model-originals-installed-client","checker":serde_json::from_str::<Value>(CHECKER).unwrap(),
        "observation":{"source":{"attempts":8192,"readCalls":8192,"returnedBytes":67108864,"files":16},"workers":{"attempts":64,"updates":8192},"host":{"updates":8192}},
        "privateRecord":{"retainedBytes":67108864},
        "installedObservation":{"rpcFrames":"checker-capture","retainedBytes":16777216,"stdoutPrefixBytes":1048576,"stderrPrefixBytes":1048576,"snapshotReadBytes":16777216,"byteVisits":visits,"records":8192}
    }).to_string()).unwrap()
}
#[tokio::test(flavor = "multi_thread")]
async fn actual_host_known_utf8_text_keeps_exact_copy_budget_and_borrowed_getters() {
    for work in [CallerWork::InsufficientCopy, CallerWork::ExactCopy] {
        let kit = tempfile::tempdir().unwrap();
        std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
        let mut probe = Probe {
            work,
            retained: None,
            visits: None,
        };
        let report = tokio::task::block_in_place(|| {
            run_configured_with_installed_client_adapter(
                kit.path(),
                &caller_configuration(probe.work),
                &mut probe,
            )
        })
        .unwrap();
        assert!(!report.qualified());
        match work {
            CallerWork::InsufficientCopy => {
                assert_eq!(
                    probe.retained,
                    Some(false),
                    "L-1 cannot retain the independently fixed L-byte actual frame"
                );
                assert!(
                    report.to_json().contains("installed-observation-refused"),
                    "real receiving work fault wins over generic adapter failure"
                );
            }
            CallerWork::ExactCopy => {
                assert_eq!(probe.retained, Some(true));
                assert_eq!(
                    probe.visits,
                    Some((REQUEST.len() as u64, REQUEST.len() as u64))
                );
                assert!(
                    report
                        .to_json()
                        .contains("installed-observation-incomplete")
                );
            }
        }
    }
}
