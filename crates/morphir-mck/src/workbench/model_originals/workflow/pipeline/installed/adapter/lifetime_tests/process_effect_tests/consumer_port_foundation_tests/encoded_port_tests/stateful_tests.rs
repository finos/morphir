//! SYNTHETIC association DATA matched to actual funded unit CommandSpecs.
//! No package/runtime/source authenticity, child launch or report qualification.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::data;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::invocation::ConsumerRegistration;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::processes::consumer::deadline::Timebase;
use std::{cell::Cell, ffi::OsStr, os::fd::BorrowedFd};
mod endpoint_tests;

#[derive(Clone, Copy)]
pub(super) enum FixtureStrategy {
    NodePackage,
    NativeExecutable,
}
struct Unit {
    program: PathBuf,
    directory: PathBuf,
    arguments: Vec<OsString>,
    implementation: data::ImplementationObservation,
    helper_arguments: [OsString; 3],
}
impl Unit {
    fn new(
        run: &mut InstalledClientRun<'_>,
        program: &Path,
        directory: &Path,
        strategy: FixtureStrategy,
    ) -> Self {
        let package = run.command_path(directory, "unit-package").unwrap();
        let entry = run.command_path(&package, "bin/morphir.js").unwrap();
        let helper = run
            .command_path(&package, "build-provider/originals.mjs")
            .unwrap();
        let launch = run.command_path(directory, "unit-launch").unwrap();
        let connection = run.command_path(directory, "unit-connection").unwrap();
        let source = run.command_path(directory, "unit-source").unwrap();
        let project = run.command_path(directory, "unit-project").unwrap();
        let config = run.command_path(directory, "unit-helper-config").unwrap();
        let InstalledClientAction::Run {
            command: InstalledCommand::Publish,
            arguments: source_arguments,
        } = run.actions().nth(8).unwrap()
        else {
            panic!("genuine compiled Publish required");
        };
        let mut arguments = run
            .vector(
                source_arguments.len()
                    + usize::from(matches!(strategy, FixtureStrategy::NodePackage))
                    + 2,
            )
            .unwrap();
        if matches!(strategy, FixtureStrategy::NodePackage) {
            arguments.push(run.copy_command_operand(entry.as_os_str()).unwrap());
        }
        // Same closed placeholder relation as installed_launch.rs253/379-410.
        // Unknown source operands refuse this TEST fixture, never gain semantics.
        for argument in source_arguments {
            let resolved = match argument.as_str() {
                "$launchFile" => launch.as_os_str(),
                "$connectionFile" => connection.as_os_str(),
                "$sourceSelectionFile" => source.as_os_str(),
                "$projectSelectionFile" => project.as_os_str(),
                "$destination" => OsStr::new("destination"),
                "$verifiedNodeRuntime" => program.as_os_str(),
                literal if !literal.starts_with('$') => OsStr::new(literal),
                _ => panic!("unknown compiled operand"),
            };
            arguments.push(run.copy_command_operand(resolved).unwrap());
        }
        arguments.push(
            run.copy_command_operand(OsStr::new("--originals-helper"))
                .unwrap(),
        );
        arguments.push(run.copy_command_operand(helper.as_os_str()).unwrap());
        let observed_launch = match strategy {
            FixtureStrategy::NodePackage => data::LaunchObservation::NodePackage {
                entry: run.observation_operand(entry.as_os_str()).unwrap(),
            },
            FixtureStrategy::NativeExecutable => data::LaunchObservation::NativeExecutable {
                program: run.observation_operand(program.as_os_str()).unwrap(),
                byte_length: data::Natural(0),
                sha256: data::ContentSha256::new([0; 32]),
            },
        };
        let implementation = data::ImplementationObservation::Observed {
            before_action: data::Natural(2),
            launch: observed_launch,
            runtime: data::RuntimeObservation {
                program: run.observation_operand(program.as_os_str()).unwrap(),
                byte_length: data::Natural(0),
                sha256: data::ContentSha256::new([0; 32]),
                version: data::VersionObservation::Unobserved {},
            },
            command_paths: data::CommandPaths {
                launch_file: run.observation_operand(launch.as_os_str()).unwrap(),
                connection_file: run.observation_operand(connection.as_os_str()).unwrap(),
                source_selection_file: run.observation_operand(source.as_os_str()).unwrap(),
                project_selection_file: run.observation_operand(project.as_os_str()).unwrap(),
                destination: run.observation_operand(OsStr::new("destination")).unwrap(),
            },
            package: data::PackageCensus {
                root: run.observation_operand(package.as_os_str()).unwrap(),
                entries: data::Items::new(Vec::new()).unwrap(),
                sha256: data::ContentSha256::new([0; 32]),
            },
            source: data::SourceAssociation {
                root: run.observation_operand(directory.as_os_str()).unwrap(),
                head: run
                    .observation_text("0000000000000000000000000000000000000000")
                    .unwrap(),
                object_format: data::ObjectFormat::Sha1,
                tracked_status: data::TrackedStatus::Unchanged,
                entries: data::Items::new(Vec::new()).unwrap(),
                sha256: data::ContentSha256::new([0; 32]),
            },
            metadata_tools: data::Items::new(Vec::new()).unwrap(),
        };
        Self {
            program: PathBuf::from(run.copy_command_operand(program.as_os_str()).unwrap()),
            directory: PathBuf::from(run.copy_command_operand(directory.as_os_str()).unwrap()),
            arguments,
            implementation,
            // Actual native originals_dispatch source has exactly this shape.
            // Config is synthetic DATA, not an assertion of C temp-file creation.
            helper_arguments: [
                run.copy_command_operand(helper.as_os_str()).unwrap(),
                run.copy_command_operand(OsStr::new("--morphir-originals-v1"))
                    .unwrap(),
                run.copy_command_operand(config.as_os_str()).unwrap(),
            ],
        }
    }
    fn command(&self) -> ConsumerProcessCommand<'_> {
        ConsumerProcessCommand {
            purpose: InstalledProcessPurpose::Canonical {
                action_index: 8,
                command: InstalledCommand::Publish,
            },
            program: &self.program,
            arguments: &self.arguments,
            directory: &self.directory,
            environment: &[],
            limits: Limits {
                max_frame: 131072,
                stderr_capture: 128,
                ..Limits::DEFAULT
            },
        }
    }
    fn prepare(
        &self,
        run: &mut InstalledClientRun<'_>,
        end: Instant,
    ) -> (PreparedInstalledConsumerProcess, InstalledConsumerPorts) {
        run.prepare_observed_consumer_process(self.command(), end, &self.implementation)
            .unwrap()
    }
    fn helper_started(&self, run: &mut InstalledClientRun<'_>) -> Vec<u8> {
        #[derive(serde::Serialize)]
        struct Launch<'a> {
            program: &'a data::OsOperand,
            arguments: [data::OsOperand; 3],
            directory: &'a data::OsOperand,
        }
        #[derive(serde::Serialize)]
        struct Started<'a> {
            kind: &'static str,
            version: &'static str,
            sequence: u64,
            launch: Launch<'a>,
        }
        let data::ImplementationObservation::Observed {
            runtime, source, ..
        } = &self.implementation
        else {
            unreachable!()
        };
        let arguments = [
            run.observation_operand(&self.helper_arguments[0]).unwrap(),
            run.observation_operand(&self.helper_arguments[1]).unwrap(),
            run.observation_operand(&self.helper_arguments[2]).unwrap(),
        ];
        // Test-only direct typed serialization, no Value/clone/reparse of DATA.
        framed(
            &serde_json::to_vec(&Started {
                kind: "helper-started",
                version: "0.1.0-draft.1",
                sequence: 1,
                launch: Launch {
                    program: &runtime.program,
                    arguments,
                    directory: &source.root,
                },
            })
            .unwrap(),
        )
    }
}
pub(super) fn prepare_unit_ports(
    run: &mut InstalledClientRun<'_>,
    program: &Path,
    directory: &Path,
    end: Instant,
    strategy: FixtureStrategy,
) -> (PreparedInstalledConsumerProcess, InstalledConsumerPorts) {
    Unit::new(run, program, directory, strategy).prepare(run, end)
}
fn no_ack(child: BorrowedFd<'_>) {
    assert!(matches!(
        rustix::io::read(child, &mut [0; 1]),
        Err(rustix::io::Errno::AGAIN)
    ));
}
fn ack(
    run: &mut InstalledClientRun<'_>,
    ports: &mut InstalledConsumerPorts,
    mut pending:crate::workbench::model_originals::workflow::pipeline::installed::adapter::processes::consumer::wire::ConsumerPendingAck,
    child: BorrowedFd<'_>,
    sequence: u64,
) {
    assert!(matches!(
        run.write_consumer_ack(ports, &mut pending).unwrap(),
        ConsumerAckProgress::Complete
    ));
    let mut received = [0; 256];
    let count = rustix::io::read(child, &mut received).unwrap();
    let payload =
        format!("{{\"kind\":\"retained\",\"version\":\"0.1.0-draft.1\",\"sequence\":{sequence}}}");
    assert_eq!(&received[..count], framed(payload.as_bytes()));
}
#[derive(Clone, Copy)]
enum StateExercise {
    Lane(FixtureStrategy),
    RefuseUnobserved,
    RefuseMismatch,
    RawNoLane,
    FixedDeadline,
}
struct StateProbe {
    which: StateExercise,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for StateProbe {
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
        let program = std::env::current_exe().unwrap().canonicalize().unwrap();
        let directory = tempfile::tempdir().unwrap();
        let strategy = match self.which {
            StateExercise::Lane(strategy) => strategy,
            _ => FixtureStrategy::NodePackage,
        };
        let mut unit = Unit::new(&mut run, &program, directory.path(), strategy);
        if matches!(
            self.which,
            StateExercise::RefuseUnobserved | StateExercise::RefuseMismatch
        ) {
            if matches!(self.which, StateExercise::RefuseUnobserved) {
                unit.implementation = data::ImplementationObservation::Unobserved {};
            } else {
                let wrong = run
                    .observation_operand(OsStr::new("/unit/foreign-runtime"))
                    .unwrap();
                let data::ImplementationObservation::Observed { runtime, .. } =
                    &mut unit.implementation
                else {
                    unreachable!()
                };
                runtime.program = wrong;
            }
            let result =
                run.prepare_observed_consumer_process(unit.command(), end, &unit.implementation);
            let refused = result.is_err();
            drop(result);
            assert!(
                refused,
                "unobserved or actual spec mismatch must refuse preparation"
            );
            assert!(
                matches!(run.revoker.consumer_ports, ConsumerRegistration::Unprepared),
                "refusal precedes endpoint registration"
            );
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        let (prepared, mut ports) = if matches!(self.which, StateExercise::RawNoLane) {
            run.prepare_consumer_process(unit.command(), end).unwrap()
        } else {
            unit.prepare(&mut run, end)
        };
        if matches!(self.which, StateExercise::RawNoLane) {
            let child = prepared.test_child_handle(ConsumerProducerRole::Outer);
            let open = framed(br#"{"kind":"open","version":"0.1.0-draft.1","sequence":0}"#);
            assert_eq!(rustix::io::write(child, &open).unwrap(), open.len());
            let error = run
                .poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer)
                .err();
            let empty = run
                .test_consumer_cache(ConsumerProducerRole::Outer)
                .is_empty();
            let no_ack = matches!(
                rustix::io::read(child, &mut [0; 1]),
                Ok(0) | Err(rustix::io::Errno::AGAIN)
            );
            drop(prepared);
            drop(ports);
            assert_eq!(error, Some(ConsumerCodecError::Association));
            assert!(
                empty && no_ack,
                "raw DATA preparation cannot retain a frame or mint an ACK"
            );
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        if matches!(self.which, StateExercise::FixedDeadline) {
            let calls = Cell::new(0);
            let before = Instant::now();
            let after = before;
            let first = run
                .test_consumer_deadline_with(&ports, ConsumerProducerRole::Outer, || {
                    calls.set(calls.get() + 1);
                    (before, 12, after, Timebase::new(125, 3).unwrap())
                })
                .unwrap();
            let second = run
                .test_consumer_deadline_with(&ports, ConsumerProducerRole::TransferHelper, || {
                    calls.set(calls.get() + 1);
                    (before, 1_000_012, after, Timebase::new(125, 3).unwrap())
                })
                .unwrap();
            let third = run
                .test_consumer_deadline_with(&ports, ConsumerProducerRole::Outer, || {
                    panic!("issued deadline cannot resample")
                })
                .unwrap();
            assert_eq!(calls.get(), 1);
            assert_eq!(first.calibrated_at_ns(), 500);
            for value in [&second, &third] {
                assert_eq!(value.calibrated_at_ns(), first.calibrated_at_ns());
                assert_eq!(value.end_ns(), first.end_ns());
                assert_eq!(value.timebase().numerator(), 125);
                assert_eq!(value.timebase().denominator(), 3);
            }
        } else {
            let open = framed(br#"{"kind":"open","version":"0.1.0-draft.1","sequence":0}"#);
            let outer = prepared.test_child_handle(ConsumerProducerRole::Outer);
            assert_eq!(rustix::io::write(outer, &open).unwrap(), open.len());
            let ConsumerReceiveProgress::Retained(pending) = run
                .poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer)
                .unwrap()
            else {
                panic!("independent Outer must progress")
            };
            ack(&mut run, &mut ports, pending, outer, 0);
            let helper = prepared.test_child_handle(ConsumerProducerRole::TransferHelper);
            assert_eq!(rustix::io::write(helper, &open).unwrap(), open.len());
            let progress = run
                .poll_consumer_frame(&mut ports, ConsumerProducerRole::TransferHelper)
                .unwrap();
            match strategy {
                FixtureStrategy::NodePackage => {
                    let ConsumerReceiveProgress::Retained(pending) = progress else {
                        panic!("Node helper Open needs no delegated launch")
                    };
                    ack(&mut run, &mut ports, pending, helper, 0);
                }
                FixtureStrategy::NativeExecutable => {
                    assert!(matches!(
                        progress,
                        ConsumerReceiveProgress::AwaitingAssociation
                    ));
                    no_ack(helper);
                    assert_eq!(
                        run.test_consumer_cache(ConsumerProducerRole::TransferHelper)
                            .last()
                            .unwrap()
                            .literal_utf8(),
                        r#"{"kind":"open","version":"0.1.0-draft.1","sequence":0}"#
                    );
                    let started = unit.helper_started(&mut run);
                    assert_eq!(rustix::io::write(outer, &started).unwrap(), started.len());
                    let ConsumerReceiveProgress::Retained(pending) = run
                        .poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer)
                        .unwrap()
                    else {
                        panic!("actual Outer launch frame must retain")
                    };
                    ack(&mut run, &mut ports, pending, outer, 1);
                    let retained = run
                        .test_consumer_cache(ConsumerProducerRole::TransferHelper)
                        .len();
                    let ConsumerReceiveProgress::Retained(pending) = run
                        .poll_consumer_frame(&mut ports, ConsumerProducerRole::TransferHelper)
                        .unwrap()
                    else {
                        panic!("same held Open must now yield its ACK without more socket bytes")
                    };
                    assert_eq!(
                        run.test_consumer_cache(ConsumerProducerRole::TransferHelper)
                            .len(),
                        retained,
                        "release cannot duplicate the held cached Open"
                    );
                    ack(&mut run, &mut ports, pending, helper, 0);
                }
            }
        }
        drop(prepared);
        drop(ports);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn exercise_state(which: StateExercise) {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut policy = funded_consumer_policy(Limits {
        max_frame: 131072,
        stderr_capture: 128,
        ..Limits::DEFAULT
    });
    policy["consumerObservation"] =
        serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
    let mut probe = StateProbe {
        which,
        entered: false,
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
    };
    let report = run_configured_with_installed_client_adapter(
        kit.path(),
        &RunConfiguration::from_json(&policy.to_string()).unwrap(),
        &mut probe,
    )
    .unwrap();
    assert!(probe.entered);
    assert!(!report.qualified());
}
#[test]
fn synthetic_observed_lane_controls_real_open_association_and_ack() {
    for strategy in [
        FixtureStrategy::NodePackage,
        FixtureStrategy::NativeExecutable,
    ] {
        exercise_state(StateExercise::Lane(strategy));
    }
}
#[test]
fn unobserved_mismatch_and_raw_preparation_refuse_stateful_collection() {
    for which in [
        StateExercise::RefuseUnobserved,
        StateExercise::RefuseMismatch,
        StateExercise::RawNoLane,
    ] {
        exercise_state(which);
    }
}
#[test]
fn same_control_issues_one_deadline_for_both_roles_despite_continuous_only_advance() {
    exercise_state(StateExercise::FixedDeadline);
}

mod runtime_tests;
