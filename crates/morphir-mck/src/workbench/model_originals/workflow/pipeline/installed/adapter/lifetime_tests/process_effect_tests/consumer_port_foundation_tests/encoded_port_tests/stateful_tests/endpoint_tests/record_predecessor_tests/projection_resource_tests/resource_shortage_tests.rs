//! Additional SAME-owner source-first refusal boundaries, no endpoint effects.
use super::*;
#[derive(Clone, Copy)]
enum Shortage {
    ReceivingVisits,
    DecoderSlots,
}
struct ShortProbe {
    which: Shortage,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for ShortProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        activate(
            &mut run,
            &self.owner,
            Instant::now() + Duration::from_secs(10),
        );
        let policy: serde_json::Value = serde_json::from_str(V3).unwrap();
        let limits = Limits {
            max_frame: 64,
            stderr_capture: 64,
            ..Limits::DEFAULT
        };
        let requirements = run.test_consumer_output_requirements(limits).unwrap();
        let r = requirements.test_report_limit();
        let d = requirements.test_diagnostic_bytes();
        let w = limits
            .max_frame
            .checked_add(limits.stderr_capture)
            .unwrap()
            .checked_add(r.checked_mul(8).unwrap())
            .unwrap()
            .checked_add(20)
            .unwrap()
            .checked_add(d)
            .unwrap();
        match self.which {
            Shortage::ReceivingVisits => {
                let limit = policy["installedObservation"]["byteVisits"]
                    .as_u64()
                    .unwrap();
                let left = limit - run.installed_observation_usage().byte_visits();
                run.receiving
                    .reserve_span(
                        InstalledObservationResource::ByteVisits,
                        usize::try_from(left - u64::try_from(w - 1).unwrap()).unwrap(),
                    )
                    .unwrap();
                let before = run.installed_observation_usage();
                let result = run.test_prepare_consumer_output(limits);
                let refused = result.is_err();
                drop(result);
                assert!(
                    refused,
                    "receiving ByteVisits W-1 must refuse before actual output Vec allocation"
                );
                let extra = w.checked_sub(r.checked_add(d).unwrap()).unwrap();
                assert!(
                    matches!(run.receiving.ready(),Err(InstalledObservationError::Resource{kind:InstalledObservationResource::ByteVisits,requested,..})if *requested==extra as u64)
                );
                assert_eq!(
                    run.installed_observation_usage().retained_bytes() - before.retained_bytes(),
                    (r + d) as u64,
                    "preceding storage reservation stays spent; it is not an output allocation"
                );
                assert!(matches!(
                    run.revoker.consumer_ports,
                    ConsumerRegistration::Unprepared
                ));
            }
            Shortage::DecoderSlots => {
                let limit = policy["checker"]["decode"]["slots"].as_u64().unwrap() as usize;
                run.decode
                    .slots(limit - run.decode.usage().slots - 2)
                    .unwrap();
                let receiving = run.installed_observation_usage();
                let before = run.decode.usage();
                let result = run.test_prepare_consumer_output(limits);
                let refused = result.is_err();
                drop(result);
                assert!(
                    refused,
                    "two slots cannot issue three output/prefix-buffer permissions"
                );
                assert_eq!(
                    run.decode.ready(),
                    Err(DecodeError::Work(OperandResource::Slots))
                );
                assert_eq!(run.decode.usage(), before);
                assert_eq!(run.installed_observation_usage(), receiving);
            }
        }
        let receiving = run.installed_observation_usage();
        let decode = run.decode.usage();
        assert!(run.test_prepare_consumer_output(limits).is_err());
        assert_eq!(run.installed_observation_usage(), receiving);
        assert_eq!(run.decode.usage(), decode);
        assert!(matches!(
            run.revoker.consumer_ports,
            ConsumerRegistration::Unprepared
        ));
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn shortage(which: Shortage) {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), CASES).unwrap();
    let mut policy: serde_json::Value = serde_json::from_str(V3).unwrap();
    policy["consumerObservation"] =
        serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
    let mut probe = ShortProbe {
        which,
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
fn output_reservation_refuses_receiving_visit_shortage_and_retry_spends_nothing() {
    shortage(Shortage::ReceivingVisits);
}
#[test]
fn output_reservation_refuses_decoder_slot_shortage_before_byte_work_and_is_sticky() {
    shortage(Shortage::DecoderSlots);
}
