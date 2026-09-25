//! The CLI runner that runs an itest scenario's commands with itest's own isolation.
use super::ItestDirs;
use crate::commands::itest::runner::{ProcessOutput, execute, isolated_command};
use morphir_bdd::steps::{
    cli::{CliProgram, CliRequest, CliRunner},
    output::LastOutput,
};
use std::{fs, future::Future, path::Path, pin::Pin, sync::atomic::Ordering, time::Duration};

/// The timeout of a command whose step names none.
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(120);

/// The CLI runner that runs `morphir` with itest's isolation (`isolated_command`), per-step logs
/// under `root/step-N/`, the step timeout (default 120 s, as `model` does today), and
/// process-tree termination.
///
/// It reads the scenario's [`ItestDirs`] from the request's context, so `MaterializeExample`
/// must have prepared the scenario first.
#[derive(Debug)]
pub struct ItestRunner;

impl CliRunner for ItestRunner {
    fn run<'a>(
        &'a self,
        request: CliRequest<'a>,
    ) -> Pin<Box<dyn Future<Output = Result<LastOutput, String>> + Send + 'a>> {
        Box::pin(async move {
            let dirs = request.context.get::<ItestDirs>().cloned().ok_or_else(|| {
                "no itest directories: the `MaterializeExample` processor must prepare the \
                 scenario before `When I run`"
                    .to_owned()
            })?;
            // This is a `When I run`: advance `command` (not just `step`, which
            // `run_isolated` below advances for every isolated subprocess, including the
            // policy step's own internal `morphir eval` calls) and record its timeout for the
            // policy step to reuse.
            dirs.command.fetch_add(1, Ordering::SeqCst);
            *dirs
                .last_timeout
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = request.timeout;
            *dirs
                .last_command_line
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) =
                Some(format!("{} {:?}", request.program.name, request.args));
            let timeout = request.timeout.unwrap_or(DEFAULT_TIMEOUT);
            let project = dirs.project.clone();
            run_isolated(request.program, request.args, &dirs, &project, timeout).await
        })
    }
}

/// Runs `program` with `args` in `cwd`, with itest's own isolation (`isolated_command`), a fresh
/// `root/step-N/` log directory (`execute`'s own `stdout.log`/`stderr.log`), process-tree
/// termination, and `timeout`.
///
/// Shared by [`ItestRunner::run`] (`cwd` is the scenario's project, `dirs.project`) and the policy
/// step's own internal `morphir eval` call (`cwd` is that check's own harness directory), so both
/// get the same isolation and the same cleanup; `dirs.root` is where the isolated home directories
/// live either way. Both callers' invocations share `dirs.step`'s numbering, so a scenario's
/// `step-N` directories are not all `When I run` commands; see [`ItestDirs::step`].
pub(crate) async fn run_isolated(
    program: &CliProgram,
    args: &[String],
    dirs: &ItestDirs,
    cwd: &Path,
    timeout: Duration,
) -> Result<LastOutput, String> {
    let step = dirs.step.fetch_add(1, Ordering::SeqCst) + 1;
    let logs = dirs.root.join(format!("step-{step}"));
    let mut command = isolated_command(&program.path, cwd, &dirs.root);
    command.args(args);
    let context = format!("step {step}: {} {:?}", program.name, args);
    let output = tokio::task::spawn_blocking(move || -> anyhow::Result<ProcessOutput> {
        fs::create_dir_all(&logs)?;
        execute(command, &logs, timeout)
    })
    .await
    .map_err(|error| format!("{context}: {error}"))?
    .map_err(|error| format!("{:#}", error.context(context)))?;
    Ok(LastOutput {
        stdout: output.stdout,
        stderr: output.stderr,
        status: output.code,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `run_isolated` is `pub(crate)`, so unlike `ItestRunner` (whose `CliRunner::run` always uses
    /// `dirs.project`) it can only be exercised from inside this crate — this is that exercise, for
    /// the policy step's own use of it with a `cwd` other than the project.
    #[cfg(unix)]
    #[tokio::test]
    async fn run_isolated_runs_the_process_in_the_given_working_directory() {
        let temp = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(temp.path().join("project")).unwrap();
        let dirs = ItestDirs::new(temp.path());
        let harness = temp.path().join("policy-1");
        std::fs::create_dir_all(&harness).unwrap();
        let program = CliProgram {
            name: "sh".into(),
            path: "/bin/sh".into(),
        };
        let args = vec!["-c".to_owned(), "pwd".to_owned()];

        let in_project = run_isolated(
            &program,
            &args,
            &dirs,
            &dirs.project,
            Duration::from_secs(5),
        )
        .await
        .unwrap();
        assert_eq!(
            Path::new(in_project.stdout.trim()).canonicalize().unwrap(),
            dirs.project.canonicalize().unwrap(),
            "stdout={}",
            in_project.stdout
        );

        // A different `cwd` — the policy step's own harness directory, not the project — is
        // honored the same way.
        let in_harness = run_isolated(&program, &args, &dirs, &harness, Duration::from_secs(5))
            .await
            .unwrap();
        assert_eq!(
            Path::new(in_harness.stdout.trim()).canonicalize().unwrap(),
            harness.canonicalize().unwrap(),
            "stdout={}",
            in_harness.stdout
        );

        // Both calls share `dirs.step`'s numbering regardless of `cwd`.
        assert!(temp.path().join("step-1/stdout.log").is_file());
        assert!(temp.path().join("step-2/stdout.log").is_file());
    }
}
