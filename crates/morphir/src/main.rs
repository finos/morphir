use clap::{Args, Parser, Subcommand};
use starbase::{App, AppResult, AppSession};

pub mod commands;
pub mod error;
mod help;
pub mod home;
mod log_lock;
mod logging;
pub mod output;

use morphir::observability;

use commands::{
    GenerateOptions, MigrateCommandOptions, OutputLayout, compile::CompileOptions, run_compile,
    run_config_get, run_config_path, run_config_show, run_diagnostics_path, run_dist_install,
    run_dist_list, run_dist_uninstall, run_dist_update, run_extension_install, run_extension_list,
    run_extension_uninstall, run_extension_update, run_generate, run_gleam_compile,
    run_gleam_generate, run_gleam_roundtrip, run_kb_add_concept, run_kb_check,
    run_kb_decision_list, run_kb_decision_show, run_kb_index, run_kb_intent_cancel,
    run_kb_intent_check, run_kb_intent_init, run_kb_intent_list, run_kb_intent_move,
    run_kb_intent_new, run_kb_intent_refine, run_kb_intent_release, run_kb_intent_show,
    run_kb_intent_start, run_kb_intent_supersede, run_kb_list, run_kb_new_bundle, run_kb_query,
    run_kb_refresh, run_kb_refresh_db, run_kb_refresh_markdown, run_kb_search, run_kb_show,
    run_kb_sync_diff, run_kb_sync_pull, run_kb_sync_push, run_kb_sync_status, run_migrate,
    run_tool_install, run_tool_list, run_tool_uninstall, run_tool_update, run_transform,
    run_validate, run_version,
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

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Clone, Subcommand)]
enum Commands {
    // ===== Core Commands =====
    /// Compile source code to Morphir IR
    Compile {
        /// Source language (e.g., gleam, elm)
        #[arg(short, long)]
        language: Option<String>,
        /// Extension provider id for single-file Elm compilation. Defaults to morphir- followed by the language name.
        #[arg(long)]
        extension: Option<String>,
        /// Input source directory or file. An installed or configured Elm process accepts one .elm file.
        #[arg(short, long)]
        input: Option<String>,
        /// Output directory
        #[arg(short, long)]
        output: Option<String>,
        /// Package name override
        #[arg(long)]
        package_name: Option<String>,
        /// Explicit config file path. An Elm command is a development override for the installed extension.
        #[arg(long)]
        config: Option<String>,
        /// Project name (for workspaces)
        #[arg(long)]
        project: Option<String>,
        /// Output as JSON
        #[arg(long)]
        json: bool,
        /// Output as JSON Lines (streaming)
        #[arg(long)]
        json_lines: bool,
    },
    /// Generate code from Morphir IR
    Generate {
        /// Target language or format
        #[arg(short, long)]
        target: Option<String>,
        /// Path to the Morphir IR file or directory
        #[arg(short, long)]
        input: Option<String>,
        /// Output directory
        #[arg(short, long)]
        output: Option<String>,
        /// Explicit config file path
        #[arg(long)]
        config: Option<String>,
        /// Project name (for workspaces)
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
    /// Manage Morphir tools, distributions, and extensions
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
enum ToolAction {
    /// Install a Morphir tool or extension
    Install {
        /// Name of the tool to install
        name: String,
        /// Version to install (defaults to latest)
        #[arg(short, long)]
        version: Option<String>,
    },
    /// List installed Morphir tools
    List,
    /// Update an installed Morphir tool
    Update {
        /// Name of the tool to update
        name: String,
        /// Version to update to (defaults to latest)
        #[arg(short, long)]
        version: Option<String>,
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
        /// Controlled local extension index directory
        #[arg(long)]
        index: std::path::PathBuf,
        /// Moving release channel (defaults to stable)
        #[arg(long, conflicts_with = "version")]
        channel: Option<String>,
        /// Exact semantic version
        #[arg(long, conflicts_with = "channel")]
        version: Option<String>,
    },
    /// List installed Morphir extensions
    List,
    /// Update an installed Morphir extension
    Update {
        /// Name of the extension to update
        name: String,
        /// Controlled local extension index directory
        #[arg(long)]
        index: std::path::PathBuf,
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
enum GleamAction {
    /// Compile Gleam source to Morphir IR
    Compile {
        /// Input source directory or file
        #[arg(short, long)]
        input: Option<String>,
        /// Output directory
        #[arg(short, long)]
        output: Option<String>,
        /// Package name override
        #[arg(long)]
        package_name: Option<String>,
        /// Explicit config file path
        #[arg(long)]
        config: Option<String>,
        /// Project name (for workspaces)
        #[arg(long)]
        project: Option<String>,
    },
    /// Generate Gleam code from Morphir IR
    Generate {
        /// Path to the Morphir IR file or directory
        #[arg(short, long)]
        input: Option<String>,
        /// Output directory
        #[arg(short, long)]
        output: Option<String>,
        /// Explicit config file path
        #[arg(long)]
        config: Option<String>,
        /// Project name (for workspaces)
        #[arg(long)]
        project: Option<String>,
    },
    /// Roundtrip: compile then generate (for testing)
    Roundtrip {
        /// Input source directory or file
        #[arg(short, long)]
        input: Option<String>,
        /// Output directory
        #[arg(short, long)]
        output: Option<String>,
        /// Package name override
        #[arg(long)]
        package_name: Option<String>,
        /// Explicit config file path
        #[arg(long)]
        config: Option<String>,
        /// Project name (for workspaces)
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

/// Application session for Morphir CLI
#[derive(Clone)]
struct MorphirSession {
    command: Commands,
}

#[async_trait::async_trait]
impl AppSession for MorphirSession {
    type Error = miette::Report;

    async fn execute(&mut self) -> AppResult<miette::Report> {
        match &self.command {
            Commands::Validate { input } => run_validate(input.clone()),
            Commands::Compile {
                language,
                extension,
                input,
                output,
                package_name,
                config,
                project,
                json,
                json_lines,
            } => {
                run_compile(CompileOptions {
                    language: language.clone(),
                    extension: extension.clone(),
                    input: input.clone(),
                    output: output.clone(),
                    package_name: package_name.clone(),
                    config_path: config.clone(),
                    project: project.clone(),
                    json: *json,
                    json_lines: *json_lines,
                })
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
                })
                .await
            }
            Commands::Transform { input, output } => run_transform(input.clone(), output.clone()),
            Commands::Migrate(args) => args.run(),
            Commands::Ui(args) => commands::ui::run_ui(args.clone()).await,
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
            Commands::Tool { action } => match action {
                ToolAction::Install { name, version } => {
                    run_tool_install(name.clone(), version.clone())
                }
                ToolAction::List => run_tool_list(),
                ToolAction::Update { name, version } => {
                    run_tool_update(name.clone(), version.clone())
                }
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
                    index,
                    channel,
                    version,
                } => run_extension_install(
                    name.clone(),
                    index.clone(),
                    channel.clone(),
                    version.clone(),
                ),
                ExtensionAction::List => run_extension_list(),
                ExtensionAction::Update {
                    name,
                    index,
                    channel,
                    version,
                } => run_extension_update(
                    name.clone(),
                    index.clone(),
                    channel.clone(),
                    version.clone(),
                ),
                ExtensionAction::Uninstall { name } => run_extension_uninstall(name.clone()),
            },
            Commands::Ir { action } => match action {
                IrAction::Migrate(args) => args.run(),
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
                    run_gleam_compile(
                        input.clone(),
                        output.clone(),
                        package_name.clone(),
                        config.clone(),
                        project.clone(),
                        *json,
                        *json_lines,
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
                    run_gleam_roundtrip(
                        input.clone(),
                        output.clone(),
                        package_name.clone(),
                        config.clone(),
                        project.clone(),
                        *json,
                        *json_lines,
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

#[tokio::main]
async fn main() -> starbase::MainResult {
    use clap::CommandFactory;
    use tracing::Instrument as _;

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
        let session = MorphirSession { command };

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
}
