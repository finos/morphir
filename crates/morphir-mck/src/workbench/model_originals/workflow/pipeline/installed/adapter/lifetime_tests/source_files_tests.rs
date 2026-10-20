//! Receiving DATA only. No SDK witness, source-seal or joined-worker claim.
use super::*;
use crate::workbench::model_originals::native::data::{self, FileRole};

struct SourceFilesProbe {
    exhaust_storage: bool,
    completed: bool,
}
impl InstalledClientAdapter for SourceFilesProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.completed);
        let fixture = run.fixture();
        let rows = || {
            fixture.witnesses().map(|(role, path)| {
                (
                    role,
                    path,
                    data::ReadCounts {
                        attempts: data::ObservedCount(0),
                        read_calls: data::ObservedCount(0),
                        returned_bytes: data::ObservedCount(0),
                    },
                )
            })
        };
        if self.exhaust_storage {
            // Spend the remaining explicit SAME owner allowance. This is unit
            // phase isolation, not a fresh budget or actual filesystem work.
            let limit = configuration()
                .installed_observation_limits()
                .unwrap()
                .retained_bytes();
            let remaining = limit - run.receiving.usage().retained_bytes();
            run.receiving
                .reserve_span(
                    InstalledObservationResource::RetainedBytes,
                    usize::try_from(remaining).unwrap(),
                )
                .unwrap();
            assert!(matches!(
                run.retain_source_files(rows()),
                Err(InstalledAdapterError::ObservationIncomplete)
            ));
            assert!(
                matches!(run.receiving.ready(), Err(InstalledObservationError::Resource { kind: InstalledObservationResource::RetainedBytes, limit: actual, .. }) if *actual == limit)
            );
            let receiving = run.receiving.usage();
            let decode = run.decode.usage();
            let comparison = run.comparison.usage();
            assert!(matches!(
                run.retain_source_files(rows()),
                Err(InstalledAdapterError::ObservationIncomplete)
            ));
            assert_eq!(run.receiving.usage(), receiving);
            assert_eq!(run.decode.usage(), decode);
            assert_eq!(run.comparison.usage(), comparison);
            assert!(run.attempt.fault.is_some());
        } else {
            let before = run.receiving.usage();
            let files = run.retain_source_files(rows()).unwrap();
            assert_eq!(files.as_slice().len(), 3);
            for (file, (role, path)) in files.as_slice().iter().zip(fixture.witnesses()) {
                assert_eq!(file.role, role);
                assert_eq!(file.path.as_str(), path.as_str());
                assert_eq!(file.reads.attempts.0, 0);
                assert_eq!(file.reads.read_calls.0, 0);
                assert_eq!(file.reads.returned_bytes.0, 0);
            }
            assert!(run.receiving.usage().retained_bytes() > before.retained_bytes());
            assert_eq!(files.as_slice()[0].role, FileRole::CompileRecord);
        }
        self.completed = true;
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn exercise_source_files(exhaust_storage: bool) {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut probe = SourceFilesProbe {
        exhaust_storage,
        completed: false,
    };
    let report =
        run_configured_with_installed_client_adapter(kit.path(), &configuration(), &mut probe)
            .unwrap();
    assert!(probe.completed);
    assert!(!report.qualified());
}
#[test]
fn source_file_data_retains_existing_validated_role_paths_with_same_receiving_owner() {
    exercise_source_files(false);
}
#[test]
fn source_file_data_storage_refusal_latches_and_retry_cannot_spend_again() {
    exercise_source_files(true);
}
