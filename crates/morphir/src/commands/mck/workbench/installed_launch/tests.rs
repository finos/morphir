//! OFFGRAPH source-first launch-selection/argv controls. No process or host.
//! Proposed mount: workbench::installed_launch::tests, subject to root review.
use super::installed_launch::*;
use super::*;
use crate::commands::mck::workbench::RunArgs;
use clap::Parser;
use morphir_mck::workbench::model_originals::installed::{
    InstalledAdapterError, InstalledClientAction, InstalledClientAdapter,
    InstalledClientMeasurements, InstalledClientRun, InstalledCommand,
};
use morphir_mck::workbench::{
    RunConfiguration, WorkbenchExecutionMode, run_configured_with_installed_client_adapter,
};
use std::{ffi::OsString, path::PathBuf};

const INSTALLED: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../morphir-mck/src/workbench/installed_borrowed_controls/installed-policy.json"
));
const NATIVE: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../morphir-mck/src/workbench/native_pipeline_controls/native-policy.json"
));
const SELECTED: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../morphir-mck/src/workbench/model_originals/workflow/pipeline/installed_client_controls/checker-policy.json"
));
const CASES: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../morphir-mck/src/workbench/model_originals/workflow/pipeline/installed_client_controls/cases24.json"
));
const WRONG_ROLE: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../morphir-mck/src/workbench/model_originals/workflow/pipeline/installed_client_controls/wrong-role.json"
));

#[derive(Parser)]
struct Arguments {
    #[command(flatten)]
    run: RunArgs,
}
fn absolute(member: &str) -> PathBuf {
    #[cfg(windows)]
    let root = PathBuf::from(r"C:\mck-lexical-inputs-not-created");
    #[cfg(not(windows))]
    let root = PathBuf::from("/mck-lexical-inputs-not-created");
    root.join(member)
}
fn base_argv(adapter: &str) -> Vec<OsString> {
    vec![
        "launch-controls".into(),
        "--kit".into(),
        absolute("corpus").into_os_string(),
        "--adapter".into(),
        adapter.into(),
        "--report".into(),
        absolute("report.json").into_os_string(),
    ]
}
fn options(target: &str) -> Vec<OsString> {
    let mut args = vec![
        "--installed-client-target".into(),
        target.into(),
        "--installed-client-package".into(),
        absolute("package with spaces").into_os_string(),
        "--installed-client-node".into(),
        absolute("runtime/node").into_os_string(),
        "--installed-client-source-checkout".into(),
        absolute("associated source").into_os_string(),
    ];
    if target == "native" {
        args.extend([
            "--installed-client-program".into(),
            absolute("native/morphir").into_os_string(),
        ]);
    }
    args
}
fn args(extra: &[OsString]) -> RunArgs {
    let mut argv = base_argv("builtin:morphir-workbench");
    argv.extend_from_slice(extra);
    Arguments::try_parse_from(argv).unwrap().run
}
fn mode(raw: &str) -> WorkbenchExecutionMode {
    RunConfiguration::from_json(raw).unwrap().execution_mode()
}
fn installed(extra: &[OsString]) -> InstalledLaunch {
    match WorkbenchLaunch::select(&args(extra), mode(INSTALLED)).unwrap() {
        WorkbenchLaunch::InstalledClient(launch) => launch,
        _ => panic!("installed configuration must select the closed installed launch"),
    }
}

#[test]
fn launch_l01_existing_native_builtin_and_external_argv_are_preserved() {
    let native = args(&[]);
    assert!(matches!(
        WorkbenchLaunch::select(&native, mode(NATIVE)),
        Ok(WorkbenchLaunch::NativeHost)
    ));
    let mut argv = base_argv("relative external adapter");
    argv.extend(["--adapter-arg".into(), "--opaque=a b".into()]);
    let external = Arguments::try_parse_from(argv).unwrap().run;
    for raw in [r#"{"kind":"historical"}"#, SELECTED] {
        match WorkbenchLaunch::select(&external, mode(raw)).unwrap() {
            WorkbenchLaunch::External { program, arguments } => {
                assert_eq!(program, &external.adapter);
                assert_eq!(arguments, external.adapter_args.as_slice());
            }
            _ => panic!("historical external spelling is not an installed launch"),
        }
    }
}

#[test]
fn launch_l02_required_and_forbidden_options_form_closed_node_native_choices() {
    for target in ["node", "native"] {
        let complete = options(target);
        assert!(matches!(
            WorkbenchLaunch::select(&args(&complete), mode(INSTALLED)),
            Ok(WorkbenchLaunch::InstalledClient(_))
        ));
        for flag in [
            "--installed-client-target",
            "--installed-client-package",
            "--installed-client-node",
            "--installed-client-source-checkout",
        ] {
            let mut incomplete = complete.clone();
            let index = incomplete.iter().position(|arg| arg == flag).unwrap();
            incomplete.drain(index..index + 2);
            assert!(WorkbenchLaunch::select(&args(&incomplete), mode(INSTALLED)).is_err());
        }
    }
    let mut missing_native = options("native");
    missing_native.truncate(missing_native.len() - 2);
    assert!(WorkbenchLaunch::select(&args(&missing_native), mode(INSTALLED)).is_err());
    let mut extra_native = options("node");
    extra_native.extend([
        "--installed-client-program".into(),
        absolute("unselected native").into_os_string(),
    ]);
    assert!(WorkbenchLaunch::select(&args(&extra_native), mode(INSTALLED)).is_err());
}

#[test]
fn launch_l03_wrong_mode_external_and_builtin_arguments_refuse_lexically() {
    for raw in [r#"{"kind":"historical"}"#, SELECTED, NATIVE] {
        assert!(WorkbenchLaunch::select(&args(&options("node")), mode(raw)).is_err());
    }
    let mut external_argv = base_argv("ordinary-program");
    external_argv.extend(options("native"));
    let external = Arguments::try_parse_from(external_argv).unwrap().run;
    assert!(WorkbenchLaunch::select(&external, mode(INSTALLED)).is_err());
    for suffix in [vec![], options("node"), options("native")] {
        let mut bad = suffix;
        bad.extend(["--adapter-arg".into(), "free-prefix".into()]);
        assert!(WorkbenchLaunch::select(&args(&bad), mode(INSTALLED)).is_err());
    }
    assert!(WorkbenchLaunch::select(&args(&[]), mode(INSTALLED)).is_err());
    assert!(WorkbenchLaunch::select(&args(&[]), mode(SELECTED)).is_err());
}

#[test]
fn launch_l04_absolute_input_paths_are_lexical_and_lossless_not_verified() {
    let raw = absolute("not inspected/../entry with spaces");
    let parsed = AbsoluteLaunchPath::parse(raw.clone()).unwrap();
    assert_eq!(parsed.as_path(), raw.as_path());
    assert!(AbsoluteLaunchPath::parse(PathBuf::from("relative/path")).is_err());
    assert!(AbsoluteLaunchPath::parse(PathBuf::new()).is_err());
    // This path is deliberately not created or probed. Selection must not
    // perform canonicalize, metadata, hash/version/auth or process operations.
    for target in ["node", "native"] {
        let _ = installed(&options(target));
    }
}

#[test]
fn launch_l05_each_relative_selected_path_and_unknown_target_is_refused() {
    for target in ["node", "native"] {
        let complete = options(target);
        for flag in [
            "--installed-client-package",
            "--installed-client-node",
            "--installed-client-source-checkout",
            "--installed-client-program",
        ] {
            let Some(index) = complete.iter().position(|arg| arg == flag) else {
                continue;
            };
            let mut bad = complete.clone();
            bad[index + 1] = "relative/path".into();
            assert!(WorkbenchLaunch::select(&args(&bad), mode(INSTALLED)).is_err());
        }
    }
    let mut unknown = base_argv("builtin:morphir-workbench");
    unknown.extend(options("shell"));
    assert!(Arguments::try_parse_from(unknown).is_err());
}

fn command_paths() -> InstalledCommandPaths {
    InstalledCommandPaths::new(
        absolute("invocation/launch.json"),
        absolute("invocation/connection.json"),
        absolute("invocation/source.json"),
        absolute("invocation/project.json"),
        absolute("invocation/destination"),
    )
    .unwrap()
}
struct CommandProbe {
    launch: InstalledLaunch,
    native: bool,
    callbacks: usize,
    commands: usize,
}
impl InstalledClientAdapter for CommandProbe {
    fn observe(
        &mut self,
        run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.callbacks += 1;
        let paths = command_paths();
        for action in run.actions() {
            if !matches!(&action, InstalledClientAction::Run { .. }) {
                continue;
            }
            let line = self.launch.command(action, &paths).unwrap();
            let mut expected: Vec<OsString> = if self.native {
                vec![]
            } else {
                vec![absolute("package with spaces/bin/morphir.js").into_os_string()]
            };
            let arguments: Vec<OsString> = match self.commands {
                0 => vec![
                    "connected".into(),
                    "connect".into(),
                    absolute("invocation/launch.json").into_os_string(),
                    "--connection".into(),
                    absolute("invocation/connection.json").into_os_string(),
                    "--connection-scope".into(),
                    "models".into(),
                    "--provider".into(),
                    "workbench-http".into(),
                    "--json".into(),
                    "--node".into(),
                    absolute("runtime/node").into_os_string(),
                    "--connected-helper".into(),
                    absolute("package with spaces/build-provider/connected.mjs").into_os_string(),
                ],
                1 => vec![
                    "connected".into(),
                    "originals".into(),
                    absolute("invocation/source.json").into_os_string(),
                    "--list".into(),
                    "--connection".into(),
                    absolute("invocation/connection.json").into_os_string(),
                    "--provider".into(),
                    "workbench-http".into(),
                    "--json".into(),
                    "--node".into(),
                    absolute("runtime/node").into_os_string(),
                    "--originals-helper".into(),
                    absolute("package with spaces/build-provider/originals.mjs").into_os_string(),
                ],
                2 => vec![
                    "connected".into(),
                    "originals".into(),
                    absolute("invocation/project.json").into_os_string(),
                    "--connection".into(),
                    absolute("invocation/connection.json").into_os_string(),
                    "--output".into(),
                    absolute("invocation/destination").into_os_string(),
                    "--provider".into(),
                    "workbench-http".into(),
                    "--json".into(),
                    "--node".into(),
                    absolute("runtime/node").into_os_string(),
                    "--originals-helper".into(),
                    absolute("package with spaces/build-provider/originals.mjs").into_os_string(),
                ],
                _ => panic!("source must retain exactly the existing three commands"),
            };
            expected.extend(arguments);
            assert_eq!(line.arguments(), expected.as_slice());
            let program = if self.native {
                absolute("native/morphir")
            } else {
                absolute("runtime/node")
            };
            assert_eq!(line.program(), program.as_path());
            assert_eq!(
                line.arguments()
                    .iter()
                    .filter(|arg| *arg == "--node")
                    .count(),
                1
            );
            assert!(
                !line
                    .arguments()
                    .iter()
                    .any(|arg| arg == "--installed-client-source-checkout")
            );
            let _ = line.into_spec(absolute("invocation"), vec![]).unwrap();
            self.commands += 1;
        }
        // Only lexical command DATA was inspected. No successful measurement,
        // actual executable validation, invocation/auth/spawn or host evidence.
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn kit(raw: &[u8]) -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(dir.path().join("cases.json"), raw).unwrap();
    dir
}
fn probe(target: &str) -> CommandProbe {
    CommandProbe {
        launch: installed(&options(target)),
        native: target == "native",
        callbacks: 0,
        commands: 0,
    }
}

#[test]
fn launch_l06_node_uses_actual_three_actions_fixed_entry_helpers_and_one_node() {
    let mut adapter = probe("node");
    let root = kit(CASES);
    let report = run_configured_with_installed_client_adapter(
        root.path(),
        &RunConfiguration::from_json(INSTALLED).unwrap(),
        &mut adapter,
    )
    .unwrap();
    assert_eq!((adapter.callbacks, adapter.commands), (1, 3));
    assert!(!report.qualified());
}

#[test]
fn launch_l07_native_has_no_free_prefix_and_preserves_same_node_and_helpers() {
    let mut adapter = probe("native");
    let root = kit(CASES);
    let report = run_configured_with_installed_client_adapter(
        root.path(),
        &RunConfiguration::from_json(INSTALLED).unwrap(),
        &mut adapter,
    )
    .unwrap();
    assert_eq!((adapter.callbacks, adapter.commands), (1, 3));
    assert!(!report.qualified());
}

#[test]
fn launch_l08_wrong_or_malformed_whole_source_prevents_command_callback() {
    let last_non_whitespace = CASES
        .iter()
        .rposition(|byte| !byte.is_ascii_whitespace())
        .unwrap();
    for raw in [WRONG_ROLE, &CASES[..last_non_whitespace]] {
        let root = kit(raw);
        let mut adapter = probe("node");
        assert!(
            run_configured_with_installed_client_adapter(
                root.path(),
                &RunConfiguration::from_json(INSTALLED).unwrap(),
                &mut adapter,
            )
            .is_err()
        );
        assert_eq!((adapter.callbacks, adapter.commands), (0, 0));
    }
}

struct WrongDirectoryProbe {
    callbacks: usize,
}
impl InstalledClientAdapter for WrongDirectoryProbe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.callbacks += 1;
        let launch = installed(&options("node"));
        let directory = absolute("invocation");
        let paths = InstalledCommandPaths::new_confined(
            directory.join("launch.json"),
            directory.join("connection.json"),
            directory.join("source.json"),
            directory.join("project.json"),
            directory.clone(),
            "destination".into(),
            directory.join("destination"),
        )
        .unwrap();
        let action = run.actions().nth(2).unwrap();
        assert!(matches!(
            action,
            InstalledClientAction::Run {
                command: InstalledCommand::Connect,
                ..
            }
        ));
        let wrong_directory = absolute("wrong-directory");
        let before = run.installed_observation_usage();
        let result = launch.spawn(
            2,
            action,
            &paths,
            &mut run,
            InstalledInvocationSettings::new(
                &wrong_directory,
                &[],
                morphir_mck::transport::Limits::DEFAULT,
            ),
        );
        assert!(matches!(
            result,
            Err(InstalledAdapterError::ObservationIncomplete)
        ));
        let after = run.installed_observation_usage();
        assert_eq!(after.retained_bytes(), before.retained_bytes());
        assert_eq!(after.stdout_prefix_bytes(), before.stdout_prefix_bytes());
        assert_eq!(after.stderr_prefix_bytes(), before.stderr_prefix_bytes());
        assert_eq!(after.snapshot_read_bytes(), before.snapshot_read_bytes());
        assert_eq!(after.records(), before.records());
        assert_eq!(
            after.byte_visits(),
            before.byte_visits()
                + (wrong_directory.as_os_str().len() + directory.as_os_str().len()) as u64
        );
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}

#[test]
fn installed_spawn_rejects_wrong_directory_before_spec_allocation() {
    let mut adapter = WrongDirectoryProbe { callbacks: 0 };
    let root = kit(CASES);
    let report = run_configured_with_installed_client_adapter(
        root.path(),
        &RunConfiguration::from_json(INSTALLED).unwrap(),
        &mut adapter,
    )
    .unwrap();
    assert_eq!(adapter.callbacks, 1);
    assert!(!report.qualified());
}
