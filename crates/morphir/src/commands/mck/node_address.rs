//! CLI arguments and output for the shared node-address MCK suite.

use clap::Args;
use morphir_mck::node_address::{load_kit, run_process};
use morphir_mck::transport::Limits;
use starbase::AppResult;
use std::ffi::OsString;
use std::path::PathBuf;
use std::time::Duration;

use super::{Outcome, finish};

#[derive(Clone, Args)]
pub struct RunArgs {
    /// Fixed V3/V4 node-address case file
    #[arg(long, default_value = "spec/ir/mck/node-address-draft.json")]
    pub kit: PathBuf,
    /// Adapter executable, launched without a shell
    #[arg(long)]
    pub adapter: OsString,
    /// Adapter argument; repeat to pass --suite node-address
    #[arg(long = "adapter-arg", allow_hyphen_values = true)]
    pub adapter_args: Vec<OsString>,
    /// Write the JSON report to this file
    #[arg(long)]
    pub report: Option<PathBuf>,
    /// Maximum milliseconds per adapter exchange
    #[arg(long, default_value_t = 30_000)]
    pub timeout: u64,
}

pub fn run(args: RunArgs) -> AppResult<miette::Report> {
    let kit = match load_kit(&args.kit) {
        Ok(kit) => kit,
        Err(error) => return finish(Outcome::Error(error)),
    };
    let limits = Limits {
        request_timeout: Duration::from_millis(args.timeout),
        ..Limits::DEFAULT
    };
    let report = run_process(&kit, &args.adapter, &args.adapter_args, limits);
    if let Some(path) = &args.report {
        let text = serde_json::to_string_pretty(&report).expect("serializable report");
        if let Some(parent) = path.parent().filter(|path| !path.as_os_str().is_empty())
            && let Err(error) = std::fs::create_dir_all(parent)
        {
            return finish(Outcome::Error(format!("{}: {error}", parent.display())));
        }
        if let Err(error) = std::fs::write(path, format!("{text}\n")) {
            return finish(Outcome::Error(format!("{}: {error}", path.display())));
        }
    }
    for record in &report.records {
        if let Some(message) = &record.message {
            println!("{}: {message}", record.case_id);
        }
    }
    if let Some(error) = &report.error {
        eprintln!("node-address MCK: {error}");
    }
    println!(
        "node-address: {} cases, {} passed",
        report.records.len(),
        report
            .records
            .iter()
            .filter(|record| matches!(record.result, morphir_mck::node_address::ResultKind::Pass))
            .count()
    );
    finish(if report.passed() {
        Outcome::Passed
    } else {
        Outcome::Failed
    })
}
