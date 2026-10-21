//! Prospective actual-process refusal controls. No encoded producer or facts.
//! Child of consumer_port_foundation_tests; its original bytes stay unchanged.
use super::*;

struct Kit {
    _held: tempfile::TempDir,
    directory: PathBuf,
    program: PathBuf,
    marker: PathBuf,
    configuration: RunConfiguration,
}
impl Kit {
    fn new() -> Self {
        let held = tempfile::tempdir().unwrap();
        let directory = held.path().canonicalize().unwrap();
        std::fs::write(directory.join("cases.json"), CASES).unwrap();
        let mut policy = foundation_policy();
        policy["consumerObservation"] =
            serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
        Self {
            program: PathBuf::from(
                std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
                    .expect("same explicit fresh actual MEP peer required"),
            )
            .canonicalize()
            .unwrap(),
            marker: directory.join("actual-supplement-entry.marker"),
            configuration: RunConfiguration::from_json(&policy.to_string()).unwrap(),
            directory,
            _held: held,
        }
    }
    fn arguments(&self) -> [OsString; 3] {
        [
            OsString::from("--adapter"),
            OsString::from("installed-consumer-port-foundation"),
            self.marker.as_os_str().to_owned(),
        ]
    }
    fn run(&self, adapter: &mut impl InstalledClientAdapter) {
        let report = run_configured_with_installed_client_adapter(
            &self.directory,
            &self.configuration,
            adapter,
        )
        .unwrap();
        assert!(!report.qualified());
    }
}
fn gate_owner() -> std::sync::Arc<TestGateOwner> {
    std::sync::Arc::new(TestGateOwner {
        gate: InvocationGate::dormant(),
    })
}
fn publish_command<'a>(
    kit: &'a Kit,
    arguments: &'a [OsString],
    environment: &'a [(OsString, OsString)],
) -> ConsumerProcessCommand<'a> {
    ConsumerProcessCommand {
        purpose: InstalledProcessPurpose::Canonical {
            action_index: 8,
            command: InstalledCommand::Publish,
        },
        program: &kit.program,
        arguments,
        directory: &kit.directory,
        environment,
        limits: Limits {
            max_frame: 131072,
            stderr_capture: 128,
            ..Limits::DEFAULT
        },
    }
}
// Always dispose an unexpected genuine child before any refusal assertion.
fn refusal_after_cleanup(
    result: Result<RunningInstalledProcess, InstalledAdapterError>,
    ports: InstalledConsumerPorts,
) -> bool {
    match result {
        Err(error) => {
            drop(ports);
            assert_eq!(error, InstalledAdapterError::ObservationIncomplete);
            true
        }
        Ok(mut process) => {
            drop(ports);
            let _ = process.request_termination();
            drop(actual_finish(process));
            false
        }
    }
}
struct ForeignSpawn<'a> {
    kit: &'a Kit,
    owner: std::sync::Arc<TestGateOwner>,
    pair: Option<(PreparedInstalledConsumerProcess, InstalledConsumerPorts)>,
    entered: bool,
}
impl InstalledClientAdapter for ForeignSpawn<'_> {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        let projection: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        let _token = run
            .issue_host_observation(std::sync::Arc::downgrade(&projection))
            .unwrap();
        run.bind_consumer_window(Instant::now() + Duration::from_secs(10))
            .unwrap();
        let (prepared, ports) = self.pair.take().unwrap();
        let refused = refusal_after_cleanup(run.spawn_prepared_consumer_process(prepared), ports);
        assert!(
            refused,
            "foreign invocation must refuse before actual spawn"
        );
        assert!(!self.kit.marker.exists());
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
struct PrepareForeign<'a> {
    kit: &'a Kit,
    owner: std::sync::Arc<TestGateOwner>,
    transfer_while_live: bool,
    escaped: Option<(PreparedInstalledConsumerProcess, InstalledConsumerPorts)>,
    entered: bool,
}
impl InstalledClientAdapter for PrepareForeign<'_> {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        let projection: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        let _token = run
            .issue_host_observation(std::sync::Arc::downgrade(&projection))
            .unwrap();
        let end = Instant::now() + Duration::from_secs(10);
        run.bind_consumer_window(end).unwrap();
        let arguments = self.kit.arguments();
        let pair = run
            .prepare_consumer_process(publish_command(self.kit, &arguments, &[]), end)
            .expect("real original invocation prepares before foreign handoff");
        if self.transfer_while_live {
            // Both original and foreign invocations are genuinely live here.
            // Revocation alone therefore cannot substitute for identity checking.
            let mut foreign = ForeignSpawn {
                kit: self.kit,
                owner: gate_owner(),
                pair: Some(pair),
                entered: false,
            };
            self.kit.run(&mut foreign);
            assert!(foreign.entered);
        } else {
            self.escaped = Some(pair);
        }
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[test]
fn foreign_live_and_callback_revoked_prepared_cannot_spawn() {
    for transfer_while_live in [true, false] {
        let kit = Kit::new();
        let mut first = PrepareForeign {
            kit: &kit,
            owner: gate_owner(),
            transfer_while_live,
            escaped: None,
            entered: false,
        };
        kit.run(&mut first);
        assert!(first.entered);
        if let Some(pair) = first.escaped.take() {
            let mut foreign = ForeignSpawn {
                kit: &kit,
                owner: gate_owner(),
                pair: Some(pair),
                entered: false,
            };
            kit.run(&mut foreign);
            assert!(foreign.entered);
        }
        assert!(!kit.marker.exists());
    }
}
struct Expiry<'a> {
    kit: &'a Kit,
    owner: std::sync::Arc<TestGateOwner>,
    extend_caller: bool,
    entered: bool,
}
impl InstalledClientAdapter for Expiry<'_> {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        let projection: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        let _token = run
            .issue_host_observation(std::sync::Arc::downgrade(&projection))
            .unwrap();
        let original_end = Instant::now() + Duration::from_secs(1);
        run.bind_consumer_window(original_end).unwrap();
        let caller_end = if self.extend_caller {
            original_end + Duration::from_secs(30)
        } else {
            original_end
        };
        let arguments = self.kit.arguments();
        let (prepared, ports) = run
            .prepare_consumer_process(publish_command(self.kit, &arguments, &[]), caller_end)
            .expect("prepare while original bound window is genuinely live");
        while Instant::now() < original_end {
            std::thread::sleep(original_end.saturating_duration_since(Instant::now()));
        }
        let refused = refusal_after_cleanup(run.spawn_prepared_consumer_process(prepared), ports);
        assert!(
            refused,
            "expired original end must refuse despite later caller end"
        );
        assert!(!self.kit.marker.exists());
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[test]
fn prepared_expiry_is_rechecked_and_later_caller_cannot_extend_original_end() {
    for extend_caller in [false, true] {
        let kit = Kit::new();
        let mut probe = Expiry {
            kit: &kit,
            owner: gate_owner(),
            extend_caller,
            entered: false,
        };
        kit.run(&mut probe);
        assert!(probe.entered);
        assert!(!kit.marker.exists());
    }
}
struct Reserved<'a> {
    kit: &'a Kit,
    owner: std::sync::Arc<TestGateOwner>,
    key: &'static str,
    entered: bool,
}
impl InstalledClientAdapter for Reserved<'_> {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        let projection: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        let _token = run
            .issue_host_observation(std::sync::Arc::downgrade(&projection))
            .unwrap();
        let end = Instant::now() + Duration::from_secs(10);
        run.bind_consumer_window(end).unwrap();
        let arguments = self.kit.arguments();
        let environment = [(OsString::from(self.key), OsString::from("999"))];
        let before = run.installed_observation_usage();
        let refused = match run
            .prepare_consumer_process(publish_command(self.kit, &arguments, &environment), end)
        {
            Err(error) => {
                assert_eq!(error, InstalledAdapterError::ObservationIncomplete);
                true
            }
            Ok((prepared, ports)) => {
                drop(prepared);
                drop(ports);
                false
            }
        };
        assert!(
            refused,
            "caller cannot supply a reserved inherited-FD selector"
        );
        assert!(
            matches!(
                run.receiving.ready(),
                Err(InstalledObservationError::LayoutMismatch)
            ),
            "reserved selector must be the actual typed refusal"
        );
        assert_eq!(
            run.installed_observation_usage().retained_bytes(),
            before.retained_bytes(),
            "reject before command/consumer storage allocation"
        );
        assert_eq!(
            run.installed_observation_usage().records(),
            before.records(),
            "reject before process or consumer record permission"
        );
        assert!(!self.kit.marker.exists());
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
#[test]
fn reserved_role_environment_collisions_refuse_preparation() {
    for key in [
        "MORPHIR_PRIVATE_CONSUMER_OUTER_FD",
        "MORPHIR_PRIVATE_CONSUMER_HELPER_FD",
    ] {
        let kit = Kit::new();
        let mut probe = Reserved {
            kit: &kit,
            owner: gate_owner(),
            key,
            entered: false,
        };
        kit.run(&mut probe);
        assert!(probe.entered);
        assert!(!kit.marker.exists());
    }
}
