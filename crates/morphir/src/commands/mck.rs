//! `morphir mck` — the Morphir Compatibility Kit command layer.
//!
//! This module owns argument shapes, terminal output and exit status only;
//! the kit grammar, loading, hashing and status live in the `morphir-mck`
//! crate. The contract is `spec/mck/cli-contract.md`: stdout carries the
//! command's result, diagnostics go to stderr, 0 is success, 1 is a failed
//! check or an operational error, and 2 is a usage error (clap's own code).

use std::path::{Path, PathBuf};

use clap::Args;
use morphir_mck::json::to_tab_json;
use morphir_mck::kit::status::{
    KitStatus, MANIFEST_NAME, embedded_status, is_managed, local_status,
};
use morphir_mck::kit::{Kit, KitSource, load_kit};
use serde_json::json;
use starbase::AppResult;

#[derive(Args, Clone, Debug)]
pub struct MckCheckArgs {
    /// The kit directory to validate, for example spec/ir/mck
    pub dir: PathBuf,

    /// Repository root that `text` fences resolve against (inferred when the
    /// kit path ends in spec/ir/mck)
    #[arg(long, value_name = "DIR")]
    pub repo_root: Option<PathBuf>,

    /// Print the files, case ids and errors as JSON on stdout
    #[arg(long)]
    pub json: bool,
}

#[derive(Args, Clone, Debug)]
pub struct MckKitStatusArgs {
    /// A kit directory; the kit embedded in this CLI when omitted
    #[arg(long, value_name = "DIR")]
    pub kit: Option<PathBuf>,

    /// Repository root that `text` fences resolve against (inferred when the
    /// kit path ends in spec/ir/mck)
    #[arg(long, value_name = "DIR")]
    pub repo_root: Option<PathBuf>,

    /// Print the status as JSON on stdout
    #[arg(long)]
    pub json: bool,
}

/// Payload already printed: success is `Ok(None)`, a failed check is
/// `Ok(Some(1))`, and an operational failure prints `error: <msg>` and exits 1.
fn finish(result: Result<bool, String>) -> AppResult<miette::Report> {
    match result {
        Ok(true) => Ok(None),
        Ok(false) => Ok(Some(1)),
        Err(message) => {
            eprintln!("error: {message}");
            Ok(Some(1))
        }
    }
}

/// Loads a kit directory. A vendored snapshot must be verified against its
/// manifest before use; until that lands it is refused rather than read as a
/// raw checkout, so a managed kit is never silently downgraded.
fn load_directory(dir: &Path, repo_root: Option<&Path>) -> Result<Kit, String> {
    let source = KitSource::directory(dir, repo_root);
    if is_managed(source.repo_root()) {
        return Err(format!(
            "{} holds a managed kit snapshot ({MANIFEST_NAME}); this build cannot verify managed kits yet (finos/morphir#851, IR-1V)",
            source
                .repo_root()
                .map(|root| root.display().to_string())
                .unwrap_or_default()
        ));
    }
    load_kit(source).map_err(|error| format!("cannot read kit {}: {error}", dir.display()))
}

pub fn run_mck_check(args: MckCheckArgs) -> AppResult<miette::Report> {
    finish(
        load_directory(&args.dir, args.repo_root.as_deref()).map(|kit| {
            if args.json {
                let errors: Vec<_> = kit
                    .errors
                    .iter()
                    .map(|e| json!({ "file": e.file, "line": e.line, "message": e.message }))
                    .collect();
                let cases: Vec<_> = kit.cases.iter().map(|c| c.id.as_str()).collect();
                println!(
                    "{}",
                    to_tab_json(&json!({ "files": kit.files, "cases": cases, "errors": errors }))
                );
            } else {
                for error in &kit.errors {
                    eprintln!("{}:{}: {}", error.file, error.line, error.message);
                }
                println!(
                    "{} case(s) in {} file(s), {} error(s)",
                    kit.cases.len(),
                    kit.files.len(),
                    kit.errors.len()
                );
            }
            kit.errors.is_empty()
        }),
    )
}

fn print_status(status: &KitStatus) {
    let mode = match status.mode {
        morphir_mck::kit::status::KitMode::Embedded => "embedded",
        morphir_mck::kit::status::KitMode::Local => "local",
    };
    println!("kit: {mode} ({})", status.label);
    println!(
        "revision: {}",
        status.revision.as_deref().unwrap_or("unknown")
    );
    println!("modified: {}", status.modified);
    println!(
        "corpus hash: {} ({})",
        status
            .corpus_hash
            .as_deref()
            .unwrap_or("none; the kit has errors"),
        status.algorithm
    );
    println!(
        "{} case(s) in {} file(s), {} error(s)",
        status.cases, status.files, status.errors
    );
}

pub fn run_mck_kit_status(args: MckKitStatusArgs) -> AppResult<miette::Report> {
    let status = match &args.kit {
        None => embedded_status().map_err(|error| format!("cannot read the embedded kit: {error}")),
        Some(dir) => load_directory(dir, args.repo_root.as_deref()).and_then(|kit| {
            local_status(&kit)
                .map_err(|error| format!("cannot hash kit {}: {error}", dir.display()))
        }),
    };
    finish(status.map(|status| {
        if args.json {
            println!("{}", to_tab_json(&status));
        } else {
            print_status(&status);
        }
        status.is_ok()
    }))
}
