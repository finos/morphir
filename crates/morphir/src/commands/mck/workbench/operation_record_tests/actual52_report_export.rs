//! Explicit artifact production with the real fixture, not replay acceptance.
use super::*;
use crate::commands::ui::installed_mck::TestConsumerAckCutoff;

#[test]
#[ignore = "explicit exact52 inputs and output directory; preserves genuine reports for reader controls"]
fn export_actual52_reader_control_reports() {
    let directory = input("MORPHIR_MCK_OPERATION_REPORT_EXPORT_DIR");
    std::fs::create_dir(&directory).expect("new immutable report directory");
    for (target, name) in [(Target::Node, "node"), (Target::Native, "native")] {
        for (cutoff, suffix) in [
            (None, "healthy"),
            (Some(TestConsumerAckCutoff::Release), "release-ack-loss"),
            (Some(TestConsumerAckCutoff::Commit), "commit-ack-loss"),
        ] {
            let mut fixture = Actual52::prepare(target);
            let mut adapter = fixture.adapter();
            if let Some(cutoff) = cutoff {
                adapter = adapter.test_with_consumer_ack_cutoff(cutoff);
            }
            let report = fixture.run(&mut adapter);
            assert_eq!(
                adapter.test_consumer_ack_cut_count(),
                usize::from(cutoff.is_some())
            );
            let text = report.to_json();
            let saved: Value = serde_json::from_str(&text).unwrap();
            assert_eq!(saved["formatVersion"], "0.1.0-draft.31");
            assert_eq!(saved["qualified"], false);
            assert_eq!(saved["records"].as_array().unwrap().len(), 24);
            let evidence = &saved["records"][0]["evidence"];
            if cutoff.is_some() {
                assert_eq!(evidence["kind"], "attempt-failed");
                assert_eq!(evidence["consumerFailure"]["kind"], "recorded");
                assert_eq!(evidence["consumerFailure"]["context"]["kind"], "prefix");
                assert_eq!(
                    evidence["consumerFailure"]["operation"]["completion"]["kind"],
                    "interrupted"
                );
            } else {
                assert_eq!(evidence["kind"], "client-process-measured");
                assert_eq!(
                    evidence["measurement"]["consumerObservation"]["completion"]["kind"],
                    "drained"
                );
            }
            // fixture.run returned only after the real host/process/readers
            // cleanup. These bytes remain DATA and currently fail replay.
            std::fs::write(directory.join(format!("{name}-{suffix}.json")), text).unwrap();
        }
    }
}
