//! Thin command layer for the shared executable MEP guest suite.
use super::{Outcome, finish};
use clap::Args;
use morphir_mck::{
    mep::{Identity, check_report_file, load_kit, run_process},
    transport::Limits,
};
use starbase::AppResult;
use std::{ffi::OsString, path::PathBuf, time::Duration};

#[derive(Clone, Args)]
pub struct RunArgs {
    /// Independently authored guest profile and fixed expectations
    #[arg(long, default_value = "spec/mep/mck/guest-moonbit-bool.json")]
    kit: PathBuf,
    /// Refuse to execute unless the kit has this SHA-256 digest
    #[arg(long)]
    expect_kit_sha256: Option<String>,
    /// MEP host executable, launched directly without a shell
    #[arg(long)]
    host: PathBuf,
    /// Host argument, repeated in order
    #[arg(long = "host-arg", allow_hyphen_values = true)]
    host_args: Vec<OsString>,
    /// Pin a guest or host artifact by its exact bytes; repeat for each input
    #[arg(long = "identity-file", required = true)]
    identity_files: Vec<PathBuf>,
    /// Complete observations and executable/corpus/artifact identities
    #[arg(long)]
    report: PathBuf,
    #[arg(long, default_value_t = 30_000)]
    timeout: u64,
}
#[derive(Clone, Args)]
pub struct CheckArgs {
    #[arg(long, default_value = "spec/mep/mck/guest-moonbit-bool.json")]
    kit: PathBuf,
    /// Saved guest report to independently adjudicate again
    report: PathBuf,
}
pub fn run(args: RunArgs) -> AppResult<miette::Report> {
    let result = (|| -> Result<bool, String> {
        let kit = load_kit(&args.kit)?;
        if args.expect_kit_sha256.is_some_and(|d| d != kit.digest) {
            return Err("MEP corpus SHA-256 does not match pin".into());
        }
        let identity = Identity::capture(&args.host, &args.host_args, &args.identity_files)?;
        let report = run_process(
            &kit,
            identity,
            Limits {
                request_timeout: Duration::from_millis(args.timeout),
                ..Limits::DEFAULT
            },
        );
        if let Some(parent) = args.report.parent().filter(|p| !p.as_os_str().is_empty()) {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        std::fs::write(
            &args.report,
            format!("{}\n", serde_json::to_string_pretty(&report).unwrap()),
        )
        .map_err(|e| e.to_string())?;
        println!(
            "MEP guest {}: {} observations, qualified={}",
            kit.profile(),
            report.records.len(),
            report.qualified
        );
        if let Some(error) = report.error {
            eprintln!("MEP guest: {error}");
        }
        Ok(report.qualified)
    })();
    finish(match result {
        Ok(true) => Outcome::Passed,
        Ok(false) => Outcome::Failed,
        Err(e) => Outcome::Error(e),
    })
}
pub fn check(args: CheckArgs) -> AppResult<miette::Report> {
    let result = (|| -> Result<(), String> {
        let kit = load_kit(&args.kit)?;
        check_report_file(&kit, &args.report)
    })();
    finish(match result {
        Ok(()) => {
            println!("MEP guest report: qualified");
            Outcome::Passed
        }
        Err(e) => Outcome::Error(e),
    })
}
