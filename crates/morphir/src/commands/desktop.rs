use crate::home::{MORPHIR_HOME_ENV, MorphirHome};
use crate::observability::{
    DesktopLaunchContext, DesktopLaunchErrorCode, DesktopLaunchEvent, OperationId,
};
use clap::Args;
use miette::{IntoDiagnostic, Result, WrapErr, miette};
use morphir_distribution::{DistributionError, ToolId, activate_installed_tool};
use serde_json::Value;
use starbase::AppResult;
use std::{
    path::{Path, PathBuf},
    process::{Command, ExitStatus, Stdio},
    thread,
    time::{Duration, Instant},
};

mod readiness;
#[cfg(windows)]
mod windows;
use readiness::ReadinessLogs;

const DESKTOP_TOOL_ID: &str = "desktop";
const LAUNCH_CONTRACT_VERSION_ENV: &str = "MORPHIR_DESKTOP_LAUNCH_CONTRACT_VERSION";
const DESKTOP_WORKSPACE_ENV: &str = "MORPHIR_DESKTOP_WORKSPACE";
const LAUNCH_CONTRACT_VERSION: &str = "1";
const READY_TIMEOUT: Duration = Duration::from_secs(30);
const READY_POLL_INTERVAL: Duration = Duration::from_millis(50);
const LOG_POLL_INTERVAL: Duration = Duration::from_millis(250);
const FORWARDED_READY_GRACE: Duration = Duration::from_secs(2);
const UNVERIFIED_STARTUP_GRACE: Duration = Duration::from_secs(2);

/// Launch the active installed Morphir Desktop release.
#[derive(Args, Clone, Debug)]
pub struct DesktopArgs {
    /// Workspace directory or Morphir artifact to open (defaults to the current directory)
    #[arg(value_name = "PATH")]
    pub path: Option<PathBuf>,

    /// Wait for Desktop to exit and return its exit status
    #[arg(long)]
    pub wait: bool,

    /// Prohibit acquisition and launch only an already-installed release
    #[arg(long)]
    pub offline: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum DesktopLifecycle {
    Ready,
    Failed { error_code: Option<String> },
    Crashed { error_code: Option<String> },
    Exited { exit_code: Option<i64> },
}

pub fn run_desktop(operation_id: &OperationId, args: DesktopArgs) -> AppResult<miette::Report> {
    let workspace = resolve_workspace(args.path.as_deref())?;
    let home = resolve_absolute_home()?;
    let desktop_logs = resolve_desktop_logs(&home)?;
    let tool_id = ToolId::parse(DESKTOP_TOOL_ID).into_diagnostic()?;
    let active = match activate_installed_tool(&home, &tool_id) {
        Ok(active) => active,
        Err(DistributionError::ToolNotInstalled { .. }) => {
            return Err(miette!(
                "Morphir Desktop is not installed. Install a local developer package with: \
                 morphir tool install desktop --source <package> --channel developer --version <semver>"
            ));
        }
        Err(error) => {
            return Err(miette!(
                "The active Morphir Desktop installation could not be verified: {error}. \
                 Repair it with: morphir tool repair desktop --source <package>"
            ));
        }
    };
    let launch = DesktopLaunchContext::new(operation_id);
    let version = active.version().clone();
    let executable = active.program().to_path_buf();
    #[cfg(windows)]
    let launch_executable = windows::executable_path(&executable)?;
    #[cfg(not(windows))]
    let launch_executable = &executable;
    let mut command = Command::new(launch_executable);
    command.args(active.args()).arg(&workspace);
    command.env_clear();
    command.envs(std::env::vars_os().filter(|(name, _)| should_inherit_environment(name)));
    command.env(MORPHIR_HOME_ENV, home.root());
    // Resolve relative overrides before changing the child's working directory.
    command.env("MORPHIR_LOG_DIR", &desktop_logs);
    command.env(LAUNCH_CONTRACT_VERSION_ENV, LAUNCH_CONTRACT_VERSION);
    command.env(DESKTOP_WORKSPACE_ENV, &workspace);
    for (name, value) in launch.child_environment() {
        command.env(name, value);
    }
    command.current_dir(workspace_directory(&workspace));
    if args.wait {
        command.stdin(Stdio::inherit());
        command.stdout(Stdio::inherit());
        command.stderr(Stdio::inherit());
    } else {
        command.stdin(Stdio::null());
        command.stdout(Stdio::null());
        command.stderr(Stdio::null());
        configure_detached_process(&mut command);
    }

    tracing::info!(
        schema_version = 1,
        component = "cli",
        event_name = "desktop.launch.start",
        operation_id = %operation_id,
        launch_id = %launch.launch_id(),
        desktop_version = %version,
        executable = %executable.display(),
        workspace = %workspace.display(),
        offline = args.offline,
        wait = args.wait,
        "Launching Morphir Desktop"
    );

    let mut readiness = ReadinessLogs::snapshot(&desktop_logs);
    let mut child = command.spawn().map_err(|error| {
        record_launch_failure(
            operation_id,
            &launch,
            DesktopLaunchErrorCode::SpawnFailed,
            &version.to_string(),
            &executable,
            &desktop_logs,
        );
        miette!(
            "Failed to launch Morphir Desktop {version} from {}: {error}. Desktop logs: {}. \
             Repair with: morphir tool repair desktop --source <package>",
            executable.display(),
            desktop_logs.display()
        )
    })?;
    drop(active);

    let readiness_status = match await_ready(|| child.try_wait(), &mut readiness, &launch) {
        Ok(status) => status,
        Err(failure) => {
            record_launch_failure(
                operation_id,
                &launch,
                failure.code(),
                &version.to_string(),
                &executable,
                &desktop_logs,
            );
            if args.wait {
                let status = match &failure {
                    ReadyFailure::Exited(status) => Some(*status),
                    // A shutdown log can precede OS process termination. --wait
                    // must wait for its real status, not kill it or use the log's code.
                    ReadyFailure::ReportedExit(_) | ReadyFailure::ForwardingTimedOut => Some(
                        child
                            .wait()
                            .into_diagnostic()
                            .wrap_err("Failed while waiting for Morphir Desktop to exit")?,
                    ),
                    _ => child
                        .try_wait()
                        .into_diagnostic()
                        .wrap_err("Failed to observe Morphir Desktop exit")?,
                };
                if let Some(status) = status {
                    return Ok(Some(portable_exit_code(status)));
                }
            }
            let _ = child.kill();
            let _ = child.wait();
            return Err(miette!(
                "{} ({}) Desktop {} executable: {} logs: {} repair: morphir tool repair desktop --source <package>",
                failure.message(),
                failure.code().as_str(),
                version,
                executable.display(),
                desktop_logs.display()
            ));
        }
    };

    match readiness_status {
        ReadinessStatus::Confirmed => tracing::info!(
            schema_version = 1,
            component = "cli",
            event_name = DesktopLaunchEvent::Ready.as_str(),
            operation_id = %operation_id,
            launch_id = %launch.launch_id(),
            desktop_version = %version,
            "Morphir Desktop is ready"
        ),
        ReadinessStatus::Unverified { reason } => tracing::warn!(
            schema_version = 1,
            component = "cli",
            operation_id = %operation_id,
            launch_id = %launch.launch_id(),
            desktop_logs = %desktop_logs.display(),
            "Desktop started, but readiness could not be verified: {reason}. Continuing without terminating Desktop."
        ),
    }

    if !args.wait {
        return Ok(None);
    }

    let status = child
        .wait()
        .into_diagnostic()
        .wrap_err("Failed while waiting for Morphir Desktop to exit")?;
    let exit_code = portable_exit_code(status);
    tracing::info!(
        schema_version = 1,
        component = "cli",
        event_name = DesktopLaunchEvent::Exit.as_str(),
        operation_id = %operation_id,
        launch_id = %launch.launch_id(),
        desktop_version = %version,
        exit_code,
        outcome = if exit_code == 0 { "success" } else { "failure" },
        "Morphir Desktop exited"
    );
    Ok(Some(exit_code))
}

fn resolve_workspace(requested: Option<&Path>) -> Result<PathBuf> {
    let requested = match requested {
        Some(path) if path.is_absolute() => path.to_path_buf(),
        Some(path) => std::env::current_dir()
            .into_diagnostic()
            .wrap_err("Failed to resolve the current directory")?
            .join(path),
        None => std::env::current_dir()
            .into_diagnostic()
            .wrap_err("Failed to resolve the current directory")?,
    };
    requested
        .canonicalize()
        .into_diagnostic()
        .wrap_err_with(|| {
            format!(
                "Desktop workspace or artifact does not exist: {}",
                requested.display()
            )
        })
}

fn resolve_absolute_home() -> Result<MorphirHome> {
    let home = MorphirHome::resolve()
        .map_err(|error| miette!("Failed to resolve Morphir Home: {error}"))?;
    let root = if home.root().is_absolute() {
        home.root().to_path_buf()
    } else {
        std::env::current_dir()
            .into_diagnostic()
            .wrap_err("Failed to resolve the current directory")?
            .join(home.root())
    };
    MorphirHome::resolve_from(Some(root.as_os_str()), None)
        .map_err(|error| miette!("Failed to resolve Morphir Home: {error}"))
}

fn resolve_desktop_logs(home: &MorphirHome) -> Result<PathBuf> {
    let configured = std::env::var_os("MORPHIR_LOG_DIR")
        .filter(|path| !path.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home.desktop_logs_dir());
    std::path::absolute(configured)
        .into_diagnostic()
        .wrap_err("Failed to resolve the Desktop log directory")
}

fn workspace_directory(workspace: &Path) -> &Path {
    if workspace.is_dir() {
        workspace
    } else {
        workspace.parent().unwrap_or(workspace)
    }
}

#[cfg(unix)]
fn configure_detached_process(command: &mut Command) {
    use std::os::unix::process::CommandExt as _;

    command.process_group(0);
}

#[cfg(windows)]
fn configure_detached_process(command: &mut Command) {
    use std::os::windows::process::CommandExt as _;

    const DETACHED_PROCESS: u32 = 0x0000_0008;
    const CREATE_NEW_PROCESS_GROUP: u32 = 0x0000_0200;
    command.creation_flags(DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP);
}

fn should_inherit_environment(name: &std::ffi::OsStr) -> bool {
    let name = name.to_string_lossy().to_ascii_uppercase();
    matches!(
        name.as_str(),
        "PATH"
            | "PATHEXT"
            | "SYSTEMROOT"
            | "WINDIR"
            | "COMSPEC"
            | "TEMP"
            | "TMP"
            | "TMPDIR"
            | "HOME"
            | "USERPROFILE"
            | "HOMEDRIVE"
            | "HOMEPATH"
            | "APPDATA"
            | "LOCALAPPDATA"
            | "PROGRAMDATA"
            | "USERNAME"
            | "USER"
            | "LOGNAME"
            | "SHELL"
            | "LANG"
            | "DISPLAY"
            | "WAYLAND_DISPLAY"
            | "XAUTHORITY"
            | "DBUS_SESSION_BUS_ADDRESS"
            | "DESKTOP_SESSION"
            | "SESSION_MANAGER"
    ) || name.starts_with("LC_")
        || name.starts_with("XDG_")
        || name.starts_with("GTK_")
        || name.starts_with("GDK_")
        || name.starts_with("QT_")
}

#[derive(Debug)]
enum ReadyFailure {
    Exited(ExitStatus),
    ReportedFailure(Option<String>),
    ReportedExit(Option<i64>),
    ForwardingTimedOut,
    ObservationFailed(std::io::Error),
    TimedOut,
}

impl ReadyFailure {
    fn code(&self) -> DesktopLaunchErrorCode {
        match self {
            Self::TimedOut => DesktopLaunchErrorCode::ReadyTimedOut,
            _ => DesktopLaunchErrorCode::ExitedBeforeReady,
        }
    }

    fn message(&self) -> String {
        match self {
            Self::Exited(status) => format!("Morphir Desktop exited before reporting readiness. Exit status: {status}."),
            Self::ReportedFailure(code) => format!("Morphir Desktop reported a launch failure before readiness{}.", code.as_ref().map(|code| format!(" ({code})")).unwrap_or_default()),
            Self::ReportedExit(code) => format!("Morphir Desktop exited before readiness{}.", code.map(|code| format!(" Exit code: {code}")).unwrap_or_default()),
            Self::ForwardingTimedOut => "Morphir Desktop exited successfully, but the existing instance did not report readiness during the forwarding grace period.".to_owned(),
            Self::ObservationFailed(error) => format!("Failed to observe Morphir Desktop startup: {error}."),
            Self::TimedOut => format!("Morphir Desktop did not report readiness within {} seconds.", READY_TIMEOUT.as_secs()),
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
enum ReadinessStatus {
    Confirmed,
    Unverified { reason: String },
}

fn await_ready(
    mut poll_child: impl FnMut() -> std::io::Result<Option<ExitStatus>>,
    readiness: &mut std::io::Result<ReadinessLogs>,
    launch: &DesktopLaunchContext,
) -> std::result::Result<ReadinessStatus, ReadyFailure> {
    let readiness = match readiness {
        Ok(readiness) => readiness,
        Err(error) => {
            return await_unverified(&mut poll_child, error.to_string(), None);
        }
    };
    let deadline = Instant::now() + READY_TIMEOUT;
    let mut next_log_poll = Instant::now();
    let mut observed_exit: Option<(ExitStatus, Instant)> = None;
    let mut forwarded_exit_at: Option<Instant> = None;
    loop {
        let lifecycle = if Instant::now() >= next_log_poll {
            let lifecycle = match readiness.poll(launch.launch_id().as_str()) {
                Ok(lifecycle) => lifecycle,
                Err(error) => {
                    return await_unverified(
                        &mut poll_child,
                        error.to_string(),
                        observed_exit.map(|(status, _)| status),
                    );
                }
            };
            next_log_poll = Instant::now() + LOG_POLL_INTERVAL;
            lifecycle
        } else {
            None
        };
        if let Some(lifecycle) = lifecycle {
            match lifecycle {
                DesktopLifecycle::Ready => return Ok(ReadinessStatus::Confirmed),
                DesktopLifecycle::Failed { error_code }
                | DesktopLifecycle::Crashed { error_code } => {
                    return Err(ReadyFailure::ReportedFailure(error_code));
                }
                DesktopLifecycle::Exited { exit_code: Some(0) } => {
                    // Repeated polls return the last observed event. Start the
                    // grace once so it stays bounded until forwarded readiness.
                    forwarded_exit_at.get_or_insert_with(Instant::now);
                }
                DesktopLifecycle::Exited { exit_code } => {
                    return Err(ReadyFailure::ReportedExit(exit_code));
                }
            }
        }
        if let Some((status, observed_at)) = observed_exit
            && observed_at.elapsed() >= FORWARDED_READY_GRACE
        {
            return Err(ReadyFailure::Exited(status));
        }
        if forwarded_exit_at.is_some_and(|at| at.elapsed() >= FORWARDED_READY_GRACE) {
            return Err(ReadyFailure::ForwardingTimedOut);
        }
        if observed_exit.is_none()
            && let Some(status) = poll_child().map_err(ReadyFailure::ObservationFailed)?
        {
            observed_exit = Some((status, Instant::now()));
        }
        if Instant::now() >= deadline {
            return Err(ReadyFailure::TimedOut);
        }
        thread::sleep(READY_POLL_INTERVAL);
    }
}

fn await_unverified(
    poll_child: &mut impl FnMut() -> std::io::Result<Option<ExitStatus>>,
    reason: String,
    observed_exit: Option<ExitStatus>,
) -> std::result::Result<ReadinessStatus, ReadyFailure> {
    let deadline = Instant::now() + UNVERIFIED_STARTUP_GRACE;
    loop {
        let status = match observed_exit {
            Some(status) => Some(status),
            None => poll_child().map_err(ReadyFailure::ObservationFailed)?,
        };
        if let Some(status) = status {
            if !status.success() {
                return Err(ReadyFailure::Exited(status));
            }
            // A successful short-lived child may have forwarded to an existing
            // Desktop. Without logs, neither readiness nor failure is proven.
            return Ok(ReadinessStatus::Unverified { reason });
        }
        if Instant::now() >= deadline {
            return Ok(ReadinessStatus::Unverified { reason });
        }
        thread::sleep(READY_POLL_INTERVAL);
    }
}

fn lifecycle_from_event(event: &Value, launch_id: &str) -> Option<DesktopLifecycle> {
    let fields = event.get("fields")?;
    if fields.get("launch_id")?.as_str()? != launch_id {
        return None;
    }
    let event_name = fields.get("event_name")?.as_str()?;
    match DesktopLaunchEvent::parse(event_name)? {
        DesktopLaunchEvent::Ready => Some(DesktopLifecycle::Ready),
        DesktopLaunchEvent::LaunchFailed => Some(DesktopLifecycle::Failed {
            error_code: fields
                .get("error_code")
                .and_then(Value::as_str)
                .map(str::to_owned),
        }),
        DesktopLaunchEvent::Crash => Some(DesktopLifecycle::Crashed {
            error_code: fields
                .get("error_code")
                .and_then(Value::as_str)
                .map(str::to_owned),
        }),
        DesktopLaunchEvent::Exit => Some(DesktopLifecycle::Exited {
            exit_code: fields.get("exit_code").and_then(Value::as_i64),
        }),
    }
}

fn record_launch_failure(
    operation_id: &OperationId,
    launch: &DesktopLaunchContext,
    code: DesktopLaunchErrorCode,
    version: &str,
    executable: &Path,
    desktop_logs: &Path,
) {
    tracing::error!(
        schema_version = 1,
        component = "cli",
        event_name = DesktopLaunchEvent::LaunchFailed.as_str(),
        operation_id = %operation_id,
        launch_id = %launch.launch_id(),
        error_code = code.as_str(),
        desktop_version = version,
        executable = %executable.display(),
        desktop_logs = %desktop_logs.display(),
        repair_command = "morphir tool repair desktop --source <package>",
        "Morphir Desktop launch failed"
    );
}

fn portable_exit_code(status: ExitStatus) -> u8 {
    status
        .code()
        .and_then(|code| u8::try_from(code).ok())
        .unwrap_or(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn successful_logged_exit_grace_expires_without_readiness() {
        let root = tempfile::tempdir().unwrap();
        let mut readiness = ReadinessLogs::snapshot(root.path());
        let launch = DesktopLaunchContext::new(&OperationId::new());
        let fields = serde_json::json!({"fields": {
            "event_name": "desktop.exit", "launch_id": launch.launch_id().as_str(), "exit_code": 0
        }});
        std::fs::write(root.path().join("exit.jsonl"), format!("{fields}\n")).unwrap();
        let result = await_ready(|| Ok(None), &mut readiness, &launch);
        assert!(
            matches!(result, Err(ReadyFailure::ForwardingTimedOut)),
            "{result:?}"
        );
    }

    #[test]
    fn nonzero_logged_exit_fails_without_forwarding_grace() {
        let root = tempfile::tempdir().unwrap();
        let mut readiness = ReadinessLogs::snapshot(root.path());
        let launch = DesktopLaunchContext::new(&OperationId::new());
        let fields = serde_json::json!({"fields": {
            "event_name": "desktop.exit", "launch_id": launch.launch_id().as_str(), "exit_code": 23
        }});
        std::fs::write(root.path().join("exit.jsonl"), format!("{fields}\n")).unwrap();
        let result = await_ready(
            || panic!("nonzero logged exit must fail immediately"),
            &mut readiness,
            &launch,
        );
        assert!(
            matches!(result, Err(ReadyFailure::ReportedExit(Some(23)))),
            "{result:?}"
        );
    }

    #[test]
    fn successful_logged_exit_allows_forwarded_readiness_in_a_later_poll() {
        let root = tempfile::tempdir().unwrap();
        let mut readiness = ReadinessLogs::snapshot(root.path());
        let launch = DesktopLaunchContext::new(&OperationId::new());
        let fields = serde_json::json!({"fields": {
            "event_name": "desktop.exit", "launch_id": launch.launch_id().as_str(), "exit_code": 0
        }});
        std::fs::write(root.path().join("exit.jsonl"), format!("{fields}\n")).unwrap();
        let result = await_ready(
            || {
                let ready = serde_json::json!({"fields": {
                    "event_name": "desktop.ready", "launch_id": launch.launch_id().as_str()
                }});
                std::fs::write(root.path().join("ready.jsonl"), format!("{ready}\n")).unwrap();
                Ok(Some(exit_status(0)))
            },
            &mut readiness,
            &launch,
        );
        assert!(
            matches!(result, Ok(ReadinessStatus::Confirmed)),
            "{result:?}"
        );
    }

    fn exit_status(code: u32) -> ExitStatus {
        #[cfg(windows)]
        {
            use std::os::windows::process::ExitStatusExt;
            ExitStatus::from_raw(code)
        }
        #[cfg(unix)]
        {
            use std::os::unix::process::ExitStatusExt;
            ExitStatus::from_raw((code as i32) << 8)
        }
    }

    #[test]
    fn unavailable_readiness_does_not_hide_an_immediate_crash() {
        let mut readiness = Err(std::io::Error::other("unavailable logs"));
        let launch = DesktopLaunchContext::new(&OperationId::new());
        let result = await_ready(|| Ok(Some(exit_status(23))), &mut readiness, &launch);
        assert!(
            matches!(result, Err(ReadyFailure::Exited(_))),
            "a known startup failure must not be reported as started: {result:?}"
        );
    }

    #[test]
    fn log_discovery_cap_before_spawn_does_not_fail_the_launch() {
        let root = tempfile::tempdir().unwrap();
        std::fs::write(root.path().join("unrelated.txt"), "unrelated").unwrap();
        let mut readiness = ReadinessLogs::snapshot_with_limit(root.path(), 1);
        assert!(readiness.is_err(), "fixture must reach discovery cap");
        let launch = DesktopLaunchContext::new(&OperationId::new());
        let mut polls = 0;
        let result = await_ready(
            || {
                polls += 1;
                Ok(None)
            },
            &mut readiness,
            &launch,
        );
        assert!(polls > 1, "observe the healthy child for a startup window");
        assert!(
            matches!(result, Ok(ReadinessStatus::Unverified { .. })),
            "log saturation must not fail launch or claim readiness: {result:?}"
        );
    }

    #[test]
    fn log_discovery_cap_after_spawn_does_not_fail_the_launch() {
        let root = tempfile::tempdir().unwrap();
        let mut readiness = ReadinessLogs::snapshot_with_limit(root.path(), 1);
        assert!(readiness.is_ok());
        std::fs::write(root.path().join("unrelated.txt"), "unrelated").unwrap();
        let launch = DesktopLaunchContext::new(&OperationId::new());
        let mut polls = 0;
        let result = await_ready(
            || {
                polls += 1;
                Ok(None)
            },
            &mut readiness,
            &launch,
        );
        assert!(polls > 1, "observe the healthy child for a startup window");
        assert!(
            matches!(result, Ok(ReadinessStatus::Unverified { .. })),
            "log saturation must not fail launch or claim readiness: {result:?}"
        );
    }

    #[test]
    fn log_polling_failure_still_observes_a_delayed_crash() {
        let root = tempfile::tempdir().unwrap();
        let mut readiness = ReadinessLogs::snapshot_with_limit(root.path(), 1);
        assert!(readiness.is_ok());
        std::fs::write(root.path().join("unrelated.txt"), "unrelated").unwrap();
        let launch = DesktopLaunchContext::new(&OperationId::new());
        let mut polls = 0;
        let result = await_ready(
            || {
                polls += 1;
                Ok((polls == 2).then(|| exit_status(23)))
            },
            &mut readiness,
            &launch,
        );
        assert!(matches!(result, Err(ReadyFailure::Exited(_))));
        assert_eq!(polls, 2);
    }

    #[test]
    fn unavailable_logs_do_not_misclassify_successful_forwarding() {
        let mut readiness = Err(std::io::Error::other("unavailable logs"));
        let launch = DesktopLaunchContext::new(&OperationId::new());
        let result = await_ready(|| Ok(Some(exit_status(0))), &mut readiness, &launch);
        assert!(matches!(result, Ok(ReadinessStatus::Unverified { .. })));
    }

    #[test]
    fn unavailable_logs_preserve_an_already_observed_crash() {
        let result = await_unverified(
            &mut || panic!("the child has already been observed exiting"),
            "unavailable logs".to_owned(),
            Some(exit_status(23)),
        );
        assert!(matches!(result, Err(ReadyFailure::Exited(_))));
    }

    #[test]
    fn readiness_requires_the_requested_launch_id() {
        let unrelated: Value = serde_json::json!({
            "fields": { "event_name": "desktop.ready", "launch_id": "launch-other" }
        });
        let expected: Value = serde_json::json!({
            "fields": { "event_name": "desktop.ready", "launch_id": "launch-expected" }
        });

        assert_eq!(lifecycle_from_event(&unrelated, "launch-expected"), None);
        assert_eq!(
            lifecycle_from_event(&expected, "launch-expected"),
            Some(DesktopLifecycle::Ready)
        );
    }

    #[test]
    fn child_failures_preserve_the_desktop_error_code() {
        let failed: Value = serde_json::json!({
            "fields": {
                "event_name": "desktop.launch.failed",
                "launch_id": "launch-expected",
                "error_code": "MORPHIR_DESKTOP_RENDERER_LOAD_FAILED"
            }
        });

        assert_eq!(
            lifecycle_from_event(&failed, "launch-expected"),
            Some(DesktopLifecycle::Failed {
                error_code: Some("MORPHIR_DESKTOP_RENDERER_LOAD_FAILED".to_owned())
            })
        );
    }

    #[test]
    fn a_recorded_ready_event_wins_over_a_later_exit() {
        let temporary = tempfile::tempdir().unwrap();
        let mut readiness = ReadinessLogs::snapshot(temporary.path()).unwrap();
        let log = temporary.path().join("desktop.jsonl");
        std::fs::write(
            log,
            concat!(
                "{\"fields\":{\"event_name\":\"desktop.ready\",\"launch_id\":\"launch-expected\"}}\n",
                "{\"fields\":{\"event_name\":\"desktop.exit\",\"launch_id\":\"launch-expected\",\"exit_code\":0}}\n"
            ),
        )
        .unwrap();

        assert_eq!(
            readiness.poll("launch-expected").unwrap(),
            Some(DesktopLifecycle::Ready)
        );
    }

    #[test]
    fn inherited_environment_excludes_credentials_and_stale_morphir_state() {
        assert!(should_inherit_environment(std::ffi::OsStr::new("PATH")));
        assert!(should_inherit_environment(std::ffi::OsStr::new(
            "XDG_RUNTIME_DIR"
        )));
        assert!(!should_inherit_environment(std::ffi::OsStr::new(
            "GITHUB_TOKEN"
        )));
        assert!(!should_inherit_environment(std::ffi::OsStr::new(
            "MORPHIR_LAUNCH_ID"
        )));
    }
}
