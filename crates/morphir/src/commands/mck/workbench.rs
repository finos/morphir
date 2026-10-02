//! CLI boundaries for parent-owned Workbench codec qualification.

use std::ffi::OsString;
use std::io::Read;
use std::path::PathBuf;
use std::time::Duration;

use clap::Args;
use morphir_mck::transport::{Limits, Session};
use morphir_mck::workbench::{MAX_REPORT_BYTES, Report, check_report, load, run_with_session};
use starbase::AppResult;

use super::{Outcome, finish};

#[derive(Args, Clone, Debug)]
pub struct RunArgs {
    /// Workbench corpus directory containing cases.json; no embedded IR kit is used
    #[arg(long, value_name = "DIR")]
    pub kit: PathBuf,
    /// Adapter executable, launched directly without a shell
    #[arg(long, value_name = "PROGRAM")]
    pub adapter: OsString,
    /// An argument for the adapter; repeat for more
    #[arg(long = "adapter-arg", value_name = "ARG", allow_hyphen_values = true)]
    pub adapter_args: Vec<OsString>,
    /// Write versioned JSON evidence, including adapter and qualification failures
    #[arg(long, value_name = "FILE")]
    pub report: PathBuf,
    /// Maximum duration of one adapter exchange, in milliseconds
    #[arg(long, value_name = "MS", default_value_t = 30_000, value_parser = clap::value_parser!(u64).range(1..))]
    pub timeout: u64,
    /// Maximum duration of the adapter session, in milliseconds
    #[arg(long, value_name = "MS", default_value_t = 1_800_000, value_parser = clap::value_parser!(u64).range(1..))]
    pub session_timeout: u64,
}

pub async fn run(args: RunArgs) -> AppResult<miette::Report> {
    let corpus = match load(&args.kit) {
        Ok(corpus) => corpus,
        Err(error) => return finish(Outcome::Error(error)),
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
    let report = match Session::spawn(&args.adapter, &args.adapter_args, limits) {
        Err(error) => Report::adapter_error(&corpus, error.to_string()),
        Ok(session) => {
            let terminator = session.terminator();
            let interrupt = tokio::spawn(async move {
                if tokio::signal::ctrl_c().await.is_ok() {
                    terminator.kill();
                    eprintln!("error: interrupted; the adapter was terminated");
                    std::process::exit(130);
                }
            });
            let report = tokio::task::block_in_place(|| run_with_session(&corpus, session));
            interrupt.abort();
            report
        }
    };
    if let Err(error) = super::report::write_atomic(&args.report, report.to_json().as_bytes()) {
        return finish(Outcome::Error(format!(
            "cannot write {}: {error}",
            args.report.display()
        )));
    }
    print_summary(&report);
    finish(if report.qualified {
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
}

pub fn check(args: CheckArgs) -> AppResult<miette::Report> {
    let result = (|| {
        let mut text = String::new();
        std::fs::File::open(&args.report)
            .and_then(|file| {
                file.take(MAX_REPORT_BYTES as u64 + 1)
                    .read_to_string(&mut text)
            })
            .map_err(|error| format!("cannot read {}: {error}", args.report.display()))?;
        let report = Report::from_json(&text)?;
        check_report(&args.kit, &report)?;
        print_summary(&report);
        Ok::<_, String>(report.qualified)
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
        if report.qualified {
            "qualified"
        } else {
            "not qualified"
        }
    );
    for record in &report.records {
        if record.result != morphir_mck::workbench::ResultKind::Pass {
            println!("{}: {:?}", record.case_id, record.result);
        }
    }
    for failure in &report.errors {
        eprintln!("workbench {:?}: {}", failure.phase, failure.message);
    }
}
