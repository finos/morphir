//! Formatting/adoption DATA only. No process, fact, source or report issuer.
use super::*;
struct PrefixProbe {
    bytes: Option<Vec<u8>>,
    expected: serde_json::Value,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for PrefixProbe {
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
        let bytes = self.bytes.take().unwrap();
        let pointer = bytes.as_ptr();
        let capacity = bytes.capacity();
        let expected_bytes = bytes.clone(); // test setup snapshot, no authority
        let ticket = run
            .test_prepare_consumer_output(Limits {
                max_frame: 64,
                stderr_capture: 64,
                ..Limits::DEFAULT
            })
            .unwrap();
        let receiving = run.installed_observation_usage();
        let decoder = run.decode.usage();
        // The cfgtest DATA-only result has no route to Finished, live record,
        // ports, invocation, process status, host/source seal or an ACK ticket.
        let view = run.test_adopt_consumer_prefix_data(ticket, bytes).unwrap();
        assert_eq!(view.test_bytes(), expected_bytes);
        assert_eq!(view.test_bytes().as_ptr(), pointer);
        assert_eq!(view.test_raw_capacity(), capacity);
        assert_eq!(
            view.test_encode_with_reserved_writer().unwrap(),
            self.expected
        );
        assert_eq!(run.installed_observation_usage(), receiving);
        assert_eq!(run.decode.usage(), decoder);
        drop(view);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[test]
fn utf8_and_invalid_utf8_prefix_data_keep_exact_wire_and_owned_buffer() {
    for (bytes, expected) in [
        (
            "α\0".as_bytes().to_vec(),
            serde_json::json!({"kind":"utf8","text":"α\0"}),
        ),
        (
            vec![0xff, 0, 0x22],
            serde_json::json!({"kind":"hex","hex":"ff0022"}),
        ),
    ] {
        let root = tempfile::tempdir().unwrap();
        std::fs::write(root.path().join("cases.json"), CASES).unwrap();
        let mut policy: serde_json::Value = serde_json::from_str(V3).unwrap();
        policy["consumerObservation"] =
            serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
        let mut probe = PrefixProbe {
            bytes: Some(bytes),
            expected,
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
}
