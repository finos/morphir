//! Thin host for freshly authenticated local Library consumption.

use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use clap::{Args, Subcommand, ValueEnum};
use miette::{IntoDiagnostic, WrapErr, miette};
use morphir_package::local_registry::mvp::{
    self, InitializeRequest, RefreshRequest, ResolveRequest, RestoreRequest,
};
use morphir_package::resolution::{PackagePath, ReleaseId, StableVersion};
use starbase::AppResult;

/// Experimental local Library operations, separate from executable repositories.
#[derive(Clone, Debug, Subcommand)]
pub enum PackageAction {
    /// Explicitly provision local package trust
    Trust {
        #[command(subcommand)]
        action: TrustAction,
    },
    /// Restore an exact locked Library graph using fresh signed metadata
    Restore(RestoreArgs),
    /// Resolve an exact published root and write a new fully verified package lock
    Resolve(ResolveArgs),
    /// Authenticate current registry metadata without resolving or restoring packages
    Refresh(RefreshArgs),
}

/// Trust state is initialized only by an explicit command.
#[derive(Clone, Debug, Subcommand)]
pub enum TrustAction {
    /// Initialize a new state directory from a policy-pinned bootstrap root
    Init(InitializeArgs),
}

#[derive(Clone, Debug, Args)]
pub struct InitializeArgs {
    /// Explicit trusted-host policy file
    #[arg(long, value_name = "FILE")]
    policy: PathBuf,
    /// Bootstrap root whose exact digest is pinned by the policy
    #[arg(long, value_name = "FILE")]
    root: PathBuf,
    /// New local trust-state directory; existing state is never reset
    #[arg(long, value_name = "DIR")]
    state: PathBuf,
    /// Output the initialization result as JSON
    #[arg(long)]
    json: bool,
}

/// Consent to the MVP's caller-controlled local filesystem assumptions.
#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum Assurance {
    Portable,
}

#[derive(Clone, Debug, Args)]
pub struct RestoreArgs {
    /// Explicit trusted-host policy file
    #[arg(long, value_name = "FILE")]
    policy: PathBuf,
    /// Full package lock; replay never rewrites it
    #[arg(long, value_name = "FILE")]
    lock: PathBuf,
    /// Caller-controlled local registry; the MVP supports one registry per graph
    #[arg(long, value_name = "DIR")]
    registry: PathBuf,
    /// Existing explicitly initialized trust-state directory
    #[arg(long, value_name = "DIR")]
    state: PathBuf,
    /// Destination for the complete verified Library graph
    #[arg(long, value_name = "DIR")]
    output: PathBuf,
    /// Explicitly accept caller-controlled local roots; hardened mode is unsupported
    #[arg(long, value_enum)]
    assurance: Assurance,
    /// Output the restore result as JSON
    #[arg(long)]
    json: bool,
}

#[derive(Clone, Debug, Args)]
pub struct ResolveArgs {
    /// Exact published root release, for example example.com/finance/loan-rules@1.0.0
    #[arg(long, value_name = "PACKAGE@VERSION", value_parser = parse_root_release)]
    root: ReleaseId,
    /// Explicit trusted-host policy file
    #[arg(long, value_name = "FILE")]
    policy: PathBuf,
    /// Caller-controlled local registry; one registry per graph
    #[arg(long, value_name = "DIR")]
    registry: PathBuf,
    /// Existing explicitly initialized trust-state directory
    #[arg(long, value_name = "DIR")]
    state: PathBuf,
    /// New full lock file; its parent directory must exist
    #[arg(long, value_name = "FILE")]
    output: PathBuf,
    /// Explicitly accept caller-controlled local roots; hardened mode is unsupported
    #[arg(long, value_enum)]
    assurance: Assurance,
    /// Output the resolution result as JSON
    #[arg(long)]
    json: bool,
}

#[derive(Clone, Debug, Args)]
pub struct RefreshArgs {
    /// Explicit trusted-host policy file
    #[arg(long, value_name = "FILE")]
    policy: PathBuf,
    /// Caller-controlled local registry whose current metadata will be authenticated
    #[arg(long, value_name = "DIR")]
    registry: PathBuf,
    /// Existing explicitly initialized trust-state directory
    #[arg(long, value_name = "DIR")]
    state: PathBuf,
    /// Explicitly accept caller-controlled local roots; hardened mode is unsupported
    #[arg(long, value_enum)]
    assurance: Assurance,
    /// Output exact accepted metadata digests as JSON
    #[arg(long)]
    json: bool,
}

fn parse_root_release(input: &str) -> Result<ReleaseId, String> {
    let (package, version) = input
        .split_once('@')
        .ok_or_else(|| "expected PACKAGE@VERSION with an exact stable version".to_owned())?;
    Ok(ReleaseId::new(
        PackagePath::parse(package).map_err(|error| error.to_string())?,
        StableVersion::parse(version).map_err(|error| error.to_string())?,
    ))
}

pub async fn run(action: &PackageAction) -> AppResult<miette::Report> {
    match action {
        PackageAction::Trust {
            action: TrustAction::Init(args),
        } => {
            let policy = read_bounded(&args.policy, 1024 * 1024)?;
            let root = read_bounded(&args.root, 1024 * 1024)?;
            let result = mvp::initialize(InitializeRequest {
                policy: &policy,
                root: &root,
                state: &args.state,
            })
            .map_err(|error| miette!("{error}"))?;
            emit(args.json, &result, || {
                format!("Initialized package trust in {}", args.state.display())
            })?;
        }
        PackageAction::Restore(args) => {
            let Assurance::Portable = args.assurance;
            let policy = read_bounded(&args.policy, 1024 * 1024)?;
            let lock = read_bounded(&args.lock, 16 * 1024 * 1024)?;
            let result = mvp::restore(RestoreRequest {
                policy: &policy,
                lock: &lock,
                registry: &args.registry,
                state: &args.state,
                output: &args.output,
            })
            .await
            .map_err(|error| miette!("{error}"))?;
            emit(args.json, &result, || {
                format!("Restored verified Libraries to {}", args.output.display())
            })?;
        }
        PackageAction::Resolve(args) => {
            let Assurance::Portable = args.assurance;
            let policy = read_bounded(&args.policy, 1024 * 1024)?;
            let result = mvp::resolve(ResolveRequest {
                policy: &policy,
                root: args.root.clone(),
                registry: &args.registry,
                state: &args.state,
                output: &args.output,
            })
            .await
            .map_err(|error| miette!("{error}"))?;
            emit(args.json, &result, || {
                format!("Wrote verified Library lock to {}", args.output.display())
            })?;
        }
        PackageAction::Refresh(args) => {
            let Assurance::Portable = args.assurance;
            let policy = read_bounded(&args.policy, 1024 * 1024)?;
            let result = mvp::refresh(RefreshRequest {
                policy: &policy,
                registry: &args.registry,
                state: &args.state,
            })
            .await
            .map_err(|error| miette!("{error}"))?;
            emit(args.json, &result, || {
                format!(
                    "Refreshed authenticated registry metadata from {}",
                    args.registry.display()
                )
            })?;
        }
    }
    Ok(None)
}

fn emit<T: serde::Serialize>(
    json: bool,
    result: &T,
    human: impl FnOnce() -> String,
) -> miette::Result<()> {
    if json {
        crate::output::write_output(crate::output::OutputFormat::Json, result).into_diagnostic()
    } else {
        writeln!(std::io::stdout().lock(), "{}", human()).into_diagnostic()
    }
}

fn read_bounded(path: &Path, limit: usize) -> miette::Result<Vec<u8>> {
    let file = std::fs::File::open(path)
        .into_diagnostic()
        .wrap_err_with(|| format!("Cannot read {}", path.display()))?;
    if !file.metadata().into_diagnostic()?.is_file() {
        return Err(miette!("Expected a regular file: {}", path.display()));
    }
    let mut bytes = Vec::new();
    file.take(limit as u64 + 1)
        .read_to_end(&mut bytes)
        .into_diagnostic()
        .wrap_err_with(|| format!("Cannot read {}", path.display()))?;
    if bytes.len() > limit {
        return Err(miette!("{} exceeds the {limit}-byte limit", path.display()));
    }
    Ok(bytes)
}
