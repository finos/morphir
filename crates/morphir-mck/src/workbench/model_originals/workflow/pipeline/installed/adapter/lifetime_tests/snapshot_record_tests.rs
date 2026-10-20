//! Unit DATA through the genuine prepared callback; no filesystem/host proof.
use super::*;
#[derive(Clone, Copy)]
enum EntryKind {
    Directory,
    File,
}
struct SnapshotProbe {
    records: u64,
    kind: EntryKind,
    entered: bool,
}
impl InstalledClientAdapter for SnapshotProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.entered = true;
        run.begin_snapshot(InstalledSnapshot::Destination, 8, "/unit-snapshot")
            .unwrap();
        let entry = |run: &mut InstalledClientRun<'_>, path: &str| match self.kind {
            EntryKind::Directory => {
                run.record_snapshot_directory(InstalledSnapshot::Destination, path)
            }
            EntryKind::File => run.record_snapshot_file(InstalledSnapshot::Destination, path, b"x"),
        };
        if self.records == 1 {
            entry(&mut run, "first").unwrap();
            assert_eq!(run.installed_observation_usage().records(), 1);
        }
        let before = run.installed_observation_usage();
        assert_eq!(
            entry(&mut run, "refused"),
            Err(InstalledAdapterError::ObservationIncomplete)
        );
        assert_eq!(run.installed_observation_usage().records(), self.records);
        assert_eq!(
            run.installed_observation_usage().retained_bytes(),
            before.retained_bytes(),
            "record permission precedes path/hash/copy/growth"
        );
        assert_eq!(
            run.installed_observation_usage().byte_visits(),
            before.byte_visits()
        );
        assert!(
            matches!(run.receiving.ready(),Err(InstalledObservationError::Resource{kind:InstalledObservationResource::Records,limit,used,requested:1})if *limit==self.records&&*used==self.records)
        );
        let summary = run.attempt.fault.as_ref().unwrap().summary();
        assert_eq!(summary.phase, "installed-observation");
        assert_eq!(summary.code, "installed-observation-refused");
        assert!(run.prepare_snapshot_read(1).is_err());
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn check_snapshot_records(records: u64) {
    for kind in [EntryKind::Directory, EntryKind::File] {
        let kit = tempfile::tempdir().unwrap();
        std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
        let raw=serde_json::json!({"kind":"model-originals-installed-client","checker":serde_json::from_str::<serde_json::Value>(CHECKER).unwrap(),"observation":{"source":{"attempts":8192,"readCalls":8192,"returnedBytes":67108864,"files":16},"workers":{"attempts":64,"updates":8192},"host":{"updates":8192}},"privateRecord":{"retainedBytes":67108864},"installedObservation":{"rpcFrames":"checker-capture","retainedBytes":16777216,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":16777216,"byteVisits":67108864,"records":records}}).to_string();
        let config = RunConfiguration::from_json(&raw).unwrap();
        let mut probe = SnapshotProbe {
            records,
            kind,
            entered: false,
        };
        let report =
            run_configured_with_installed_client_adapter(kit.path(), &config, &mut probe).unwrap();
        assert!(probe.entered);
        assert!(!report.qualified());
    }
}
#[test]
fn snapshot_zero_records_refuses_before_retained_growth() {
    check_snapshot_records(0)
}
#[test]
fn snapshot_one_record_is_cumulative_without_refund() {
    check_snapshot_records(1)
}
