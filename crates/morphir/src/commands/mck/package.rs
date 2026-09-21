//! Package argument parsing and output. Corpus and execution belong to the MCK engine.
use std::ffi::OsString;
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use clap::Args;
use morphir_mck::json::to_tab_json;
use morphir_mck::package::{Contract, Report, load_kit, run_kit};
use morphir_mck::report::iso_timestamp;
use morphir_mck::transport::{Limits, Session};
use starbase::AppResult;

use super::{Outcome, finish};

#[derive(Args, Clone, Debug)]
pub struct RunArgs {
    /// Package corpus directory, for example spec/package/mck
    #[arg(long, value_name = "DIR")]
    pub kit: PathBuf,
    /// Package contract: 0.1.0-draft.1 integrity or 0.1.0-draft.2 resolution
    #[arg(long, value_name = "VERSION", default_value = "0.1.0-draft.1")]
    pub contract: Contract,
    /// Adapter executable, launched directly without a shell
    #[arg(long, value_name = "PROGRAM")]
    pub adapter: OsString,
    /// An argument for the adapter; repeat for more
    #[arg(long = "adapter-arg", value_name = "ARG", allow_hyphen_values = true)]
    pub adapter_args: Vec<OsString>,
    /// Write the package contract's JSON report to this file
    #[arg(long, value_name = "FILE")]
    pub report: Option<PathBuf>,
    /// Maximum duration of one adapter request and response, in milliseconds
    #[arg(long, value_name = "MS", default_value_t = 30_000, value_parser = clap::value_parser!(u64).range(1..))]
    pub timeout: u64,
    /// Maximum duration of the adapter session, in milliseconds
    #[arg(long, value_name = "MS", default_value_t = 1_800_000, value_parser = clap::value_parser!(u64).range(1..))]
    pub session_timeout: u64,
}

pub async fn run(args: RunArgs) -> AppResult<miette::Report> {
    let kit = load_kit(&args.kit, args.contract);
    let version = env!("CARGO_PKG_VERSION");
    let started_at = iso_timestamp(SystemTime::now());
    let limits = Limits {
        request_timeout: Duration::from_millis(args.timeout),
        session_timeout: Duration::from_millis(args.session_timeout),
        ..Limits::DEFAULT
    };
    let report = if !kit.errors.is_empty() || kit.cases.is_empty() {
        Report::kit_error(&kit, version, &started_at)
    } else {
        match Session::spawn(&args.adapter, &args.adapter_args, limits) {
            Err(error) => Report::adapter_error(&kit, version, &started_at, error.to_string()),
            Ok(session) => {
                let terminator = session.terminator();
                let interrupt = tokio::spawn(async move {
                    if tokio::signal::ctrl_c().await.is_ok() {
                        terminator.kill();
                        eprintln!("error: interrupted; the adapter was terminated");
                        std::process::exit(130);
                    }
                });
                let report =
                    tokio::task::block_in_place(|| run_kit(&kit, session, version, &started_at));
                interrupt.abort();
                report
            }
        }
    };
    if let Some(path) = &args.report {
        let write = || -> std::io::Result<()> {
            if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::write(path, format!("{}\n", to_tab_json(&report)))
        };
        if let Err(error) = write() {
            return finish(Outcome::Error(format!(
                "cannot write {}: {error}",
                path.display()
            )));
        }
    }
    println!("package: {}", report.summary_line());
    for record in &report.records {
        if let Some(message) = &record.message {
            println!("{}: {message}", record.case_id);
        }
    }
    finish(if report.exit_code() == 0 {
        Outcome::Passed
    } else {
        Outcome::Failed
    })
}
