//! CLI boundaries for parent-owned Workbench codec qualification.

mod adapter_selection;
pub(in crate::commands) mod installed_launch;

use adapter_selection::{AdapterSelectionError, WorkbenchAdapter};
use installed_launch::{InstalledTarget, WorkbenchLaunch};

use std::ffi::OsString;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use std::time::Duration;

use clap::Args;
use morphir_mck::transport::{Limits, Session};
use morphir_mck::workbench::{
    AdapterProtocol, MAX_REPORT_BYTES, Report, RunConfiguration, check_report_configured,
    run_configured_with_installed_client_adapter, run_configured_with_native_adapter,
    run_configured_with_session_factory,
};
use starbase::AppResult;

use super::{Outcome, finish};

#[derive(Args, Clone, Debug)]
pub struct RunArgs {
    /// Workbench corpus directory containing cases.json; no embedded IR kit is used
    #[arg(long, value_name = "DIR")]
    pub kit: PathBuf,
    /// Adapter executable or builtin:morphir-workbench; external programs use no shell
    #[arg(long, value_name = "PROGRAM")]
    pub adapter: OsString,
    /// An argument for the adapter; repeat for more
    #[arg(long = "adapter-arg", value_name = "ARG", allow_hyphen_values = true)]
    pub adapter_args: Vec<OsString>,
    /// Write versioned JSON evidence, including adapter and qualification failures
    #[arg(long, value_name = "FILE")]
    pub report: PathBuf,
    /// Explicit caller-owned checker policy; required for selected workflow corpora
    #[arg(long, value_name = "FILE")]
    pub checker_policy: Option<PathBuf>,
    /// Explicit installed client launch kind; only the matching builtin policy accepts it
    #[arg(long, value_enum)]
    installed_client_target: Option<InstalledTarget>,
    /// Absolute installed package directory; lexical input until observed by a producer
    #[arg(long, value_name = "DIR")]
    installed_client_package: Option<PathBuf>,
    /// Absolute Node executable shared by the installed client and its helpers
    #[arg(long, value_name = "PROGRAM")]
    installed_client_node: Option<PathBuf>,
    /// Absolute native installed executable; required for native, forbidden for node
    #[arg(long, value_name = "PROGRAM")]
    installed_client_program: Option<PathBuf>,
    /// Absolute source checkout association input; this does not prove build provenance
    #[arg(long, value_name = "DIR")]
    installed_client_source_checkout: Option<PathBuf>,
    /// Maximum duration of one adapter exchange, in milliseconds
    #[arg(long, value_name = "MS", default_value_t = 30_000, value_parser = clap::value_parser!(u64).range(1..))]
    pub timeout: u64,
    /// Maximum duration of the adapter session, in milliseconds
    #[arg(long, value_name = "MS", default_value_t = 1_800_000, value_parser = clap::value_parser!(u64).range(1..))]
    pub session_timeout: u64,
}

fn configuration(path: Option<&Path>) -> Result<RunConfiguration, String> {
    let Some(path) = path else {
        // Historical dispatch alone keeps its existing default. Selected
        // source is refused by the shared runner without explicit policy.
        return RunConfiguration::from_json(r#"{"kind":"historical"}"#);
    };
    let mut text = String::new();
    std::fs::File::open(path)
        .and_then(|file| {
            file.take(MAX_REPORT_BYTES as u64 + 1)
                .read_to_string(&mut text)
        })
        .map_err(|error| format!("cannot read checker policy {}: {error}", path.display()))?;
    RunConfiguration::from_json(&text).map_err(|error| format!("checker policy refused: {error}"))
}

pub async fn run(args: RunArgs) -> AppResult<miette::Report> {
    match WorkbenchAdapter::parse(&args.adapter, &args.adapter_args) {
        Ok(_) => (),
        Err(AdapterSelectionError::BuiltinArguments) => {
            return finish(Outcome::Usage(
                "builtin:morphir-workbench does not accept --adapter-arg".into(),
            ));
        }
    };
    let configuration = match configuration(args.checker_policy.as_deref()) {
        Ok(configuration) => configuration,
        Err(error) => return finish(Outcome::Error(error)),
    };
    let adapter = match WorkbenchLaunch::select(&args, configuration.execution_mode()) {
        Ok(selected) => selected,
        Err(error) => return finish(Outcome::Usage(error.to_string())),
    };
    let source = args.kit.join("cases.json");
    let same_source = if args.report.exists() {
        match same_file::is_same_file(&source, &args.report) {
            Ok(same) => same,
            Err(error) => {
                return finish(Outcome::Error(format!(
                    "cannot compare corpus and report paths: {error}"
                )));
            }
        }
    } else {
        false
    };
    if args.report == source || same_source {
        return finish(Outcome::Usage(
            "report output must not overwrite the independent corpus".into(),
        ));
    }
    let limits = Limits {
        request_timeout: Duration::from_millis(args.timeout),
        session_timeout: Duration::from_millis(args.session_timeout),
        ..Limits::DEFAULT
    };
    let mut interrupt = None;
    let interrupted = Arc::new(AtomicBool::new(false));
    let report = tokio::task::block_in_place(|| match adapter {
        WorkbenchLaunch::InstalledClient(launch) => {
            let cancellation = Arc::clone(&interrupted);
            interrupt = Some(tokio::spawn(async move {
                if tokio::signal::ctrl_c().await.is_ok() {
                    cancellation.store(true, Ordering::SeqCst);
                }
            }));
            let mut adapter = crate::commands::ui::installed_mck::InstalledWorkbenchAdapter::new(
                launch,
                limits,
                Arc::clone(&interrupted),
            );
            run_configured_with_installed_client_adapter(&args.kit, &configuration, &mut adapter)
        }
        WorkbenchLaunch::NativeHost => {
            let cancellation = Arc::clone(&interrupted);
            interrupt = Some(tokio::spawn(async move {
                if tokio::signal::ctrl_c().await.is_ok() {
                    cancellation.store(true, Ordering::SeqCst);
                }
            }));
            // Construction stores bounds and cancellation only. The shared
            // engine validates the source before issuing the actual invocation.
            let mut adapter = crate::commands::ui::native_mck::NativeWorkbenchAdapter::new(
                limits,
                Arc::clone(&interrupted),
            );
            run_configured_with_native_adapter(&args.kit, &configuration, &mut adapter)
        }
        WorkbenchLaunch::External { program, arguments } => {
            run_configured_with_session_factory(&args.kit, &configuration, || {
                // The shared runner finishes source preparation BEFORE invoking
                // this real process factory. No expected data/context crosses it.
                let session = match configuration.adapter_protocol() {
                    AdapterProtocol::HistoricalNewline => {
                        Session::spawn(&args.adapter, arguments, limits)
                    }
                    AdapterProtocol::ContentLength => {
                        Session::spawn_mep(program, arguments, limits)
                    }
                }?;
                let terminator = session.terminator();
                let interrupted = Arc::clone(&interrupted);
                interrupt = Some(tokio::spawn(async move {
                    if tokio::signal::ctrl_c().await.is_ok() {
                        interrupted.store(true, Ordering::SeqCst);
                        terminator.kill();
                    }
                }));
                Ok(session)
            })
        }
    });
    if let Some(interrupt) = interrupt {
        interrupt.abort();
        let _ = interrupt.await;
    }
    if interrupted.load(Ordering::SeqCst) {
        // External sessions return through close/kill/wait. The builtin owns
        // its host cleanup before returning. Neither publishes a cancelled run.
        eprintln!("error: interrupted; adapter run stopped");
        std::process::exit(130);
    }
    let report = match report {
        Ok(report) => report,
        Err(error) => return finish(Outcome::Error(error)),
    };
    if let Err(error) = super::report::write_atomic(&args.report, report.to_json().as_bytes()) {
        return finish(Outcome::Error(format!(
            "cannot write {}: {error}",
            args.report.display()
        )));
    }
    print_summary(&report);
    finish(if report.qualified() {
        Outcome::Passed
    } else {
        Outcome::Failed
    })
}

#[derive(Args, Clone, Debug)]
pub struct CheckArgs {
    /// Independent Workbench corpus directory containing cases.json
    #[arg(long, value_name = "DIR")]
    pub kit: PathBuf,
    /// Saved Workbench JSON evidence; its claimed results are independently recomputed
    #[arg(long, value_name = "FILE")]
    pub report: PathBuf,
    /// Same explicit caller-owned policy used for selected workflow verification
    #[arg(long, value_name = "FILE")]
    pub checker_policy: Option<PathBuf>,
}

pub fn check(args: CheckArgs) -> AppResult<miette::Report> {
    let result = (|| {
        let configuration = configuration(args.checker_policy.as_deref())?;
        let mut text = String::new();
        std::fs::File::open(&args.report)
            .and_then(|file| {
                file.take(MAX_REPORT_BYTES as u64 + 1)
                    .read_to_string(&mut text)
            })
            .map_err(|error| format!("cannot read {}: {error}", args.report.display()))?;
        let report = Report::from_json(&text)?;
        check_report_configured(&args.kit, &report, &configuration)?;
        print_summary(&report);
        Ok::<_, String>(report.qualified())
    })();
    finish(match result {
        Ok(true) => Outcome::Passed,
        Ok(false) => Outcome::Failed,
        Err(error) => Outcome::Error(error),
    })
}

fn print_summary(report: &Report) {
    println!(
        "workbench: {}; {}",
        report.summary_line(),
        if report.qualified() {
            "qualified"
        } else {
            "not qualified"
        }
    );
    if let Some(historical) = report.as_historical() {
        for record in &historical.records {
            if record.result != morphir_mck::workbench::ResultKind::Pass {
                println!("{}: {:?}", record.case_id, record.result);
            }
        }
        for failure in &historical.errors {
            eprintln!("workbench {:?}: {}", failure.phase, failure.message);
        }
    }
}

#[cfg(test)]
#[path = "workbench/installed_launch/tests.rs"]
mod installed_launch_tests;

#[cfg(test)]
#[path = "workbench/operation_record_tests.rs"]
mod operation_record_tests;
