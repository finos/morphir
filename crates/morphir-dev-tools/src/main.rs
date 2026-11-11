//! `morphir-dev`: the internal development tool of finos/morphir.
//!
//! This is not the Morphir CLI, and it is never released. The Morphir CLI
//! comes from finos/morphir-dotnet (pinned at `ecosystem/morphir-dotnet`). This
//! program keeps the repository's own maintenance commands working after the
//! Rust product CLI was deleted: today that is the `kb` tree that the `kb`
//! skill and `mise run kb` use. Compatibility checks run in
//! `morphir-mck`, not here. Add a command only when a repository gate needs it.

use std::process::ExitCode;

use clap::{Parser, Subcommand};

mod kb;

/// The result of one command: `Ok(None)` is success, `Ok(Some(code))` an exit
/// code the command chose after printing its own diagnostics.
pub(crate) type AppResult<E> = Result<Option<u8>, E>;

/// Internal development tool of finos/morphir (not the Morphir CLI)
#[derive(Parser)]
#[command(name = "morphir-dev", version, about, long_about = None)]
#[command(arg_required_else_help = true)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Clone, Subcommand)]
enum Command {
    /// Manage the knowledge base under kb/ — OKF bundles and concept documents
    Kb {
        #[command(subcommand)]
        action: KbAction,
    },
}

/// The `morphir-dev kb` subcommand tree — a drop-in port of the morphir-scala
/// `kb` CLI. The option structs live in `kb`.
#[derive(Clone, Subcommand)]
enum KbAction {
    /// List bundles, or one bundle's concepts
    List(kb::KbListArgs),
    /// Show one document: frontmatter, outbound links, heading outline
    Show(kb::KbShowArgs),
    /// Search concepts by metadata, body text, or the SQLite index
    Search(kb::KbSearchArgs),
    /// Run every check and exit non-zero when there are errors
    Check(kb::KbCheckArgs),
    /// Build the SQLite index over the knowledge base
    Index(kb::KbIndexArgs),
    /// Bring derived state — markdown indexes and the SQLite index — back in line
    Refresh {
        #[command(subcommand)]
        action: Option<KbRefreshAction>,
        #[command(flatten)]
        args: kb::KbRefreshArgs,
    },
    /// Run read-only SQL over the index
    Query(kb::KbQueryArgs),
    /// Scaffold a new bundle with its index.md and log.md
    NewBundle(kb::KbNewBundleArgs),
    /// Scaffold a concept and wire it into its index and log
    AddConcept(kb::KbAddConceptArgs),
    /// Mirror an upstream repository into a bundle and project edits back out
    Sync {
        #[command(subcommand)]
        action: KbSyncAction,
    },
    /// Manage intent — work recorded as prose with a lifecycle
    Intent {
        #[command(subcommand)]
        action: KbIntentAction,
    },
    /// Read decision records
    Decision {
        #[command(subcommand)]
        action: KbDecisionAction,
    },
}

#[derive(Clone, Subcommand)]
enum KbRefreshAction {
    /// Rewrite drifted index bullets only — same as `kb refresh --no-db`
    #[command(alias = "md")]
    Markdown(kb::KbRefreshMarkdownArgs),
    /// Rebuild the SQLite index only — same as `kb refresh --no-markdown`
    #[command(alias = "index")]
    Db(kb::KbRefreshDbArgs),
}

#[derive(Clone, Subcommand)]
enum KbSyncAction {
    /// What has moved, here and upstream
    Status(kb::KbSyncStatusArgs),
    /// Import upstream changes and rewrite the lockfile
    Pull(kb::KbSyncPullArgs),
    /// Project locally-edited files back into an upstream checkout
    Push(kb::KbSyncPushArgs),
    /// Diff upstream's copy against the upstream form of ours
    Diff(kb::KbSyncDiffArgs),
}

#[derive(Clone, Subcommand)]
enum KbIntentAction {
    /// Scaffold an intent bundle in a knowledge base that has none
    Init(kb::KbIntentInitArgs),
    /// Create a new intent record in Backlog
    New(kb::KbIntentNewArgs),
    /// List intent records, grouped by state
    #[command(alias = "ls")]
    List(kb::KbIntentListArgs),
    /// Show one intent record
    Show(kb::KbIntentShowArgs),
    /// Check every intent record's obligations
    Check(kb::KbIntentCheckArgs),
    /// Move an intent to Refinement
    Refine(kb::KbIntentMoveArgs),
    /// Move an intent to InProgress
    Start(kb::KbIntentMoveArgs),
    /// Move an intent to any state
    Move(kb::KbIntentMoveArgs),
    /// Mark an intent Released, linking the capability it produced
    Release(kb::KbIntentReleaseArgs),
    /// Mark an intent Cancelled, recording why
    Cancel(kb::KbIntentCancelArgs),
    /// Mark an intent Superseded by another
    Supersede(kb::KbIntentSupersedeArgs),
}

#[derive(Clone, Subcommand)]
enum KbDecisionAction {
    /// List decision records, grouped by state
    #[command(alias = "ls")]
    List(kb::KbDecisionListArgs),
    /// Show one decision record
    Show(kb::KbDecisionShowArgs),
}

fn dispatch(command: Command) -> AppResult<miette::Report> {
    let Command::Kb { action } = command;
    match action {
        KbAction::List(args) => kb::run_kb_list(args),
        KbAction::Show(args) => kb::run_kb_show(args),
        KbAction::Search(args) => kb::run_kb_search(args),
        KbAction::Check(args) => kb::run_kb_check(args),
        KbAction::Index(args) => kb::run_kb_index(args),
        KbAction::Refresh { action, args } => match action {
            None => kb::run_kb_refresh(args),
            Some(KbRefreshAction::Markdown(a)) => kb::run_kb_refresh_markdown(a),
            Some(KbRefreshAction::Db(a)) => kb::run_kb_refresh_db(a),
        },
        KbAction::Query(args) => kb::run_kb_query(args),
        KbAction::NewBundle(args) => kb::run_kb_new_bundle(args),
        KbAction::AddConcept(args) => kb::run_kb_add_concept(args),
        KbAction::Sync { action } => match action {
            KbSyncAction::Status(a) => kb::run_kb_sync_status(a),
            KbSyncAction::Pull(a) => kb::run_kb_sync_pull(a),
            KbSyncAction::Push(a) => kb::run_kb_sync_push(a),
            KbSyncAction::Diff(a) => kb::run_kb_sync_diff(a),
        },
        KbAction::Intent { action } => match action {
            KbIntentAction::Init(a) => kb::run_kb_intent_init(a),
            KbIntentAction::New(a) => kb::run_kb_intent_new(a),
            KbIntentAction::List(a) => kb::run_kb_intent_list(a),
            KbIntentAction::Show(a) => kb::run_kb_intent_show(a),
            KbIntentAction::Check(a) => kb::run_kb_intent_check(a),
            KbIntentAction::Refine(a) => kb::run_kb_intent_refine(a),
            KbIntentAction::Start(a) => kb::run_kb_intent_start(a),
            KbIntentAction::Move(a) => kb::run_kb_intent_move(a),
            KbIntentAction::Release(a) => kb::run_kb_intent_release(a),
            KbIntentAction::Cancel(a) => kb::run_kb_intent_cancel(a),
            KbIntentAction::Supersede(a) => kb::run_kb_intent_supersede(a),
        },
        KbAction::Decision { action } => match action {
            KbDecisionAction::List(a) => kb::run_kb_decision_list(a),
            KbDecisionAction::Show(a) => kb::run_kb_decision_show(a),
        },
    }
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match dispatch(cli.command) {
        Ok(None) => ExitCode::SUCCESS,
        Ok(Some(code)) => ExitCode::from(code),
        Err(report) => {
            eprintln!("error: {report:?}");
            ExitCode::FAILURE
        }
    }
}
