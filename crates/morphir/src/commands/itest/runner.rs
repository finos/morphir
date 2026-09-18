use super::{
    Scenario,
    model::{CaptureFormat, Step, relative_path},
};
use anyhow::{Context, Result, bail, ensure};
use morphir_evaluator::{
    CONTRACT_VERSION, EvaluationOutcome, EvaluationReport, EvaluationRequest, ProviderId,
};
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, Instant},
};

#[derive(Debug)]
pub struct ProcessOutput {
    pub code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
}

pub fn execute(mut command: Command, logs: &Path, timeout: Duration) -> Result<ProcessOutput> {
    // Files avoid pipe deadlocks and keep diagnostics available on timeout.
    let stdout = logs.join("stdout.log");
    let stderr = logs.join("stderr.log");
    command
        .stdin(Stdio::null())
        .stdout(fs::File::create(&stdout)?)
        .stderr(fs::File::create(&stderr)?);
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }
    #[cfg(windows)]
    let (job, mut child) = super::windows_job::Job::spawn(&mut command)?;
    #[cfg(not(windows))]
    let mut child = command.spawn().context("start CLI process")?;
    let start = Instant::now();
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break status;
        }
        if start.elapsed() >= timeout {
            #[cfg(windows)]
            let tree_result = job.terminate();
            #[cfg(not(windows))]
            let tree_result = terminate_tree(&mut child);
            let _ = child.kill();
            child.wait().context("reap timed-out CLI process")?;
            tree_result.context("terminate timed-out CLI descendants")?;
            bail!(
                "timed out after {timeout:?}\nstdout:\n{}\nstderr:\n{}",
                fs::read_to_string(stdout)?,
                fs::read_to_string(stderr)?
            );
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    #[cfg(windows)]
    job.terminate()?;
    #[cfg(unix)]
    terminate_tree(&mut child).context("clean up CLI descendants")?;
    Ok(ProcessOutput {
        code: status.code(),
        stdout: fs::read_to_string(stdout)?,
        stderr: fs::read_to_string(stderr)?,
    })
}

fn confined(root: &Path, relative: &str) -> Result<PathBuf> {
    relative_path(relative)?;
    let mut path = root.to_owned();
    for component in Path::new(relative).components() {
        path.push(component);
        match fs::symlink_metadata(&path) {
            Ok(metadata) => ensure!(
                !metadata.file_type().is_symlink(),
                "assertion traverses a symlink: {}",
                path.display()
            ),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
    }
    Ok(path)
}

pub fn run(scenario: &Scenario, binary: &Path, keep: bool) -> Result<()> {
    let temp = tempfile::Builder::new()
        .prefix("morphir-example-")
        .tempdir()?;
    if keep {
        let root = temp.keep();
        eprintln!("{}: retained {}", scenario.id, root.display());
        run_in_temporary(scenario, binary, &root)
    } else {
        run_in_temporary(scenario, binary, temp.path())
    }
}

fn isolated_command(binary: &Path, workspace: &Path, root: &Path) -> Command {
    let mut command = Command::new(binary);
    command.current_dir(workspace);
    for (key, _) in std::env::vars_os() {
        if is_morphir_environment(&key) {
            command.env_remove(key);
        }
    }
    command
        .env("MORPHIR_HOME", root.join("home"))
        .env("MORPHIR_LOG_FILE", "false")
        .env("XDG_CONFIG_HOME", root.join("config"))
        .env("HOME", root.join("user"))
        .env("USERPROFILE", root.join("user"))
        .env("APPDATA", root.join("config"))
        .env("LOCALAPPDATA", root.join("local"));
    command
}

pub(super) fn observation(step: &Step, output: &ProcessOutput, project: &Path) -> Result<Value> {
    let code = output
        .code
        .context("CLI terminated without a normal exit code")?;
    let mut input = serde_json::json!({"version":1,"exitCode":code,"stdout":output.stdout,"stderr":output.stderr,"artifacts":{}});
    if step.stdout_json {
        input["stdoutJson"] =
            serde_json::from_str(&output.stdout).context("requested stdout JSON is malformed")?;
    }
    for capture in &step.captures {
        let path = confined(project, &capture.path)?;
        let value = if !path.try_exists()? {
            serde_json::json!({"kind":"missing"})
        } else {
            ensure!(
                path.is_file(),
                "capture {} is not a regular file",
                capture.name
            );
            match capture.format {
                CaptureFormat::Exists => serde_json::json!({"kind":"file"}),
                CaptureFormat::Text => {
                    serde_json::json!({"kind":"text","value":fs::read_to_string(path)?})
                }
                CaptureFormat::Json => {
                    let value: Value = serde_json::from_str(&fs::read_to_string(path)?)
                        .with_context(|| format!("capture {} is not valid JSON", capture.name))?;
                    serde_json::json!({"kind":"json","value":value})
                }
            }
        };
        input["artifacts"][&capture.name] = value;
    }
    Ok(input)
}

fn run_in_temporary(scenario: &Scenario, binary: &Path, root: &Path) -> Result<()> {
    // Project and enclosing-workspace discovery both walk ancestors. A local
    // .morphir directory only bounds outputs, not configuration discovery.
    for ancestor in root.canonicalize()?.ancestors().skip(1) {
        let config = morphir_devkit::config::discover_config_at(ancestor)
            .context("itest cannot isolate temporary ancestor configuration")?;
        ensure!(
            config.is_none(),
            "itest cannot isolate temporary ancestor configuration at {}; choose a clean TMPDIR/TEMP",
            config.unwrap_or_default().display()
        );
    }
    let project = root.join("project");
    fs::create_dir_all(&project)?;
    fs::create_dir_all(root.join("home"))?;
    super::workspace::materialize(scenario, &project)?;
    fs::create_dir_all(project.join(".morphir"))?;
    for (index, step) in scenario.steps.iter().enumerate() {
        let logs = root.join(format!("step-{}", index + 1));
        fs::create_dir_all(&logs)?;
        let mut command = isolated_command(binary, &project, root);
        command.args(&step.args);
        let context = format!(
            "{} cell {} {:?}: morphir {:?}",
            scenario.id, step.id, step.name, step.args
        );
        let output = execute(command, &logs, Duration::from_secs(step.timeout_seconds))
            .with_context(|| context.clone())?;
        let diagnostics = format!(
            "{context}\nexit: {:?}\nstdout:\n{}\nstderr:\n{}",
            output.code, output.stdout, output.stderr
        );
        let input = observation(step, &output, &project).with_context(|| diagnostics.clone())?;
        fs::write(
            logs.join("observation.json"),
            serde_json::to_vec_pretty(&input)?,
        )?;
        for assertion in &step.assertions {
            let harness = logs.join(&assertion.id);
            fs::create_dir_all(&harness)?;
            let request: EvaluationRequest = serde_json::from_value(serde_json::json!({
                "version":1,"provider":scenario.metadata.provider,
                "program":{"kind":"source","language":"rego","modules":[{"path":format!("{}.rego",assertion.id),"source":assertion.source}]},
                "entrypoints":assertion.entrypoints,"input":input,"timeout_ms":step.timeout_seconds * 1000
            }))?;
            let request_path = harness.join("request.json");
            fs::write(&request_path, serde_json::to_vec_pretty(&request)?)?;
            let mut eval = isolated_command(binary, &harness, root);
            eval.arg("eval")
                .arg("--request")
                .arg(&request_path)
                .arg("--json");
            let checked = execute(eval, &harness, Duration::from_secs(step.timeout_seconds))
                .with_context(|| format!("{diagnostics}\nassertion cell {}", assertion.id))?;
            let assertion_context = format!(
                "{diagnostics}\nassertion cell {}\nevaluator stdout:\n{}\nevaluator stderr:\n{}",
                assertion.id, checked.stdout, checked.stderr
            );
            ensure!(
                checked.code == Some(0),
                "{assertion_context}\nevaluator failed: {:?}",
                checked.code
            );
            check_report(
                &checked.stdout,
                scenario.metadata.provider,
                &assertion.entrypoints,
            )
            .with_context(|| assertion_context)?;
        }
    }
    Ok(())
}

pub(super) fn check_report(text: &str, provider: ProviderId, entrypoints: &[String]) -> Result<()> {
    let report: EvaluationReport =
        serde_json::from_str(text).context("invalid evaluator JSON report")?;
    ensure!(
        report.version == CONTRACT_VERSION && report.provider == provider,
        "evaluator report version/provider mismatch"
    );
    ensure!(
        report.results.len() == entrypoints.len(),
        "evaluator returned the wrong number of results"
    );
    for (result, entrypoint) in report.results.iter().zip(entrypoints) {
        ensure!(
            result.entrypoint == *entrypoint,
            "evaluator result does not match requested rule {entrypoint}"
        );
        ensure!(
            matches!(
                &result.outcome,
                EvaluationOutcome::Value {
                    value: Value::Bool(true)
                }
            ),
            "assertion {entrypoint} failed: {:?}",
            result.outcome
        );
    }
    Ok(())
}

#[cfg(unix)]
fn terminate_tree(child: &mut std::process::Child) -> Result<()> {
    use rustix::process::{Pid, Signal, kill_process_group};
    let pid = Pid::from_raw(child.id() as i32).context("invalid child process id")?;
    match kill_process_group(pid, Signal::KILL) {
        Ok(()) | Err(rustix::io::Errno::SRCH) => Ok(()),
        Err(error) => Err(error.into()),
    }
}

#[cfg(not(any(unix, windows)))]
fn terminate_tree(child: &mut std::process::Child) -> Result<()> {
    child.kill()?;
    Ok(())
}

pub(super) fn is_morphir_environment(name: &std::ffi::OsStr) -> bool {
    name.to_string_lossy()
        .get(..8)
        .is_some_and(|prefix| prefix.eq_ignore_ascii_case("MORPHIR_"))
}
