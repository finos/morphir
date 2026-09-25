use super::{
    Scenario,
    model::{Assertion, AssertionKind, CaptureFormat, ExpectedText, Step, relative_path},
};
use anyhow::{Context, Result, bail, ensure};
use morphir_evaluator::{
    CONTRACT_VERSION, EvaluationOutcome, EvaluationReport, EvaluationRequest, ProviderId,
};
use serde_json::Value;
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, Instant},
};
use tempfile::TempDir;

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
    let (root, _temp) = temporary_root(&scenario.id, keep)?;
    run_in_temporary(scenario, binary, &root)
}

/// A new temporary root for scenario `id`. With `keep`, the root outlives the run: its path is
/// printed and no guard is returned. Otherwise the returned guard deletes it when dropped.
pub(super) fn temporary_root(id: &str, keep: bool) -> Result<(PathBuf, Option<TempDir>)> {
    let temp = tempfile::Builder::new()
        .prefix("morphir-example-")
        .tempdir()?;
    if keep {
        let root = temp.keep();
        eprintln!("{id}: retained {}", root.display());
        Ok((root, None))
    } else {
        Ok((temp.path().to_owned(), Some(temp)))
    }
}

/// Create `root/project` and `root/home`, fill the project with `materialize`, then add the
/// project's `.morphir` directory. Returns the project directory.
pub(super) fn prepare_root(
    root: &Path,
    materialize: impl FnOnce(&Path) -> Result<()>,
) -> Result<PathBuf> {
    let project = root.join("project");
    fs::create_dir_all(&project)?;
    fs::create_dir_all(root.join("home"))?;
    materialize(&project)?;
    fs::create_dir_all(project.join(".morphir"))?;
    Ok(project)
}

pub(super) fn isolated_command(binary: &Path, workspace: &Path, root: &Path) -> Command {
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

fn read_text(root: &Path, relative: &str) -> Result<String> {
    let path = confined(root, relative)?;
    ensure!(
        path.is_file(),
        "golden file {relative:?} is missing or is not a regular file"
    );
    fs::read_to_string(&path).with_context(|| format!("read UTF-8 golden file {relative:?}"))
}

fn expected_texts(scenario: &Scenario) -> Result<BTreeMap<&str, String>> {
    scenario
        .steps
        .iter()
        .flat_map(|step| &step.assertions)
        .filter_map(|assertion| {
            let AssertionKind::Golden(golden) = &assertion.kind else {
                return None;
            };
            let expected = match &golden.expected {
                ExpectedText::Inline(text) => Ok(text.clone()),
                ExpectedText::File(path) => read_text(&scenario.directory, path),
            };
            Some(
                expected
                    .map(|text| (assertion.id.as_str(), text))
                    .with_context(|| {
                        format!(
                            "{} golden {}: load expectation before commands",
                            scenario.id, assertion.id
                        )
                    }),
            )
        })
        .collect()
}

struct PreparedAssertion {
    source: String,
    entrypoints: Vec<String>,
    input: Value,
    mismatch: Option<String>,
}

fn prepare_assertion(
    assertion: &Assertion,
    input: &Value,
    project: &Path,
    expected: &BTreeMap<&str, String>,
) -> Result<PreparedAssertion> {
    match &assertion.kind {
        AssertionKind::Rego {
            source,
            entrypoints,
        } => Ok(PreparedAssertion {
            source: source.clone(),
            entrypoints: entrypoints.clone(),
            input: input.clone(),
            mismatch: None,
        }),
        AssertionKind::Golden(golden) => {
            let actual = read_text(project, &golden.actual)?;
            let selected = golden.select.select(&actual).with_context(|| {
                format!(
                    "golden file {:?}, selection {:?}",
                    golden.actual, golden.select
                )
            })?;
            let actual = golden.line_endings.normalize(selected);
            let expected = golden.line_endings.normalize(
                expected
                    .get(assertion.id.as_str())
                    .context("missing prepared golden expectation")?,
            );
            let mismatch = (actual != expected).then(|| {
                format!(
                    "golden mismatch: {:?}, selection {:?}, expected {:?}\n{}",
                    golden.actual,
                    golden.select,
                    match &golden.expected {
                        ExpectedText::File(path) => path.as_str(),
                        ExpectedText::Inline(_) => "inline text",
                    },
                    super::golden::diff(&expected, &actual)
                )
            });
            let mut input = input.clone();
            input["golden"] = serde_json::json!({"actual":actual,"expected":expected});
            Ok(PreparedAssertion {
                source: "package morphir_golden\nimport rego.v1\ndefault matches := false\nmatches if { input.exitCode == 0; input.golden.actual == input.golden.expected }\n".into(),
                entrypoints: vec!["data.morphir_golden.matches".into()], input, mismatch,
            })
        }
    }
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
    // Freeze authored expectations before any CLI command can change files.
    let expected = expected_texts(scenario)?;
    let project = prepare_root(root, |project| {
        super::workspace::materialize(scenario, project)
    })?;
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
            let prepared = prepare_assertion(assertion, &input, &project, &expected)
                .with_context(|| format!("{diagnostics}\nassertion cell {}", assertion.id))?;
            let request: EvaluationRequest = serde_json::from_value(serde_json::json!({
                "version":1,"provider":scenario.metadata.provider,
                "program":{"kind":"source","language":"rego","modules":[{"path":format!("{}.rego",assertion.id),"source":prepared.source}]},
                "entrypoints":prepared.entrypoints,"input":prepared.input,"timeout_ms":step.timeout_seconds * 1000
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
                &prepared.entrypoints,
            )
            .with_context(|| match prepared.mismatch {
                Some(diff) => format!("{assertion_context}\n{diff}"),
                None => assertion_context,
            })?;
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
