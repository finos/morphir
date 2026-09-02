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
    fs,
    path::{Path, PathBuf},
    process::{Child, Command, ExitStatus, Stdio},
    thread,
    time::{Duration, Instant},
};

const DESKTOP_TOOL_ID: &str = "desktop";
const LAUNCH_CONTRACT_VERSION_ENV: &str = "MORPHIR_DESKTOP_LAUNCH_CONTRACT_VERSION";
const DESKTOP_WORKSPACE_ENV: &str = "MORPHIR_DESKTOP_WORKSPACE";
const LAUNCH_CONTRACT_VERSION: &str = "1";
const READY_TIMEOUT: Duration = Duration::from_secs(30);
const READY_POLL_INTERVAL: Duration = Duration::from_millis(50);
const FORWARDED_READY_GRACE: Duration = Duration::from_secs(2);

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
    let mut command = Command::new(active.program());
    command.args(active.args()).arg(&workspace);
    command.env_clear();
    command.envs(std::env::vars_os().filter(|(name, _)| should_inherit_environment(name)));
    command.env(MORPHIR_HOME_ENV, home.root());
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

    let mut child = command.spawn().map_err(|error| {
        record_launch_failure(
            operation_id,
            &launch,
            DesktopLaunchErrorCode::SpawnFailed,
            &version.to_string(),
            &executable,
            &home.desktop_logs_dir(),
        );
        miette!(
            "Failed to launch Morphir Desktop {version} from {}: {error}. Desktop logs: {}. \
             Repair with: morphir tool repair desktop --source <package>",
            executable.display(),
            home.desktop_logs_dir().display()
        )
    })?;
    drop(active);

    await_ready(&mut child, &home.desktop_logs_dir(), &launch).map_err(|failure| {
        record_launch_failure(
            operation_id,
            &launch,
            failure.code,
            &version.to_string(),
            &executable,
            &home.desktop_logs_dir(),
        );
        let _ = child.kill();
        let _ = child.wait();
        miette!(
            "{} ({}) Desktop {} executable: {} logs: {} repair: morphir tool repair desktop --source <package>",
            failure.message,
            failure.code.as_str(),
            version,
            executable.display(),
            home.desktop_logs_dir().display()
        )
    })?;

    tracing::info!(
        schema_version = 1,
        component = "cli",
        event_name = DesktopLaunchEvent::Ready.as_str(),
        operation_id = %operation_id,
        launch_id = %launch.launch_id(),
        desktop_version = %version,
        "Morphir Desktop is ready"
    );

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
struct ReadyFailure {
    code: DesktopLaunchErrorCode,
    message: String,
}

fn await_ready(
    child: &mut Child,
    desktop_logs: &Path,
    launch: &DesktopLaunchContext,
) -> std::result::Result<(), ReadyFailure> {
    let deadline = Instant::now() + READY_TIMEOUT;
    let mut observed_exit: Option<(ExitStatus, Instant)> = None;
    loop {
        if let Some(lifecycle) = find_lifecycle_event(desktop_logs, launch.launch_id().as_str()) {
            match lifecycle {
                DesktopLifecycle::Ready => return Ok(()),
                DesktopLifecycle::Failed { error_code }
                | DesktopLifecycle::Crashed { error_code } => {
                    return Err(ReadyFailure {
                        code: DesktopLaunchErrorCode::ExitedBeforeReady,
                        message: format!(
                            "Morphir Desktop reported a launch failure before readiness{}.",
                            error_code
                                .map(|code| format!(" ({code})"))
                                .unwrap_or_default()
                        ),
                    });
                }
                DesktopLifecycle::Exited { exit_code } => {
                    return Err(ReadyFailure {
                        code: DesktopLaunchErrorCode::ExitedBeforeReady,
                        message: format!(
                            "Morphir Desktop exited before readiness{}.",
                            exit_code
                                .map(|code| format!(" Exit code: {code}"))
                                .unwrap_or_default()
                        ),
                    });
                }
            }
        }
        if let Some((status, observed_at)) = observed_exit
            && observed_at.elapsed() >= FORWARDED_READY_GRACE
        {
            return Err(ReadyFailure {
                code: DesktopLaunchErrorCode::ExitedBeforeReady,
                message: format!(
                    "Morphir Desktop exited before reporting readiness. Exit status: {status}."
                ),
            });
        }
        if observed_exit.is_none()
            && let Some(status) = child.try_wait().map_err(|error| ReadyFailure {
                code: DesktopLaunchErrorCode::ExitedBeforeReady,
                message: format!("Failed to observe Morphir Desktop startup: {error}."),
            })?
        {
            observed_exit = Some((status, Instant::now()));
        }
        if Instant::now() >= deadline {
            return Err(ReadyFailure {
                code: DesktopLaunchErrorCode::ReadyTimedOut,
                message: format!(
                    "Morphir Desktop did not report readiness within {} seconds.",
                    READY_TIMEOUT.as_secs()
                ),
            });
        }
        thread::sleep(READY_POLL_INTERVAL);
    }
}

fn find_lifecycle_event(log_root: &Path, launch_id: &str) -> Option<DesktopLifecycle> {
    let mut files = walkdir::WalkDir::new(log_root)
        .into_iter()
        .filter_map(std::result::Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .filter(|entry| {
            entry
                .path()
                .extension()
                .is_some_and(|extension| extension == "jsonl")
        })
        .map(|entry| entry.into_path())
        .collect::<Vec<_>>();
    files.sort_by_key(|path| {
        fs::metadata(path)
            .and_then(|metadata| metadata.modified())
            .ok()
    });
    files.reverse();
    let mut terminal = None;
    for path in files {
        let Ok(contents) = fs::read_to_string(path) else {
            continue;
        };
        for event in contents
            .lines()
            .rev()
            .filter_map(|line| serde_json::from_str::<Value>(line).ok())
        {
            match lifecycle_from_event(&event, launch_id) {
                Some(DesktopLifecycle::Ready) => return Some(DesktopLifecycle::Ready),
                Some(lifecycle) if terminal.is_none() => terminal = Some(lifecycle),
                _ => {}
            }
        }
    }
    terminal
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
        let log = temporary.path().join("desktop.jsonl");
        fs::write(
            log,
            concat!(
                "{\"fields\":{\"event_name\":\"desktop.ready\",\"launch_id\":\"launch-expected\"}}\n",
                "{\"fields\":{\"event_name\":\"desktop.exit\",\"launch_id\":\"launch-expected\",\"exit_code\":0}}\n"
            ),
        )
        .unwrap();

        assert_eq!(
            find_lifecycle_event(temporary.path(), "launch-expected"),
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
