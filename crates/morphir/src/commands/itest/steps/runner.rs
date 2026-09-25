//! The CLI runner that runs an itest scenario's commands with itest's own isolation.
use super::ItestDirs;
use crate::commands::itest::runner::{ProcessOutput, execute, isolated_command};
use morphir_bdd::steps::{
    cli::{CliRequest, CliRunner},
    output::LastOutput,
};
use std::{fs, future::Future, pin::Pin, sync::atomic::Ordering, time::Duration};

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
            let step = dirs.step.fetch_add(1, Ordering::SeqCst) + 1;
            let logs = dirs.root.join(format!("step-{step}"));
            let mut command = isolated_command(&request.program.path, &dirs.project, &dirs.root);
            command.args(request.args);
            let timeout = request.timeout.unwrap_or(DEFAULT_TIMEOUT);
            let context = format!("step {step}: {} {:?}", request.program.name, request.args);
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
        })
    }
}
