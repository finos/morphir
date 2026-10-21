//! Actual endpoint projection controls, synthetic association DATA only.
use super::*;
#[derive(Clone, Copy)]
enum Case {
    OpenAndFact,
    Association,
    Close,
}
struct Probe {
    case: Case,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for Probe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        let end = Instant::now() + Duration::from_secs(10);
        activate(&mut run, &self.owner, end);
        let root = tempfile::tempdir().unwrap();
        let program = std::env::current_exe().unwrap();
        let strategy = if matches!(self.case, Case::Association) {
            FixtureStrategy::NativeExecutable
        } else {
            FixtureStrategy::NodePackage
        };
        let (prepared, mut ports) =
            prepare_unit_ports(&mut run, &program, root.path(), end, strategy);
        let outer = prepared.test_child_handle(ConsumerProducerRole::Outer);
        let helper = prepared.test_child_handle(ConsumerProducerRole::TransferHelper);
        send(outer, &framed(OPEN));
        let mut ticket = receive(&mut run, &mut ports, ConsumerProducerRole::Outer);
        let open = run.test_terminal_kind(&ports, ConsumerProducerRole::Outer);
        complete_ack(&mut run, &mut ports, &mut ticket, outer, 0);
        let actual = match self.case {
            Case::OpenAndFact => {
                send(outer, &commit(1));
                let _ticket = receive(&mut run, &mut ports, ConsumerProducerRole::Outer);
                run.test_terminal_kind(&ports, ConsumerProducerRole::Outer)
            }
            Case::Association => {
                send(helper, &framed(OPEN));
                assert!(matches!(
                    run.poll_consumer_frame(&mut ports, ConsumerProducerRole::TransferHelper)
                        .unwrap(),
                    ConsumerReceiveProgress::AwaitingAssociation
                ));
                run.test_terminal_kind(&ports, ConsumerProducerRole::TransferHelper)
            }
            Case::Close => {
                send(outer,&framed(br#"{"kind":"close","version":"0.1.0-draft.1","sequence":1,"attemptedHooks":0,"startedFactFrames":0,"retainedBusinessFacts":0,"helper":{"kind":"in-process"}}"#));
                let _ticket = receive(&mut run, &mut ports, ConsumerProducerRole::Outer);
                run.test_terminal_kind(&ports, ConsumerProducerRole::Outer)
            }
        };
        // No child is spawned in these transport DATA controls. Resolve the actual
        // endpoint owners before evaluating the projection oracles.
        drop(ports);
        drop(prepared);
        assert_eq!(open, "receiving", "an actual retained Open is not a Close");
        assert_eq!(
            actual,
            if matches!(self.case, Case::Close) {
                "close-retained"
            } else {
                "receiving"
            }
        );
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn exercise(case: Case) {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), CASES).unwrap();
    let mut policy:serde_json::Value=serde_json::from_str(include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/src/workbench/model_originals/workflow/pipeline/installed_client_tests/sealed_claims_controls/checker-policy-v3.json"))).unwrap();
    policy["consumerObservation"] =
        serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
    let mut probe = Probe {
        case,
        entered: false,
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
    };
    let report = run_configured_with_installed_client_adapter(
        root.path(),
        &RunConfiguration::from_json(&policy.to_string()).unwrap(),
        &mut probe,
    )
    .unwrap();
    assert!(probe.entered);
    assert!(!report.qualified());
}
#[test]
fn retained_open_and_business_fact_do_not_claim_a_retained_close() {
    exercise(Case::OpenAndFact)
}
#[test]
fn helper_open_awaiting_association_is_not_a_retained_close() {
    exercise(Case::Association)
}
#[test]
fn genuine_retained_close_keeps_its_distinct_terminal_projection() {
    exercise(Case::Close)
}
