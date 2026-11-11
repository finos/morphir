//! `morphir-mck`: the standalone command line of the shared Morphir
//! Compatibility Kit runner.
//!
//! This is a development tool of finos/morphir, not the Morphir CLI. The
//! Morphir CLI comes from finos/morphir-dotnet, and its `morphir mck ARGS`
//! starts this program with the same `ARGS`, so both spellings run one runner
//! (`spec/mck/cli-contract.md`, "Invocation"). The command tree is the one
//! the deleted Rust product CLI exposed as `morphir mck`; only the program
//! name changed. Exit status: 0 success, 1 a failed check or an operational
//! error, 2 a usage error.

use std::process::ExitCode;

use clap::{Parser, Subcommand};

mod mck;

/// The result of one command: `Ok(None)` is success, `Ok(Some(code))` an exit
/// code the command chose after printing its own diagnostics.
pub(crate) type AppResult<E> = Result<Option<u8>, E>;

/// Run the Morphir Compatibility Kit (development only; the Morphir CLI is
/// finos/morphir-dotnet, whose `morphir mck` delegates here)
#[derive(Parser)]
#[command(name = "morphir-mck", version, about, long_about = None)]
#[command(arg_required_else_help = true)]
struct Cli {
    #[command(subcommand)]
    action: MckAction,
}

/// The `morphir-mck` subcommand tree. The contract is `spec/mck/cli-contract.md`;
/// the option structs live in `mck`.
#[derive(Clone, Subcommand)]
enum MckAction {
    /// Execute MEP guests or independently recheck their saved observations
    Mep {
        #[command(subcommand)]
        action: MckMepAction,
    },
    /// Validate a kit directory without running an adapter
    Check(mck::MckCheckArgs),
    /// Check that every IR vocabulary variant and member has a kit case
    ///
    /// Pending cases count through title and prose mentions. This JSON-key
    /// heuristic inspects inline JSON only; member coverage requires a case
    /// for the member's own node, so nesting it in another entry-point document
    /// does not cover it. Zero gaps do not establish semantic conformance.
    Coverage(mck::MckCoverageArgs),
    /// Validate kit schemas, examples and IR fences offline
    Schema {
        #[command(subcommand)]
        action: MckSchemaAction,
    },
    /// Run the kit against an implementation's adapter and report the results
    Run(mck::MckRunArgs),
    /// Inspect package definitions or run versioned compatibility suites
    Package {
        #[command(subcommand)]
        action: MckPackageAction,
    },
    /// Run Workbench value codecs or check their independently recomputed evidence
    Workbench {
        #[command(subcommand)]
        action: MckWorkbenchAction,
    },
    /// Run the draft V3/V4 semantic node-address corpus
    NodeAddress {
        #[command(subcommand)]
        action: MckNodeAddressAction,
    },
    /// Check compatibility evidence or render a saved report as offline HTML
    Report {
        #[command(subcommand)]
        action: MckReportAction,
    },
    /// Inspect, vendor and update kit data
    Kit {
        #[command(subcommand)]
        action: MckKitAction,
    },
}

#[derive(Clone, Subcommand)]
enum MckWorkbenchAction {
    /// Run the explicit Workbench codec corpus against an explicit adapter
    Run(mck::workbench::RunArgs),
    /// Recompute qualification from every saved observation and the independent corpus
    Check(mck::workbench::CheckArgs),
}

#[derive(Clone, Subcommand)]
enum MckSchemaAction {
    /// Check schemas, examples, protocol pairing and accepted JSON fences
    Check(mck::MckSchemaCheckArgs),
}

#[derive(Clone, Subcommand)]
enum MckNodeAddressAction {
    Run(mck::node_address::RunArgs),
}

#[derive(Clone, Subcommand)]
enum MckMepAction {
    GuestRun(mck::mep::RunArgs),
    ReportCheck(mck::mep::CheckArgs),
}

#[derive(Clone, Subcommand)]
enum MckPackageAction {
    /// Inspect draft.3 candidate definitions and pending assets without running restore
    Inspect(mck::package::InspectArgs),
    /// Run an integrity or resolution corpus against an explicit adapter
    Run(mck::package::RunArgs),
    /// Run admitted local Library MVP cases through an explicit adapter
    MvpRun(mck::package::MvpRunArgs),
    /// Check or render a versioned local Library MVP report
    MvpReport {
        #[command(subcommand)]
        action: MckPackageReportAction,
    },
}

#[derive(Clone, Subcommand)]
enum MckPackageReportAction {
    /// Compare every report record with the independently admitted MVP inventory
    Check(mck::package::MvpReportCheckArgs),
    /// Render a standalone offline HTML view of a versioned MVP report
    Render(mck::package::MvpReportRenderArgs),
}

#[derive(Clone, Subcommand)]
enum MckKitAction {
    /// Identify a kit: source, revision, corpus hash and whether it is modified
    Status(mck::MckKitStatusArgs),
    /// Write a verified, pinned copy of the kit into a new directory
    Vendor(mck::MckKitVendorArgs),
    /// Replace a vendored snapshot, refusing if its files were edited
    Update(mck::MckKitUpdateArgs),
}

#[derive(Clone, Subcommand)]
enum MckReportAction {
    /// Verify report inventory and the binding's allowed-failing baseline
    Check(mck::report::CheckArgs),
    /// Render a consolidated JSON report as a standalone offline HTML file
    Render(mck::report::RenderArgs),
    /// Compare two reports' records, ignoring duration and timing
    Compare(mck::report::CompareArgs),
}

async fn dispatch(action: MckAction) -> AppResult<miette::Report> {
    match action {
        MckAction::Check(args) => mck::run_mck_check(args),
        MckAction::Coverage(args) => mck::run_mck_coverage(args),
        MckAction::Schema {
            action: MckSchemaAction::Check(args),
        } => mck::run_mck_schema_check(args),
        MckAction::Run(args) => mck::run_mck_run(args).await,
        MckAction::Workbench { action } => match action {
            MckWorkbenchAction::Run(args) => mck::workbench::run(args).await,
            MckWorkbenchAction::Check(args) => mck::workbench::check(args),
        },
        MckAction::NodeAddress {
            action: MckNodeAddressAction::Run(args),
        } => mck::node_address::run(args),
        MckAction::Mep { action } => match action {
            MckMepAction::GuestRun(args) => mck::mep::run(args),
            MckMepAction::ReportCheck(args) => mck::mep::check(args),
        },
        MckAction::Package { action } => match action {
            MckPackageAction::Inspect(args) => mck::package::inspect(args),
            MckPackageAction::Run(args) => mck::package::run(args).await,
            MckPackageAction::MvpRun(args) => mck::package::mvp_run(args).await,
            MckPackageAction::MvpReport { action } => match action {
                MckPackageReportAction::Check(args) => mck::package::mvp_report_check(args),
                MckPackageReportAction::Render(args) => mck::package::mvp_report_render(args),
            },
        },
        MckAction::Report { action } => match action {
            MckReportAction::Check(args) => mck::report::run_check(args),
            MckReportAction::Render(args) => mck::report::run_render(args),
            MckReportAction::Compare(args) => mck::report::run_compare(args),
        },
        MckAction::Kit { action } => match action {
            MckKitAction::Status(args) => mck::run_mck_kit_status(args),
            MckKitAction::Vendor(args) => mck::run_mck_kit_vendor(args).await,
            MckKitAction::Update(args) => mck::run_mck_kit_update(args).await,
        },
    }
}

// Several commands move blocking work off the runtime with
// `tokio::task::block_in_place`, which needs the multi-threaded runtime.
#[tokio::main(flavor = "multi_thread")]
async fn main() -> ExitCode {
    // clap prints usage errors to stderr and exits 2, help and version to
    // stdout with 0, as `spec/mck/cli-contract.md` requires.
    let cli = Cli::parse();
    match dispatch(cli.action).await {
        Ok(None) => ExitCode::SUCCESS,
        Ok(Some(code)) => ExitCode::from(code),
        Err(report) => {
            eprintln!("error: {report:?}");
            ExitCode::FAILURE
        }
    }
}
