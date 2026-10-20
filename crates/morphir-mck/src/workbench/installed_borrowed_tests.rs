//! Source-first public borrowed-driver controls. No host or successful DATA.
//! Mount as a new Workbench test child, preserving all original controls.
use super::model_originals::installed::{
    InstalledAdapterError, InstalledClientAction, InstalledClientAdapter,
    InstalledClientMeasurements, InstalledClientRun, InstalledCommand, InstalledFixtureNode,
};
use super::{
    AdapterProtocol, Operation, Report, RunConfiguration, check_report_configured,
    run_configured_with_installed_client_adapter, run_configured_with_native_adapter,
    run_configured_with_session_factory,
};
use crate::transport::{Limits, TransportError};
use std::cell::Cell;
use std::time::Duration;

const POLICY: &str = include_str!("installed_borrowed_controls/installed-policy.json");
const ZERO: &str = include_str!("installed_borrowed_controls/zero-installed-policy.json");
const CASES: &[u8] =
    include_bytes!("model_originals/workflow/pipeline/installed_client_controls/cases24.json");
const RECORD: &[u8] = include_bytes!("installed_borrowed_controls/private-record-474.json");
const ID: &str = "single-file-explicit-companion-preserves-opaque-bytes";
const WORKSPACE: &[u8; 35] = b"[workspace]\nmembers=['packages/*']\n";

fn kit(raw: &[u8]) -> tempfile::TempDir {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), raw).unwrap();
    root
}
fn configured(raw: &str) -> RunConfiguration {
    RunConfiguration::from_json(raw).unwrap()
}
fn data(report: &Report) -> serde_json::Value {
    serde_json::from_str(&report.to_json()).unwrap()
}
fn summary(report: &Report, phase: &str, code: &str) {
    assert!(!report.qualified());
    let actual = data(report);
    assert_eq!(actual["errors"].as_array().unwrap().len(), 1);
    assert_eq!(actual["errors"][0]["phase"], phase);
    assert_eq!(actual["errors"][0]["code"], code);
    assert_eq!(actual["records"][0]["caseId"], ID);
    assert_eq!(actual["records"][0]["evidence"]["kind"], "attempt-failed");
    assert_eq!(actual["records"][0]["evidence"]["failureIndex"], 0);
    assert_eq!(actual["records"].as_array().unwrap().len(), 24);
    for row in &actual["records"].as_array().unwrap()[1..] {
        assert_eq!(row["evidence"]["kind"], "not-attempted");
        assert_eq!(row["evidence"]["priorFailureIndex"], 0);
    }
    assert!(
        !report
            .to_json()
            .contains("\"kind\":\"client-process-measured\"")
    );
}
enum Probe {
    Views,
    Refuse,
    RecipeExact,
    RecipeOneLess,
    RecordExact,
    RecordOneLess,
    Prefixes,
}
struct Adapter {
    probe: Probe,
    calls: usize,
}
impl Adapter {
    fn new(probe: Probe) -> Self {
        Self { probe, calls: 0 }
    }
}
impl InstalledClientAdapter for Adapter {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.calls += 1;
        assert_eq!(run.source().case_id(), ID);
        assert_eq!(run.source().original_packet(), "inventory35");
        assert_eq!(run.source().original_id(), ID);
        assert_eq!(run.source().run_index(), 0);
        assert_eq!(run.source().operation(), Operation::ModelOriginalsClient);
        match self.probe {
            Probe::Refuse => return Err(InstalledAdapterError::ObservationIncomplete),
            Probe::Views => {
                let fixture = run.fixture();
                assert_eq!(fixture.module().as_str(), "packages/orders");
                let nodes: Vec<_> = fixture.nodes().collect();
                assert_eq!(nodes.len(), 6);
                let mut observed = Vec::new();
                for node in nodes {
                    match node {
                        InstalledFixtureNode::Literal { path, .. } => {
                            observed.push((path.as_str(), None))
                        }
                        InstalledFixtureNode::ByteSource { path, alias, .. } => {
                            observed.push((path.as_str(), Some(alias.as_str())))
                        }
                    }
                }
                assert_eq!(
                    observed,
                    [
                        ("morphir.toml", None),
                        ("packages/orders/morphir.toml", None),
                        (
                            ".morphir/out/packages/orders/compile.json",
                            Some("private-record")
                        ),
                        (
                            ".morphir/out/packages/orders/compile.dest/morphir-ir.json",
                            Some("source-bytes-0")
                        ),
                        (
                            ".morphir/out/packages/orders/compile.dest/notes/opaque.bin",
                            Some("source-bytes-1")
                        ),
                        (
                            ".morphir/out/packages/orders/compile.dest/unrelated.log",
                            None
                        ),
                    ]
                );
                let mut tags = Vec::new();
                let mut commands = Vec::new();
                for action in run.actions() {
                    match action {
                        InstalledClientAction::PrepareFixture => tags.push("prepare"),
                        InstalledClientAction::StartObservedHost => tags.push("host"),
                        InstalledClientAction::Run { command, arguments } => {
                            tags.push("run");
                            let argv: Vec<_> =
                                arguments.iter().map(|argument| argument.as_str()).collect();
                            commands.push((command, argv));
                        }
                        InstalledClientAction::Checkpoint { name } => tags.push(name),
                        InstalledClientAction::WriteSourceSelection => tags.push("source"),
                        InstalledClientAction::WriteProjectSelection => tags.push("project"),
                        InstalledClientAction::StopAndJoin => tags.push("stop"),
                    }
                }
                assert_eq!(
                    tags,
                    [
                        "prepare",
                        "host",
                        "run",
                        "client-connected",
                        "source",
                        "run",
                        "client-project-discovered",
                        "project",
                        "run",
                        "client-publication-finished",
                        "stop",
                        "client-and-host-joined"
                    ]
                );
                assert_eq!(
                    commands,
                    [
                        (
                            InstalledCommand::Connect,
                            vec![
                                "connected",
                                "connect",
                                "$launchFile",
                                "--connection",
                                "$connectionFile",
                                "--connection-scope",
                                "models",
                                "--provider",
                                "workbench-http",
                                "--json",
                                "--node",
                                "$verifiedNodeRuntime"
                            ]
                        ),
                        (
                            InstalledCommand::List,
                            vec![
                                "connected",
                                "originals",
                                "$sourceSelectionFile",
                                "--list",
                                "--connection",
                                "$connectionFile",
                                "--provider",
                                "workbench-http",
                                "--json",
                                "--node",
                                "$verifiedNodeRuntime"
                            ]
                        ),
                        (
                            InstalledCommand::Publish,
                            vec![
                                "connected",
                                "originals",
                                "$projectSelectionFile",
                                "--connection",
                                "$connectionFile",
                                "--output",
                                "$destination",
                                "--provider",
                                "workbench-http",
                                "--json",
                                "--node",
                                "$verifiedNodeRuntime"
                            ]
                        ),
                    ]
                );
            }
            Probe::RecipeExact | Probe::RecipeOneLess => {
                let InstalledFixtureNode::Literal { path, bytes } =
                    run.fixture().nodes().next().unwrap()
                else {
                    panic!("source first literal workspace file")
                };
                assert_eq!(path.as_str(), "morphir.toml");
                match self.probe {
                    Probe::RecipeExact => {
                        let recipe = run.materialize_fixture_bytes(bytes).unwrap();
                        assert_eq!(recipe.byte_length(), 35);
                        let mut actual = [0; 35];
                        recipe.fill_window(0, &mut actual).unwrap();
                        assert_eq!(&actual, WORKSPACE);
                    }
                    _ => {
                        assert!(run.materialize_fixture_bytes(bytes).is_err());
                        assert!(run.materialize_fixture_bytes(bytes).is_err());
                    }
                }
            }
            Probe::RecordExact | Probe::RecordOneLess => {
                assert_eq!(
                    RECORD.len(),
                    474,
                    "installed original record; native237 remains separate"
                );
                let mut actual = Some(RECORD.to_vec());
                assert_eq!(
                    actual.as_ref().unwrap().capacity(),
                    474,
                    "independent unit allocation calibration"
                );
                let address = actual.as_ref().unwrap().as_ptr();
                assert_eq!(run.private_record_retention_usage().reserved_bytes(), 0);
                match self.probe {
                    Probe::RecordExact => {
                        // Type annotation requires the SAME existing receiver,
                        // never a second installed record ticket.
                        let ticket: super::model_originals::native::PrivateRecordAdoption<'_> = run
                            .prepare_private_record_adoption(actual.as_ref().unwrap())
                            .unwrap();
                        assert_eq!(ticket.usage().reserved_bytes(), 474);
                        let adopted = ticket.commit(actual.take().unwrap()).unwrap();
                        let super::model_originals::native::data::Bytes::Utf8 { text } = adopted
                        else {
                            panic!("actual same UTF8 allocation")
                        };
                        assert_eq!(text.as_str().as_ptr(), address);
                        assert_eq!(text.as_str().as_bytes(), RECORD);
                    }
                    _ => {
                        assert!(matches!(
                            run.prepare_private_record_adoption(actual.as_ref().unwrap()),
                            Err(
                                super::model_originals::native::PrivateRecordError::Capacity {
                                    limit: 473,
                                    used: 0,
                                    requested: 474
                                }
                            )
                        ));
                        assert_eq!(
                            actual.as_ref().unwrap().as_ptr(),
                            address,
                            "refusal before caller take"
                        );
                        assert_eq!(run.private_record_retention_usage().reserved_bytes(), 0);
                        let InstalledFixtureNode::Literal { bytes, .. } =
                            run.fixture().nodes().next().unwrap()
                        else {
                            panic!("first literal")
                        };
                        assert!(
                            run.materialize_fixture_bytes(bytes).is_err(),
                            "same record fault blocks subsequent recipe work"
                        );
                    }
                }
            }
            Probe::Prefixes => {
                let limits = |stdout, stderr| Limits {
                    max_frame: stdout,
                    stderr_capture: stderr,
                    request_timeout: Duration::from_secs(1),
                    session_timeout: Duration::from_secs(1),
                    exit_grace: Duration::from_secs(1),
                    shutdown_grace: Duration::from_secs(1),
                };
                run.reserve_process_prefixes(&limits(6, 4))
                    .unwrap()
                    .commit();
                run.reserve_process_prefixes(&limits(4, 2))
                    .unwrap()
                    .commit();
                assert_eq!(run.installed_observation_usage().stdout_prefix_bytes(), 10);
                assert_eq!(run.installed_observation_usage().stderr_prefix_bytes(), 6);
                let first = match run.reserve_process_prefixes(&limits(1, 0)) {
                    Err(error) => std::ptr::from_ref(error),
                    Ok(_) => {
                        panic!("third command permission must refuse, no actual spawn is attempted")
                    }
                };
                match run.prepare_snapshot_read(1) {
                    Err(error) => assert_eq!(std::ptr::from_ref(error), first),
                    Ok(_) => panic!("same exact first owner fault blocks later read permission"),
                }
                assert_eq!(run.installed_observation_usage().snapshot_read_bytes(), 0);
            }
        }
        Err(InstalledAdapterError::Cancelled)
    }
}

#[test]
fn borrowed_b01_installed_configuration_is_explicit_closed_and_zero_valid() {
    let positive = configured(POLICY);
    let limits = positive.installed_observation_limits().unwrap();
    assert_eq!(
        (
            limits.retained_bytes(),
            limits.stdout_prefix_bytes(),
            limits.stderr_prefix_bytes(),
            limits.snapshot_read_bytes(),
            limits.byte_visits(),
            limits.records()
        ),
        (4096, 10, 6, 8, 4096, 8)
    );
    assert!(
        positive.native_observation_limits().is_some(),
        "same ordinary host observer policy remains explicit"
    );
    assert_eq!(positive.adapter_protocol(), AdapterProtocol::ContentLength);
    let zero = configured(ZERO);
    let limits = zero.installed_observation_limits().unwrap();
    assert_eq!(
        (
            limits.retained_bytes(),
            limits.stdout_prefix_bytes(),
            limits.stderr_prefix_bytes(),
            limits.snapshot_read_bytes(),
            limits.byte_visits(),
            limits.records()
        ),
        (0, 0, 0, 0, 0, 0)
    );
    for raw in [
        include_str!("native_pipeline_controls/native-policy.json"),
        include_str!(
            "model_originals/workflow/pipeline/installed_client_controls/checker-policy.json"
        ),
        r#"{"kind":"historical"}"#,
    ] {
        assert!(configured(raw).installed_observation_limits().is_none());
    }
    let cases: Vec<String> = serde_json::from_str(include_str!(
        "installed_borrowed_controls/refused-policies.json"
    ))
    .unwrap();
    assert_eq!(cases.len(), 41);
    for raw in cases {
        assert!(RunConfiguration::from_json(&raw).is_err(), "{raw}");
    }
}

#[test]
fn borrowed_b02_real_prepared24_lends_safe_fixture_actions_and_typed_failure_only() {
    let root = kit(CASES);
    let mut adapter = Adapter::new(Probe::Views);
    let report = run_configured_with_installed_client_adapter(
        root.path(),
        &configured(POLICY),
        &mut adapter,
    )
    .unwrap();
    assert_eq!(adapter.calls, 1);
    summary(&report, "installed-cancelled", "installed-cancelled");
    let expected: Vec<String> =
        serde_json::from_str(include_str!("installed_borrowed_controls/ordered-ids.json")).unwrap();
    let actual = data(&report);
    assert_eq!(
        actual["records"]
            .as_array()
            .unwrap()
            .iter()
            .map(|row| row["caseId"].as_str().unwrap())
            .collect::<Vec<_>>(),
        expected.iter().map(String::as_str).collect::<Vec<_>>()
    );
}

#[test]
fn borrowed_b03_canonical_bad_source_or_work_permission_refuses_before_callback() {
    for raw in [
        include_bytes!(
            "model_originals/workflow/pipeline/installed_client_controls/wrong-role.json"
        )
        .as_slice(),
        include_bytes!(
            "model_originals/workflow/pipeline/installed_client_controls/wrong-run.json"
        )
        .as_slice(),
        include_bytes!(
            "model_originals/workflow/pipeline/installed_client_controls/wrong-original.json"
        )
        .as_slice(),
    ] {
        let root = kit(raw);
        let mut adapter = Adapter::new(Probe::Refuse);
        assert!(
            run_configured_with_installed_client_adapter(
                root.path(),
                &configured(POLICY),
                &mut adapter
            )
            .is_err()
        );
        assert_eq!(adapter.calls, 0);
    }
    for raw in [
        POLICY.replace("\"definitions\":1000000", "\"definitions\":0"),
        POLICY.replace("\"frameBytes\":1073741824", "\"frameBytes\":0"),
    ] {
        assert_ne!(raw, POLICY);
        let root = kit(CASES);
        let mut adapter = Adapter::new(Probe::Refuse);
        assert!(
            run_configured_with_installed_client_adapter(
                root.path(),
                &configured(&raw),
                &mut adapter
            )
            .is_err()
        );
        assert_eq!(adapter.calls, 0);
    }
}

struct NativeRefusal(usize);
impl super::model_originals::native::NativeOriginalAdapter for NativeRefusal {
    fn observe(
        &mut self,
        _: super::model_originals::native::NativeOriginalRun<'_>,
    ) -> Result<
        super::model_originals::native::NativeOriginalMeasurements,
        super::model_originals::native::NativeAdapterError,
    > {
        self.0 += 1;
        Err(super::model_originals::native::NativeAdapterError::ObservationIncomplete)
    }
}
#[test]
fn borrowed_b04_installed_native_and_external_entrypoints_never_cross_or_fall_back() {
    let root = kit(CASES);
    let selected = configured(POLICY);
    let factory = Cell::new(0);
    assert!(
        run_configured_with_session_factory(root.path(), &selected, || {
            factory.set(factory.get() + 1);
            Err(TransportError::Spawn(
                "forbidden actual external factory".into(),
            ))
        })
        .is_err()
    );
    assert_eq!(factory.get(), 0);
    let mut native = NativeRefusal(0);
    assert!(run_configured_with_native_adapter(root.path(), &selected, &mut native).is_err());
    assert_eq!(native.0, 0);
    for raw in [
        include_str!("native_pipeline_controls/native-policy.json"),
        include_str!(
            "model_originals/workflow/pipeline/installed_client_controls/checker-policy.json"
        ),
        r#"{"kind":"historical"}"#,
    ] {
        let mut adapter = Adapter::new(Probe::Refuse);
        assert!(
            run_configured_with_installed_client_adapter(
                root.path(),
                &configured(raw),
                &mut adapter
            )
            .is_err()
        );
        assert_eq!(adapter.calls, 0);
    }
}

#[test]
fn borrowed_b05_same_recipe_exact35_and_one_less_preserve_first_comparison_fault() {
    for (budget, probe, phase, code) in [
        (
            35,
            Probe::RecipeExact,
            "installed-cancelled",
            "installed-cancelled",
        ),
        (
            34,
            Probe::RecipeOneLess,
            "observation",
            "observation-refused",
        ),
    ] {
        let raw = POLICY.replace(
            "\"comparisonBytes\":1000000",
            &format!("\"comparisonBytes\":{budget}"),
        );
        assert_ne!(raw, POLICY);
        let root = kit(CASES);
        let mut adapter = Adapter::new(probe);
        let report = run_configured_with_installed_client_adapter(
            root.path(),
            &configured(&raw),
            &mut adapter,
        )
        .unwrap();
        assert_eq!(adapter.calls, 1);
        summary(&report, phase, code);
    }
}

#[test]
fn borrowed_b06_same_record_receiver_exact474_and_one_less_keep_allocation_and_first_fault() {
    for (limit, probe, code) in [
        (474, Probe::RecordExact, "installed-cancelled"),
        (473, Probe::RecordOneLess, "record-retention-capacity"),
    ] {
        let raw = POLICY.replace(
            "\"privateRecord\":{\"retainedBytes\":474}",
            &format!("\"privateRecord\":{{\"retainedBytes\":{limit}}}"),
        );
        let root = kit(CASES);
        let mut adapter = Adapter::new(probe);
        let report = run_configured_with_installed_client_adapter(
            root.path(),
            &configured(&raw),
            &mut adapter,
        )
        .unwrap();
        assert_eq!(adapter.calls, 1);
        let actual = data(&report);
        assert_eq!(actual["errors"].as_array().unwrap().len(), 1);
        assert_eq!(actual["errors"][0]["code"], code);
        assert!(!report.qualified());
    }
}

#[test]
fn borrowed_b07_command_permissions_share_one_owner_and_cannot_clear_first_fault() {
    let root = kit(CASES);
    let mut adapter = Adapter::new(Probe::Prefixes);
    let report = run_configured_with_installed_client_adapter(
        root.path(),
        &configured(POLICY),
        &mut adapter,
    )
    .unwrap();
    assert_eq!(adapter.calls, 1);
    summary(
        &report,
        "installed-observation",
        "installed-observation-refused",
    );
}

#[test]
fn borrowed_b08_failed_saved_report_never_reissues_adapter_or_upgrades_unproven_role() {
    let root = kit(CASES);
    let policy = configured(POLICY);
    let mut adapter = Adapter::new(Probe::Refuse);
    let report =
        run_configured_with_installed_client_adapter(root.path(), &policy, &mut adapter).unwrap();
    summary(
        &report,
        "installed-observation",
        "installed-observation-incomplete",
    );
    let saved = Report::from_json(&report.to_json()).unwrap();
    check_report_configured(root.path(), &saved, &policy).unwrap();
    assert_eq!(adapter.calls, 1);
    assert!(!saved.qualified());
    let raw = report.to_json();
    assert_eq!(raw.matches("\"qualified\":false").count(), 1);
    let forged =
        Report::from_json(&raw.replacen("\"qualified\":false", "\"qualified\":true", 1)).unwrap();
    assert!(check_report_configured(root.path(), &forged, &policy).is_err());
    assert_eq!(adapter.calls, 1);
    std::fs::write(root.path().join("cases.json"), [CASES, b" "].concat()).unwrap();
    assert!(check_report_configured(root.path(), &saved, &policy).is_err());
    assert_eq!(adapter.calls, 1);
}
