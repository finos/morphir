use clap::{Args, Parser, Subcommand};
use starbase::{App, AppResult, AppSession};
use std::path::PathBuf;

pub mod commands;
pub mod error;
pub mod extensions;
mod help;
pub mod home;
mod log_lock;
mod logging;
pub mod output;
mod session;

pub use morphir::notebook;
use morphir::observability;

use commands::{
    GenerateOptions, MigrateCommandOptions, OutputLayout, compile::CompileOptions, run_cache_clean,
    run_cache_status, run_compile, run_config_get, run_config_path, run_config_show, run_desktop,
    run_diagnostics_path, run_dist_install, run_dist_list, run_dist_uninstall, run_dist_update,
    run_extension_install, run_extension_list, run_extension_repository_add,
    run_extension_repository_disable, run_extension_repository_enable,
    run_extension_repository_init, run_extension_repository_inspect, run_extension_repository_list,
    run_extension_repository_publish, run_extension_repository_remove,
    run_extension_repository_verify, run_extension_search, run_extension_uninstall,
    run_extension_update, run_generate, run_gleam_compile, run_gleam_generate, run_gleam_roundtrip,
    run_kb_add_concept, run_kb_check, run_kb_decision_list, run_kb_decision_show, run_kb_index,
    run_kb_intent_cancel, run_kb_intent_check, run_kb_intent_init, run_kb_intent_list,
    run_kb_intent_move, run_kb_intent_new, run_kb_intent_refine, run_kb_intent_release,
    run_kb_intent_show, run_kb_intent_start, run_kb_intent_supersede, run_kb_list,
    run_kb_new_bundle, run_kb_query, run_kb_refresh, run_kb_refresh_db, run_kb_refresh_markdown,
    run_kb_search, run_kb_show, run_kb_sync_diff, run_kb_sync_pull, run_kb_sync_push,
    run_kb_sync_status, run_mck_check, run_mck_kit_status, run_mck_kit_update, run_mck_kit_vendor,
    run_mck_run, run_migrate, run_tool_install, run_tool_list, run_tool_uninstall, run_tool_update,
    run_transform, run_validate, run_version,
};

/// Morphir CLI - Tools for functional domain modeling and business logic
#[derive(Parser)]
#[command(name = "morphir")]
#[command(about = "CLI for working with Morphir IR - functional domain modeling and business logic", long_about = None)]
#[command(version)]
#[command(disable_version_flag = true)]
struct Cli {
    /// Print help including experimental commands
    #[arg(long)]
    help_all: bool,

    /// Print version
    #[arg(short = 'V', long, action = clap::ArgAction::Version)]
    version: Option<bool>,

    /// Relocate the out root, which defaults to .morphir/out under the workspace root. MORPHIR_OUT_DIR does the same.
    #[arg(long, global = true, value_name = "PATH")]
    out_dir: Option<std::path::PathBuf>,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Clone, Subcommand)]
enum Commands {
    /// Evaluate a program through a registered native provider
    Eval(commands::eval::EvalArgs),
    /// Run notebook or Markdown integration scenarios through real CLI processes
    Itest(commands::itest::ItestArgs),
    // ===== Core Commands =====
    /// Compile source code to Morphir IR
    Compile {
        /// Source language (e.g., gleam, elm)
        #[arg(short, long)]
        language: Option<String>,
        /// Extension id that provides the language (for example `morphir-elm-native`); overrides `[frontend.<language>] extension`, and defaults to the language's default provider
        #[arg(long)]
        extension: Option<String>,
        /// Input source directory or file. A single .elm file is compiled by the selected Elm provider: an installed process extension by default, or a builtin such as morphir-elm-native via --extension.
        #[arg(short, long)]
        input: Option<String>,
        /// Install task outputs into this directory after the run. Canonical output stays under .morphir/out.
        #[arg(short, long)]
        output: Option<String>,
        /// Package name override
        #[arg(long)]
        package_name: Option<String>,
        /// Explicit config file path. An Elm command is a development override for the installed extension.
        #[arg(long)]
        config: Option<String>,
        /// Declared workspace-relative member path or exact project name
        #[arg(long)]
        project: Option<String>,
        /// IR version 3 or 4. Overrides ir.format_version in the selected project.
        #[arg(long, value_parser = commands::compile::parse_ir_version)]
        ir_version: Option<morphir_common::ir_transport::IrVersion>,
        /// Output as JSON
        #[arg(long)]
        json: bool,
        /// Output as JSON Lines (streaming)
        #[arg(long)]
        json_lines: bool,
        /// Ignore the incremental compile cache for this run
        #[arg(long)]
        no_cache: bool,
        /// How Elm doc comments become IR doc text. Overrides [frontend.elm] doc_comments and MORPHIR_FRONTEND__ELM__DOC_COMMENTS.
        #[arg(long, value_name = "MODE", value_parser = ["morphir-elm", "trimmed"])]
        elm_doc_comments: Option<String>,
        /// The order Elm modules, types and constructors are written in. Overrides [frontend.elm] ordering and MORPHIR_FRONTEND__ELM__ORDERING.
        #[arg(long, value_name = "MODE", value_parser = ["source", "morphir-elm"])]
        elm_ordering: Option<String>,
    },
    /// Generate code from Morphir IR
    Generate {
        /// Target language or format
        #[arg(short, long)]
        target: Option<String>,
        /// Path to the Morphir IR file or directory
        #[arg(short, long)]
        input: Option<String>,
        /// Install task outputs into this directory after the run. Canonical output stays under .morphir/out.
        #[arg(short, long)]
        output: Option<String>,
        /// Explicit config file path
        #[arg(long)]
        config: Option<String>,
        /// Declared workspace-relative member path or exact project name
        #[arg(long)]
        project: Option<String>,
        /// Override a backend option as KEY=VALUE. May be repeated.
        #[arg(
            long = "option",
            value_name = "KEY=VALUE",
            action = clap::ArgAction::Append
        )]
        option: Vec<String>,
        /// Output as JSON
        #[arg(long)]
        json: bool,
        /// Output as JSON Lines (streaming)
        #[arg(long)]
        json_lines: bool,
    },
    /// [Experimental] Validate Morphir IR models
    #[command(hide = true)]
    Validate {
        /// Path to the Morphir IR file or directory
        #[arg(short, long)]
        input: Option<String>,
    },
    /// [Experimental] Transform Morphir IR
    #[command(hide = true)]
    Transform {
        /// Path to the Morphir IR file or directory
        #[arg(short, long)]
        input: Option<String>,
        /// Output path
        #[arg(short, long)]
        output: Option<String>,
    },
    /// Migrate IR between versions
    #[command(long_about = "Migrate IR between versions

Converts concrete Morphir IR V3 and V4 between native JSON and YAML storage, single files, and V4 document trees. V3-to-V4 output defaults to YAML.

**Examples:**

```bash
# Migrate V3 JSON to the default V4 YAML profile
morphir migrate ./morphir-ir.json -o ./morphir-ir-v4.yaml

# Convert V4 YAML to JSON without changing the IR version
morphir migrate ./morphir-ir-v4.yaml -o ./morphir-ir-v4.json

# Migrate from URL
morphir migrate https://lcr-interactive.finos.org/server/morphir-ir.json -o ./lcr-v4.json

# Stream YAML IR to stdout (no -o)
morphir migrate ./morphir-ir.json

# Write the V4 document-tree layout
morphir migrate ./morphir-ir.json -o ./morphir-ir-v4/ --output-layout vfs
```

See the [IR Migration Guide](https://morphir.finos.org/docs/user-guides/cli-tools/ir-migrate) for detailed real-world examples including the US Federal Reserve FR 2052a regulation model.")]
    Migrate(MigrateArgs),

    /// Open the Morphir development workbench in a browser
    Ui(commands::ui::UiArgs),

    /// Launch the installed Morphir Desktop application
    Desktop(commands::DesktopArgs),

    /// Open a scratch Morphir Playground in a browser, with no workspace required
    Playground(commands::playground::PlaygroundArgs),

    // ===== Management Commands =====
    /// Inspect the effective Morphir configuration
    Config {
        #[command(subcommand)]
        action: ConfigAction,
    },
    /// Locate Morphir logs and collect troubleshooting information
    Diagnostics {
        #[command(subcommand)]
        action: DiagnosticsAction,
    },
    /// Inspect and clean disposable Morphir caches
    Cache {
        #[command(subcommand)]
        action: CacheAction,
    },
    /// Manage CLI-installed Morphir tools
    Tool {
        #[command(subcommand)]
        action: ToolAction,
    },
    /// Manage Morphir distributions
    Dist {
        #[command(subcommand)]
        action: DistAction,
    },
    /// Manage Morphir extensions
    Extension {
        #[command(subcommand)]
        action: ExtensionAction,
    },
    /// Manage Morphir IR
    Ir {
        #[command(subcommand)]
        action: IrAction,
    },
    /// Manage the knowledge base under kb/ — OKF bundles and concept documents
    Kb {
        #[command(subcommand)]
        action: KbAction,
    },
    /// Morphir Compatibility Kit: validate, vendor and run compatibility kits
    Mck {
        #[command(subcommand)]
        action: MckAction,
    },
    /// Gleam language binding commands
    Gleam {
        #[command(subcommand)]
        action: GleamAction,
        /// Output as JSON
        #[arg(long)]
        json: bool,
        /// Output as JSON Lines (streaming)
        #[arg(long)]
        json_lines: bool,
    },
    /// Generate JSON Schema for Morphir IR
    Schema {
        /// Output file path (optional)
        #[arg(short, long)]
        output: Option<std::path::PathBuf>,
    },
    /// Print version information
    Version {
        /// Output version info as JSON
        #[arg(long)]
        json: bool,
    },

    // ===== Internal/Hidden Commands =====
    /// Output usage spec for documentation generation
    #[command(hide = true)]
    Usage,
}

#[derive(Clone, Subcommand)]
enum ConfigAction {
    /// Get one value from the effective configuration
    Get {
        /// Dotted configuration key, such as project.name
        key: String,
        /// Explicit project config file path
        #[arg(long)]
        config: Option<String>,
        /// Output as JSON
        #[arg(long)]
        json: bool,
        /// Ignore machine-level and user-level configuration sources
        #[arg(long, hide = true)]
        isolated: bool,
    },
    /// Show the effective configuration after merging every source
    Show {
        /// Explicit project config file path
        #[arg(long)]
        config: Option<String>,
        /// Output as JSON
        #[arg(long)]
        json: bool,
        /// Ignore machine-level and user-level configuration sources
        #[arg(long, hide = true)]
        isolated: bool,
    },
    /// Show which configuration sources were considered
    Path {
        /// Explicit project config file path
        #[arg(long)]
        config: Option<String>,
        /// Output as JSON
        #[arg(long)]
        json: bool,
        /// Ignore machine-level and user-level configuration sources
        #[arg(long, hide = true)]
        isolated: bool,
    },
}

#[derive(Clone, Subcommand)]
enum DiagnosticsAction {
    /// Show the local Morphir log locations
    Path {
        /// Output paths as JSON
        #[arg(long)]
        json: bool,
    },
    /// Create a local sanitized diagnostic archive
    Collect {
        /// Operation ID reported by Morphir
        #[arg(long)]
        operation: String,
        /// New ZIP archive to create
        #[arg(long)]
        output: std::path::PathBuf,
    },
    /// Show events correlated with one operation
    Show {
        /// Operation ID reported by Morphir
        #[arg(long)]
        operation: String,
        /// Output events as JSON
        #[arg(long)]
        json: bool,
    },
}

#[derive(Clone, Subcommand)]
enum CacheAction {
    /// Report owned and unclassified cache usage
    Status {
        /// Output status as JSON
        #[arg(long)]
        json: bool,
    },
    /// Remove known disposable cache entries
    Clean {
        /// Report the cleanup plan without changing files
        #[arg(long)]
        dry_run: bool,
        /// Remove every known disposable entry instead of applying policy
        #[arg(long)]
        all: bool,
        /// Limit cleanup to one registered cache component
        #[arg(long)]
        component: Option<String>,
        /// Output the plan and execution report as JSON
        #[arg(long)]
        json: bool,
    },
}

#[derive(Clone, Subcommand)]
enum ToolAction {
    /// Install a local developer Morphir tool
    Install {
        /// Name of the tool to install
        name: String,
        /// Exact semantic version recorded for the local package
        #[arg(short, long)]
        version: Option<String>,
        /// Local unsigned package built for the current machine
        #[arg(long)]
        source: Option<PathBuf>,
        /// Acquisition channel; local sources require developer
        #[arg(long)]
        channel: Option<String>,
    },
    /// List installed Morphir tools
    List {
        /// Output installed tool state as JSON
        #[arg(long)]
        json: bool,
    },
    /// Install a replacement local developer package
    Update {
        /// Name of the tool to update
        name: String,
        /// Exact semantic version recorded for the replacement package
        #[arg(short, long)]
        version: Option<String>,
        /// Replacement local unsigned package
        #[arg(long)]
        source: Option<PathBuf>,
        /// Acquisition channel; local sources require developer
        #[arg(long)]
        channel: Option<String>,
    },
    /// Repair the active exact release from its local package source
    Repair {
        /// Name of the tool to repair
        name: String,
        /// Original local unsigned package bytes
        #[arg(long)]
        source: PathBuf,
    },
    /// Activate the most recently retained release
    Rollback {
        /// Name of the tool to roll back
        name: String,
    },
    /// Uninstall a Morphir tool
    Uninstall {
        /// Name of the tool to uninstall
        name: String,
    },
}

#[derive(Clone, Subcommand)]
enum DistAction {
    /// Install a Morphir distribution
    Install {
        /// Name of the distribution to install
        name: String,
        /// Version to install (defaults to latest)
        #[arg(short, long)]
        version: Option<String>,
    },
    /// List installed Morphir distributions
    List,
    /// Update an installed Morphir distribution
    Update {
        /// Name of the distribution to update
        name: String,
        /// Version to update to (defaults to latest)
        #[arg(short, long)]
        version: Option<String>,
    },
    /// Uninstall a Morphir distribution
    Uninstall {
        /// Name of the distribution to uninstall
        name: String,
    },
}

#[derive(Clone, Subcommand)]
enum ExtensionAction {
    /// Install a Morphir extension
    Install {
        /// Name of the extension to install
        name: String,
        /// Named extension repository configured in Morphir Home
        #[arg(long)]
        repository: String,
        /// Moving release channel (defaults to stable)
        #[arg(long, conflicts_with = "version")]
        channel: Option<String>,
        /// Exact semantic version
        #[arg(long, conflicts_with = "channel")]
        version: Option<String>,
    },
    /// List installed Morphir extensions
    List,
    /// Search enabled extension repositories
    Search {
        /// Extension identity or display-name text
        query: String,
    },
    /// Manage named extension repositories
    Repository {
        #[command(subcommand)]
        action: ExtensionRepositoryAction,
    },
    /// Update an installed Morphir extension
    Update {
        /// Name of the extension to update
        name: String,
        /// Named extension repository configured in Morphir Home
        #[arg(long)]
        repository: String,
        /// Moving release channel (defaults to stable)
        #[arg(long, conflicts_with = "version")]
        channel: Option<String>,
        /// Exact semantic version
        #[arg(long, conflicts_with = "channel")]
        version: Option<String>,
    },
    /// Uninstall a Morphir extension
    Uninstall {
        /// Name of the extension to uninstall
        name: String,
    },
}

#[derive(Clone, Subcommand)]
enum ExtensionRepositoryAction {
    /// Initialize a local repository directory for publication
    Init {
        /// Repository directory to create or open
        directory: std::path::PathBuf,
    },
    /// Add an enabled local-directory repository
    Add {
        /// Stable repository name
        name: String,
        /// Existing local repository directory
        #[arg(long)]
        directory: std::path::PathBuf,
    },
    /// List configured repositories without contacting their endpoints
    List,
    /// Inspect one repository without contacting its endpoint
    Inspect {
        /// Repository name
        name: String,
    },
    /// Enable a configured repository
    Enable {
        /// Repository name
        name: String,
    },
    /// Disable a configured repository
    Disable {
        /// Repository name
        name: String,
    },
    /// Remove configuration without deleting endpoint content
    Remove {
        /// Repository name
        name: String,
    },
    /// Publish a verified release bundle to a configured repository
    Publish {
        /// Repository name
        name: String,
        /// Release bundle directory
        #[arg(long)]
        bundle: std::path::PathBuf,
    },
    /// Validate repository metadata without installing anything
    Verify {
        /// Repository name
        name: String,
    },
}

#[derive(Clone, Subcommand)]
enum GleamAction {
    /// Compile Gleam source to Morphir IR
    Compile {
        /// Input source directory or file
        #[arg(short, long)]
        input: Option<String>,
        /// Install task outputs into this directory after the run. Canonical output stays under .morphir/out.
        #[arg(short, long)]
        output: Option<String>,
        /// Package name override
        #[arg(long)]
        package_name: Option<String>,
        /// Explicit config file path
        #[arg(long)]
        config: Option<String>,
        /// Declared workspace-relative member path or exact project name
        #[arg(long)]
        project: Option<String>,
    },
    /// Generate Gleam code from Morphir IR
    Generate {
        /// Path to the Morphir IR file or directory
        #[arg(short, long)]
        input: Option<String>,
        /// Install task outputs into this directory after the run. Canonical output stays under .morphir/out.
        #[arg(short, long)]
        output: Option<String>,
        /// Explicit config file path
        #[arg(long)]
        config: Option<String>,
        /// Declared workspace-relative member path or exact project name
        #[arg(long)]
        project: Option<String>,
    },
    /// Roundtrip: compile then generate (for testing)
    Roundtrip {
        /// Input source directory or file
        #[arg(short, long)]
        input: Option<String>,
        /// Install task outputs into this directory after the run. Canonical output stays under .morphir/out.
        #[arg(short, long)]
        output: Option<String>,
        /// Package name override
        #[arg(long)]
        package_name: Option<String>,
        /// Explicit config file path
        #[arg(long)]
        config: Option<String>,
        /// Declared workspace-relative member path or exact project name
        #[arg(long)]
        project: Option<String>,
    },
}

#[derive(Clone, Subcommand)]
enum IrAction {
    /// Migrate IR between versions
    #[command(long_about = "Migrate IR between versions

Converts concrete Morphir IR V3 and V4 between native JSON and YAML storage, single files, and V4 document trees. V3-to-V4 output defaults to YAML.

**Examples:**

```bash
# Migrate V3 JSON to the default V4 YAML profile
morphir ir migrate ./morphir-ir.json -o ./morphir-ir-v4.yaml

# Convert V4 YAML to JSON without changing the IR version
morphir ir migrate ./morphir-ir-v4.yaml -o ./morphir-ir-v4.json

# Migrate from URL
morphir ir migrate https://lcr-interactive.finos.org/server/morphir-ir.json -o ./lcr-v4.json

# Stream YAML IR to stdout (no -o)
morphir ir migrate ./morphir-ir.json

# Write the V4 document-tree layout
morphir ir migrate ./morphir-ir.json -o ./morphir-ir-v4/ --output-layout vfs
```

See the [IR Migration Guide](https://morphir.finos.org/docs/user-guides/cli-tools/ir-migrate) for detailed real-world examples including the US Federal Reserve FR 2052a regulation model.")]
    Migrate(MigrateArgs),
}

#[derive(Args, Clone)]
struct MigrateArgs {
    /// Input file, directory, or remote source (e.g., github:owner/repo, URL)
    input: String,
    /// Output file or directory (if omitted, writes the IR artifact to stdout)
    #[arg(short, long)]
    output: Option<std::path::PathBuf>,
    /// Target version: latest, v4/4, or classic/v3/3 (default: latest)
    #[arg(long, default_value = "latest")]
    target_version: String,
    /// Force refresh cached remote sources
    #[arg(long)]
    force_refresh: bool,
    /// Skip cache entirely for remote sources
    #[arg(long)]
    no_cache: bool,
    /// Emit JSON IR to stdout, or a JSON result envelope when --output is present
    #[arg(long)]
    json: bool,
    /// Use expanded (non-compact) format for V4 output
    #[arg(long)]
    expanded: bool,
    /// Permit recoverable incomplete V4 nodes when a source construct cannot be preserved
    #[arg(long)]
    allow_partial: bool,
    /// Output storage layout (inferred from the output path when omitted)
    #[arg(long, value_enum)]
    output_layout: Option<OutputLayout>,
    /// Input serialization profile (json or yaml; inferred when omitted)
    #[arg(long)]
    input_format: Option<morphir_common::ir_transport::FormatId>,
    /// Output serialization profile (json or yaml; extension then YAML default when omitted)
    #[arg(long)]
    output_format: Option<morphir_common::ir_transport::FormatId>,
}

impl MigrateArgs {
    fn run(&self) -> AppResult<miette::Report> {
        run_migrate(
            self.input.clone(),
            MigrateCommandOptions {
                output: self.output.clone(),
                target_version: self.target_version.clone(),
                force_refresh: self.force_refresh,
                no_cache: self.no_cache,
                json: self.json,
                expanded: self.expanded,
                allow_partial: self.allow_partial,
                output_layout: self.output_layout,
                input_format: self.input_format.clone(),
                output_format: self.output_format.clone(),
            },
        )
    }
}

/// The `morphir mck` subcommand tree. The contract is `spec/mck/cli-contract.md`;
/// the option structs live in `commands::mck`.
#[derive(Clone, Subcommand)]
enum MckAction {
    /// Validate a kit directory without running an adapter
    Check(commands::mck::MckCheckArgs),
    /// Run the kit against an implementation's adapter and report the results
    Run(commands::mck::MckRunArgs),
    /// Inspect, vendor and update kit data
    Kit {
        #[command(subcommand)]
        action: MckKitAction,
    },
}

#[derive(Clone, Subcommand)]
enum MckKitAction {
    /// Identify a kit: source, revision, corpus hash and whether it is modified
    Status(commands::mck::MckKitStatusArgs),
    /// Write a verified, pinned copy of the kit into a new directory
    Vendor(commands::mck::MckKitVendorArgs),
    /// Replace a vendored snapshot, refusing if its files were edited
    Update(commands::mck::MckKitUpdateArgs),
}

/// The `morphir kb` subcommand tree — a drop-in port of the morphir-scala
/// `kb` CLI. The option structs live in `commands::kb`.
#[derive(Clone, Subcommand)]
enum KbAction {
    /// List bundles, or one bundle's concepts
    List(commands::kb::KbListArgs),
    /// Show one document: frontmatter, outbound links, heading outline
    Show(commands::kb::KbShowArgs),
    /// Search concepts by metadata, body text, or the SQLite index
    Search(commands::kb::KbSearchArgs),
    /// Run every check and exit non-zero when there are errors
    Check(commands::kb::KbCheckArgs),
    /// Build the SQLite index over the knowledge base
    Index(commands::kb::KbIndexArgs),
    /// Bring derived state — markdown indexes and the SQLite index — back in line
    Refresh {
        #[command(subcommand)]
        action: Option<KbRefreshAction>,
        #[command(flatten)]
        args: commands::kb::KbRefreshArgs,
    },
    /// Run read-only SQL over the index
    Query(commands::kb::KbQueryArgs),
    /// Scaffold a new bundle with its index.md and log.md
    NewBundle(commands::kb::KbNewBundleArgs),
    /// Scaffold a concept and wire it into its index and log
    AddConcept(commands::kb::KbAddConceptArgs),
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
    Markdown(commands::kb::KbRefreshMarkdownArgs),
    /// Rebuild the SQLite index only — same as `kb refresh --no-markdown`
    #[command(alias = "index")]
    Db(commands::kb::KbRefreshDbArgs),
}

#[derive(Clone, Subcommand)]
enum KbSyncAction {
    /// What has moved, here and upstream
    Status(commands::kb::KbSyncStatusArgs),
    /// Import upstream changes and rewrite the lockfile
    Pull(commands::kb::KbSyncPullArgs),
    /// Project locally-edited files back into an upstream checkout
    Push(commands::kb::KbSyncPushArgs),
    /// Diff upstream's copy against the upstream form of ours
    Diff(commands::kb::KbSyncDiffArgs),
}

#[derive(Clone, Subcommand)]
enum KbIntentAction {
    /// Scaffold an intent bundle in a knowledge base that has none
    Init(commands::kb::KbIntentInitArgs),
    /// Create a new intent record in Backlog
    New(commands::kb::KbIntentNewArgs),
    /// List intent records, grouped by state
    #[command(alias = "ls")]
    List(commands::kb::KbIntentListArgs),
    /// Show one intent record
    Show(commands::kb::KbIntentShowArgs),
    /// Check every intent record's obligations
    Check(commands::kb::KbIntentCheckArgs),
    /// Move an intent to Refinement
    Refine(commands::kb::KbIntentMoveArgs),
    /// Move an intent to InProgress
    Start(commands::kb::KbIntentMoveArgs),
    /// Move an intent to any state
    Move(commands::kb::KbIntentMoveArgs),
    /// Mark an intent Released, linking the capability it produced
    Release(commands::kb::KbIntentReleaseArgs),
    /// Mark an intent Cancelled, recording why
    Cancel(commands::kb::KbIntentCancelArgs),
    /// Mark an intent Superseded by another
    Supersede(commands::kb::KbIntentSupersedeArgs),
}

#[derive(Clone, Subcommand)]
enum KbDecisionAction {
    /// List decision records, grouped by state
    #[command(alias = "ls")]
    List(commands::kb::KbDecisionListArgs),
    /// Show one decision record
    Show(commands::kb::KbDecisionShowArgs),
}

// `Ready` and its `SessionReady` alias live in `session.rs`, which both this
// binary crate root and the library crate root declare, because
// `commands::compile` needs to name the type under both.
use session::Ready;
pub(crate) use session::SessionReady;

/// The state a phase produced. Phase *progress* is starbase's, in `AppPhase`
/// and `AppRunOutcome.last_phase`; this carries only the data.
#[derive(Clone)]
enum SessionState {
    /// Before `startup`: the session holds only its command and out overrides.
    Bootstrapped,
    /// After `startup`. `MorphirSession::ready` reads this variant.
    Ready(std::sync::Arc<Ready>),
}

/// Application session for Morphir CLI
#[derive(Clone)]
struct MorphirSession {
    command: Commands,
    operation_id: observability::OperationId,
    out: commands::OutOverrides,
    state: SessionState,
}

impl MorphirSession {
    /// What `startup` produced.
    ///
    /// An error rather than a panic so a wiring mistake reports like any other
    /// CLI failure. It names the phase, because the only way to see it is to
    /// call a command outside the lifecycle.
    fn ready(&self) -> Result<&Ready, miette::Report> {
        match &self.state {
            SessionState::Ready(ready) => Ok(ready),
            SessionState::Bootstrapped => Err(miette::miette!(
                "configuration was requested before the startup phase produced it"
            )),
        }
    }
}

#[async_trait::async_trait]
impl AppSession for MorphirSession {
    type Error = miette::Report;

    async fn startup(&mut self) -> AppResult<miette::Report> {
        // Only a whole-project compile has its configuration resolved here. The
        // single-file path applies a different rule (configuration optional,
        // discovery only under `--project`), and unifying them would change
        // behaviour, so it still resolves its own. Every other command must
        // reach `Ready` without touching the filesystem at all, so
        // `current_dir()` is called only inside this branch, not up front.
        let compile = match &self.command {
            Commands::Compile {
                config,
                project,
                input,
                language,
                ..
            } if !commands::compile::is_single_file_request(
                input.as_deref(),
                language.as_deref(),
            ) =>
            {
                Some((config.clone(), project.clone()))
            }
            // `morphir gleam compile` and the compile half of `morphir gleam
            // roundtrip` reach `run_provider_compile` too (Gleam is never the
            // single-file language), through `run_gleam_compile`, so they
            // need the same resolved configuration.
            Commands::Gleam {
                action:
                    GleamAction::Compile {
                        config, project, ..
                    }
                    | GleamAction::Roundtrip {
                        config, project, ..
                    },
                ..
            } => Some((config.clone(), project.clone())),
            _ => None,
        };

        let ready = match compile {
            None => Ready {
                start_dir: None,
                config: None,
            },
            Some((config_flag, project_flag)) => {
                let start_dir = std::env::current_dir()
                    .map_err(|error| crate::error::CliError::FileSystem { error })?;
                let config_file = match config_flag.as_deref() {
                    Some(path) => {
                        commands::compile::absolute_from(&start_dir, std::path::Path::new(path))
                    }
                    None => morphir_devkit::discover_config(&start_dir)
                        .map_err(|error| crate::error::CliError::Config { error })?
                        .ok_or_else(|| crate::error::CliError::Config {
                            error: anyhow::anyhow!(
                                "No morphir.toml, morphir.yaml, or morphir.json found"
                            ),
                        })?,
                };
                let context = morphir_devkit::load_config_context_with(
                    &config_file,
                    &morphir_devkit::ConfigLoadOptions {
                        project: project_flag
                            .map(morphir_devkit::config::ProjectSelection::Explicit)
                            .unwrap_or_default(),
                        ..Default::default()
                    },
                )
                .map_err(|error| crate::error::CliError::Config { error })?;
                Ready {
                    start_dir: Some(start_dir),
                    config: Some(context),
                }
            }
        };

        self.state = SessionState::Ready(std::sync::Arc::new(ready));

        Ok(None)
    }

    async fn execute(&mut self) -> AppResult<miette::Report> {
        match &self.command {
            Commands::Eval(args) => commands::eval::run_eval(args.clone()).map(|()| None),
            Commands::Itest(args) => commands::itest::run_itest(args.clone()),
            Commands::Validate { input } => run_validate(input.clone()),
            Commands::Compile {
                language,
                extension,
                input,
                output,
                package_name,
                config,
                project,
                ir_version,
                json,
                json_lines,
                no_cache,
                elm_doc_comments,
                elm_ordering,
            } => {
                let ready = self.ready()?;
                run_compile(
                    CompileOptions {
                        language: language.clone(),
                        extension: extension.clone(),
                        input: input.clone(),
                        output: output.clone(),
                        package_name: package_name.clone(),
                        config_path: config.clone(),
                        project: project.clone(),
                        ir_version: *ir_version,
                        json: *json,
                        json_lines: *json_lines,
                        no_cache: *no_cache,
                        elm_modes: commands::compile::ElmModeFlags {
                            doc_comments: elm_doc_comments.clone(),
                            ordering: elm_ordering.clone(),
                        },
                        out: self.out.clone(),
                    },
                    ready,
                )
                .await
            }
            Commands::Generate {
                target,
                input,
                output,
                config,
                project,
                option,
                json,
                json_lines,
            } => {
                run_generate(GenerateOptions {
                    target: target.clone(),
                    input: input.clone(),
                    output: output.clone(),
                    config_path: config.clone(),
                    project: project.clone(),
                    backend_options: option.clone(),
                    json: *json,
                    json_lines: *json_lines,
                    out: self.out.clone(),
                })
                .await
            }
            Commands::Transform { input, output } => run_transform(input.clone(), output.clone()),
            Commands::Migrate(args) => args.run(),
            Commands::Ui(args) => commands::ui::run_ui(args.clone(), self.out.clone()).await,
            Commands::Desktop(args) => run_desktop(&self.operation_id, args.clone()),
            Commands::Playground(args) => commands::playground::run_playground(args.clone()).await,
            Commands::Config { action } => match action {
                ConfigAction::Get {
                    key,
                    config,
                    json,
                    isolated,
                } => run_config_get(key.clone(), config.clone(), *json, *isolated),
                ConfigAction::Show {
                    config,
                    json,
                    isolated,
                } => run_config_show(config.clone(), *json, *isolated),
                ConfigAction::Path {
                    config,
                    json,
                    isolated,
                } => run_config_path(config.clone(), *json, *isolated),
            },
            Commands::Diagnostics { action } => match action {
                DiagnosticsAction::Path { json } => run_diagnostics_path(*json),
                DiagnosticsAction::Show { operation, json } => {
                    commands::run_diagnostics_show(operation, *json)
                }
                DiagnosticsAction::Collect { operation, output } => {
                    commands::run_diagnostics_collect(operation, output)
                }
            },
            Commands::Cache { action } => match action {
                CacheAction::Status { json } => run_cache_status(*json),
                CacheAction::Clean {
                    dry_run,
                    all,
                    component,
                    json,
                } => run_cache_clean(*dry_run, *all, component.clone(), *json),
            },
            Commands::Tool { action } => match action {
                ToolAction::Install {
                    name,
                    version,
                    source,
                    channel,
                } => run_tool_install(
                    name.clone(),
                    version.clone(),
                    source.clone(),
                    channel.clone(),
                ),
                ToolAction::List { json } => run_tool_list(*json),
                ToolAction::Update {
                    name,
                    version,
                    source,
                    channel,
                } => run_tool_update(
                    name.clone(),
                    version.clone(),
                    source.clone(),
                    channel.clone(),
                ),
                ToolAction::Repair { name, source } => {
                    commands::tool::run_tool_repair(name.clone(), source.clone())
                }
                ToolAction::Rollback { name } => commands::tool::run_tool_rollback(name.clone()),
                ToolAction::Uninstall { name } => run_tool_uninstall(name.clone()),
            },
            Commands::Dist { action } => match action {
                DistAction::Install { name, version } => {
                    run_dist_install(name.clone(), version.clone())
                }
                DistAction::List => run_dist_list(),
                DistAction::Update { name, version } => {
                    run_dist_update(name.clone(), version.clone())
                }
                DistAction::Uninstall { name } => run_dist_uninstall(name.clone()),
            },
            Commands::Extension { action } => match action {
                ExtensionAction::Install {
                    name,
                    repository,
                    channel,
                    version,
                } => run_extension_install(
                    &self.operation_id,
                    name.clone(),
                    repository.clone(),
                    channel.clone(),
                    version.clone(),
                ),
                ExtensionAction::List => run_extension_list(),
                ExtensionAction::Search { query } => {
                    run_extension_search(&self.operation_id, query.clone())
                }
                ExtensionAction::Repository { action } => match action {
                    ExtensionRepositoryAction::Init { directory } => {
                        run_extension_repository_init(&self.operation_id, directory.clone())
                    }
                    ExtensionRepositoryAction::Add { name, directory } => {
                        run_extension_repository_add(
                            &self.operation_id,
                            name.clone(),
                            directory.clone(),
                        )
                    }
                    ExtensionRepositoryAction::List => {
                        run_extension_repository_list(&self.operation_id)
                    }
                    ExtensionRepositoryAction::Inspect { name } => {
                        run_extension_repository_inspect(&self.operation_id, name.clone())
                    }
                    ExtensionRepositoryAction::Enable { name } => {
                        run_extension_repository_enable(&self.operation_id, name.clone())
                    }
                    ExtensionRepositoryAction::Disable { name } => {
                        run_extension_repository_disable(&self.operation_id, name.clone())
                    }
                    ExtensionRepositoryAction::Remove { name } => {
                        run_extension_repository_remove(&self.operation_id, name.clone())
                    }
                    ExtensionRepositoryAction::Publish { name, bundle } => {
                        run_extension_repository_publish(
                            &self.operation_id,
                            name.clone(),
                            bundle.clone(),
                        )
                    }
                    ExtensionRepositoryAction::Verify { name } => {
                        run_extension_repository_verify(&self.operation_id, name.clone())
                    }
                },
                ExtensionAction::Update {
                    name,
                    repository,
                    channel,
                    version,
                } => run_extension_update(
                    &self.operation_id,
                    name.clone(),
                    repository.clone(),
                    channel.clone(),
                    version.clone(),
                ),
                ExtensionAction::Uninstall { name } => run_extension_uninstall(name.clone()),
            },
            Commands::Ir { action } => match action {
                IrAction::Migrate(args) => args.run(),
            },
            Commands::Mck { action } => match action {
                MckAction::Check(args) => run_mck_check(args.clone()),
                MckAction::Run(args) => run_mck_run(args.clone()).await,
                MckAction::Kit { action } => match action {
                    MckKitAction::Status(args) => run_mck_kit_status(args.clone()),
                    MckKitAction::Vendor(args) => run_mck_kit_vendor(args.clone()).await,
                    MckKitAction::Update(args) => run_mck_kit_update(args.clone()).await,
                },
            },
            Commands::Kb { action } => match action {
                KbAction::List(args) => run_kb_list(args.clone()),
                KbAction::Show(args) => run_kb_show(args.clone()),
                KbAction::Search(args) => run_kb_search(args.clone()),
                KbAction::Check(args) => run_kb_check(args.clone()),
                KbAction::Index(args) => run_kb_index(args.clone()),
                KbAction::Refresh { action, args } => match action {
                    None => run_kb_refresh(args.clone()),
                    Some(KbRefreshAction::Markdown(a)) => run_kb_refresh_markdown(a.clone()),
                    Some(KbRefreshAction::Db(a)) => run_kb_refresh_db(a.clone()),
                },
                KbAction::Query(args) => run_kb_query(args.clone()),
                KbAction::NewBundle(args) => run_kb_new_bundle(args.clone()),
                KbAction::AddConcept(args) => run_kb_add_concept(args.clone()),
                KbAction::Sync { action } => match action {
                    KbSyncAction::Status(a) => run_kb_sync_status(a.clone()),
                    KbSyncAction::Pull(a) => run_kb_sync_pull(a.clone()),
                    KbSyncAction::Push(a) => run_kb_sync_push(a.clone()),
                    KbSyncAction::Diff(a) => run_kb_sync_diff(a.clone()),
                },
                KbAction::Intent { action } => match action {
                    KbIntentAction::Init(a) => run_kb_intent_init(a.clone()),
                    KbIntentAction::New(a) => run_kb_intent_new(a.clone()),
                    KbIntentAction::List(a) => run_kb_intent_list(a.clone()),
                    KbIntentAction::Show(a) => run_kb_intent_show(a.clone()),
                    KbIntentAction::Check(a) => run_kb_intent_check(a.clone()),
                    KbIntentAction::Refine(a) => run_kb_intent_refine(a.clone()),
                    KbIntentAction::Start(a) => run_kb_intent_start(a.clone()),
                    KbIntentAction::Move(a) => run_kb_intent_move(a.clone()),
                    KbIntentAction::Release(a) => run_kb_intent_release(a.clone()),
                    KbIntentAction::Cancel(a) => run_kb_intent_cancel(a.clone()),
                    KbIntentAction::Supersede(a) => run_kb_intent_supersede(a.clone()),
                },
                KbAction::Decision { action } => match action {
                    KbDecisionAction::List(a) => run_kb_decision_list(a.clone()),
                    KbDecisionAction::Show(a) => run_kb_decision_show(a.clone()),
                },
            },
            Commands::Gleam {
                action,
                json,
                json_lines,
            } => match action {
                GleamAction::Compile {
                    input,
                    output,
                    package_name,
                    config,
                    project,
                } => {
                    let ready = self.ready()?;
                    run_gleam_compile(
                        self.out.clone(),
                        input.clone(),
                        output.clone(),
                        package_name.clone(),
                        config.clone(),
                        project.clone(),
                        *json,
                        *json_lines,
                        ready,
                    )
                    .await
                }
                GleamAction::Generate {
                    input,
                    output,
                    config,
                    project,
                } => {
                    run_gleam_generate(
                        self.out.clone(),
                        input.clone(),
                        output.clone(),
                        config.clone(),
                        project.clone(),
                        *json,
                        *json_lines,
                    )
                    .await
                }
                GleamAction::Roundtrip {
                    input,
                    output,
                    package_name,
                    config,
                    project,
                } => {
                    let ready = self.ready()?;
                    run_gleam_roundtrip(
                        self.out.clone(),
                        input.clone(),
                        output.clone(),
                        package_name.clone(),
                        config.clone(),
                        project.clone(),
                        *json,
                        *json_lines,
                        ready,
                    )
                    .await
                }
            },
            Commands::Schema { output } => commands::schema::run_schema(output.clone()),
            Commands::Version { json } => run_version(*json),
            Commands::Usage => {
                use clap::CommandFactory;
                let cli = Cli::command();
                let spec: usage::Spec = cli.into();
                println!("{}", spec);
                Ok(None)
            }
        }
    }

    async fn shutdown(&mut self) -> AppResult<miette::Report> {
        // starbase runs this after a failed phase too, so it may be reached with
        // `SessionState::Bootstrapped`. It therefore reports what it has rather
        // than assuming a completed run.
        //
        // The exit code is not available here: `execute` runs on a clone, so its
        // result reaches `AppRunOutcome` rather than this session. `run()` still
        // reports that, and this phase reports only what belongs to the session.
        tracing::debug!(
            target: "morphir::correlation",
            schema_version = 1,
            component = "cli",
            event_name = "cli.session.shutdown",
            operation_id = %self.operation_id,
            configured = matches!(self.state, SessionState::Ready(_)),
            "CLI session shutting down"
        );
        Ok(None)
    }
}

fn report_operation_outcome(
    operation_id: &observability::OperationId,
    logging_guard: Option<&logging::LogGuard>,
    exit_code: u8,
    failed: bool,
    diagnostic: Option<&str>,
) {
    logging::record_operation_finish(operation_id, logging_guard, exit_code, failed, diagnostic);
    if failed {
        eprintln!("Operation ID: {operation_id}");
        if let Some(log) = logging_guard.map(logging::LogGuard::log_path) {
            eprintln!("Log: {}", log.display());
        }
    }
}

fn operation_diagnostic(raw: Option<String>, exit_code: u8) -> Option<String> {
    raw.filter(|diagnostic| !diagnostic.trim().is_empty())
        .or_else(|| {
            (exit_code != 0).then(|| {
                format!(
                    "command exited with status {exit_code}; details were reported by the command"
                )
            })
        })
        .map(|diagnostic| commands::diagnostics::sanitize_text(&diagnostic))
}

/// The process entry point, synchronous on purpose.
///
/// `#[tokio::main]` would build the runtime and `expect` it *before* running
/// the async body, so a runtime that fails to build, under thread or file
/// descriptor exhaustion, would panic through the standard handler with none of
/// our reporting installed. Installing diagnostics first means that panic
/// renders like every other CLI error, and a build failure is reported as a
/// diagnostic rather than panicking at all.
///
/// The builder below reproduces what `#[tokio::main]` generates for a bare
/// attribute: a multi-threaded runtime with all drivers enabled.
fn main() -> starbase::MainResult {
    use miette::IntoDiagnostic as _;

    morphir::diagnostics::install();

    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .into_diagnostic()?
        .block_on(run())
}

async fn run() -> starbase::MainResult {
    use clap::CommandFactory;
    use tracing::Instrument as _;

    // Logging comes up before anything can report. It runs ahead of argv
    // parsing because a failure in that parse still has to be logged.
    let operation_id = observability::OperationId::new();
    // Keep the guard alive until process exit so non-blocking file logs flush.
    let logging_guard = logging::init_from_env(&operation_id);
    let operation_span = tracing::debug_span!(
        target: "morphir::correlation",
        "cli.operation",
        operation_id = %operation_id
    );

    async move {
        tracing::debug!(
            schema_version = 1,
            component = "cli",
            event_name = "cli.command.dispatch",
            "CLI command dispatch started"
        );
        // Check for help/version flags first to print our custom banner
        let args: Vec<String> = std::env::args().collect();

        if help::should_show_banner(&args) {
            help::print_banner();
        }

        // Handle full help variants
        if help::should_show_full_help(&args) {
            help::print_full_help::<Cli>();
            report_operation_outcome(&operation_id, logging_guard.as_ref(), 0, false, None);
            return Ok(std::process::ExitCode::SUCCESS);
        }

        // Handle version subcommand early (before starbase) to avoid double execution
        if args.len() >= 2 && args[1] == "version" {
            let json = args.iter().any(|a| a == "--json");
            match run_version(json) {
                Ok(code) => {
                    let exit_code = code.unwrap_or(0);
                    report_operation_outcome(
                        &operation_id,
                        logging_guard.as_ref(),
                        exit_code,
                        exit_code != 0,
                        operation_diagnostic(None, exit_code).as_deref(),
                    );
                    return Ok(std::process::ExitCode::from(exit_code));
                }
                Err(error) => {
                    let diagnostic = operation_diagnostic(Some(error.to_string()), 1);
                    report_operation_outcome(
                        &operation_id,
                        logging_guard.as_ref(),
                        1,
                        true,
                        diagnostic.as_deref(),
                    );
                    return Err(error);
                }
            }
        }

        // Handle usage subcommand early (before starbase) to avoid double execution
        if args.len() >= 2 && args[1] == "usage" {
            use clap::CommandFactory;
            let cli = Cli::command();
            let spec: usage::Spec = cli.into();
            println!("{}", spec);
            report_operation_outcome(&operation_id, logging_guard.as_ref(), 0, false, None);
            return Ok(std::process::ExitCode::SUCCESS);
        }

        let cli = match Cli::try_parse_from(&args) {
            Ok(cli) => cli,
            Err(error) => {
                let exit_code = u8::try_from(error.exit_code()).unwrap_or(1);
                let failed = exit_code != 0;
                let diagnostic = operation_diagnostic(Some(error.to_string()), exit_code);
                let _ = error.print();
                report_operation_outcome(
                    &operation_id,
                    logging_guard.as_ref(),
                    exit_code,
                    failed,
                    diagnostic.as_deref(),
                );
                return Ok(std::process::ExitCode::from(exit_code));
            }
        };

        // Read before `cli.command` is moved below.
        let out_dir = cli.out_dir.clone();

        // Handle case where no command is provided.
        let command = match cli.command {
            Some(cmd) => cmd,
            None => {
                Cli::command().print_help().ok();
                report_operation_outcome(&operation_id, logging_guard.as_ref(), 0, false, None);
                return Ok(std::process::ExitCode::SUCCESS);
            }
        };

        // Handle migration subcommands early (before starbase) to avoid double execution.
        let command = match command {
            Commands::Migrate(migrate_args)
            | Commands::Ir {
                action: IrAction::Migrate(migrate_args),
            } => {
                let (exit_code, failed, diagnostic) = match migrate_args.run() {
                    Ok(Some(code)) => (code, code != 0, operation_diagnostic(None, code)),
                    Ok(None) => (0, false, None),
                    Err(error) => (1, true, operation_diagnostic(Some(error.to_string()), 1)),
                };
                report_operation_outcome(
                    &operation_id,
                    logging_guard.as_ref(),
                    exit_code,
                    failed,
                    diagnostic.as_deref(),
                );
                return Ok(std::process::ExitCode::from(exit_code));
            }
            command => command,
        };

        // Create session with command
        let session = MorphirSession {
            command,
            operation_id: operation_id.clone(),
            out: commands::OutOverrides::from_process(out_dir),
            state: SessionState::Bootstrapped,
        };

        // Initialize and run starbase App.
        // As of starbase 0.13, run() returns AppRunOutcome rather than a Result;
        // into_miette_result() preserves the real exit code instead of miette's
        // default of always reporting 1 on error.
        let outcome = App::default()
            .run(
                session,
                |_session| async move { Ok::<_, miette::Report>(None) },
            )
            .await;
        let failed = outcome.error.is_some() || outcome.exit_code != 0;
        let diagnostic = operation_diagnostic(
            outcome.error.as_ref().map(ToString::to_string),
            outcome.exit_code,
        );
        report_operation_outcome(
            &operation_id,
            logging_guard.as_ref(),
            outcome.exit_code,
            failed,
            diagnostic.as_deref(),
        );
        outcome.into_miette_result()
    }
    .instrument(operation_span)
    .await
}

#[cfg(test)]
mod operation_diagnostic_tests {
    use super::operation_diagnostic;

    #[test]
    fn nonzero_outcomes_never_record_an_empty_diagnostic() {
        assert_eq!(operation_diagnostic(None, 0), None);
        assert_eq!(
            operation_diagnostic(None, 7).as_deref(),
            Some("command exited with status 7; details were reported by the command")
        );
        assert_eq!(
            operation_diagnostic(Some("request failed: --api-key LIVE_SECRET".to_owned()), 1)
                .as_deref(),
            Some("[REDACTED]")
        );
    }

    /// Asking for the loaded configuration before startup has produced it is a
    /// programming error, and it names the phase rather than returning an empty
    /// configuration that reads as "nothing was configured". Conflating those two
    /// is what made GH #887 silent.
    #[test]
    fn asking_for_ready_before_startup_names_the_phase() {
        use super::{MorphirSession, SessionState};

        let session = MorphirSession {
            command: super::Commands::Usage,
            operation_id: morphir::observability::OperationId::new(),
            out: super::commands::OutOverrides::default(),
            state: SessionState::Bootstrapped,
        };

        let failure = session
            .ready()
            .expect_err("no configuration before startup");

        let message = failure.to_string();
        assert!(message.contains("startup"), "{message}");
    }
}
