use clap::{Parser, Subcommand};
use starbase::{App, AppResult, AppSession};

pub mod commands;
pub mod error;
mod help;
mod logging;
pub mod output;
mod tui;

use commands::{
    compile::CompileOptions, run_compile, run_dist_install, run_dist_list, run_dist_uninstall,
    run_dist_update, run_extension_install, run_extension_list, run_extension_uninstall,
    run_extension_update, run_generate, run_gleam_compile, run_gleam_generate, run_gleam_roundtrip,
    run_migrate, run_tool_install, run_tool_list, run_tool_uninstall, run_tool_update,
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

    // ===== Management Commands =====
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
        /// Version to install (defaults to latest)
        #[arg(short, long)]
        version: Option<String>,
    },
    /// List installed Morphir extensions
    List,
    /// Update an installed Morphir extension
    Update {
        /// Name of the extension to update
        name: String,
        /// Version to update to (defaults to latest)
        #[arg(short, long)]
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

Converts Morphir IR between Classic (V1-V3) and V4 formats. Supports local files, URLs, and GitHub shorthand sources.

**Examples:**

```bash
# Migrate to file
morphir ir migrate ./morphir-ir.json -o ./morphir-ir-v4.json --target-version v4

# Migrate from URL
morphir ir migrate https://lcr-interactive.finos.org/server/morphir-ir.json -o ./lcr-v4.json

# Display in console with syntax highlighting (no -o)
morphir ir migrate ./morphir-ir.json

# Downgrade V4 to Classic
morphir ir migrate ./morphir-ir-v4.json -o ./morphir-ir-classic.json --target-version classic
```

See the [IR Migration Guide](/ir-migrate/) for detailed real-world examples including the US Federal Reserve FR 2052a regulation model.")]
    Migrate {
        /// Input file, directory, or remote source (e.g., github:owner/repo, URL)
        input: String,
        /// Output file or directory (if omitted, displays in console with syntax highlighting)
        #[arg(short, long)]
        output: Option<std::path::PathBuf>,
        /// Target version: latest, v4/4, classic, v3/3, v2/2, v1/1 (default: latest)
        #[arg(long, default_value = "latest")]
        target_version: String,
        /// Force refresh cached remote sources
        #[arg(long)]
        force_refresh: bool,
        /// Skip cache entirely for remote sources
        #[arg(long)]
        no_cache: bool,
        /// Output result as JSON (for scripting)
        #[arg(long)]
        json: bool,
        /// Use expanded (non-compact) format for V4 output
        #[arg(long)]
        expanded: bool,
    },
}

/// Application session for Morphir CLI
#[derive(Clone)]
struct MorphirSession {
    command: Commands,
}

#[async_trait::async_trait]
impl AppSession for MorphirSession {
    async fn execute(&mut self) -> AppResult {
        match &self.command {
            Commands::Validate { input } => run_validate(input.clone()),
            Commands::Compile {
                language,
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
                json,
                json_lines,
            } => {
                run_generate(
                    target.clone(),
                    input.clone(),
                    output.clone(),
                    config.clone(),
                    project.clone(),
                    *json,
                    *json_lines,
                )
                .await
            }
            Commands::Transform { input, output } => run_transform(input.clone(), output.clone()),
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
                ExtensionAction::Install { name, version } => {
                    run_extension_install(name.clone(), version.clone())
                }
                ExtensionAction::List => run_extension_list(),
                ExtensionAction::Update { name, version } => {
                    run_extension_update(name.clone(), version.clone())
                }
                ExtensionAction::Uninstall { name } => run_extension_uninstall(name.clone()),
            },
            Commands::Ir { action } => match action {
                IrAction::Migrate {
                    input,
                    output,
                    target_version,
                    force_refresh,
                    no_cache,
                    json,
                    expanded,
                } => run_migrate(
                    input.clone(),
                    output.clone(),
                    target_version.clone(),
                    *force_refresh,
                    *no_cache,
                    *json,
                    *expanded,
                ),
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

#[tokio::main]
async fn main() -> starbase::MainResult {
    use clap::CommandFactory;

    // Check for help/version flags first to print our custom banner
    let args: Vec<String> = std::env::args().collect();

    if help::should_show_banner(&args) {
        help::print_banner();
    }

    // Handle full help variants
    if help::should_show_full_help(&args) {
        help::print_full_help::<Cli>();
        return Ok(std::process::ExitCode::SUCCESS);
    }

    // Handle version subcommand early (before starbase) to avoid double execution
    if args.len() >= 2 && args[1] == "version" {
        let json = args.iter().any(|a| a == "--json");
        if let Some(code) = run_version(json)? {
            return Ok(std::process::ExitCode::from(code));
        }
        return Ok(std::process::ExitCode::SUCCESS);
    }

    // Handle usage subcommand early (before starbase) to avoid double execution
    if args.len() >= 2 && args[1] == "usage" {
        use clap::CommandFactory;
        let cli = Cli::command();
        let spec: usage::Spec = cli.into();
        println!("{}", spec);
        return Ok(std::process::ExitCode::SUCCESS);
    }

    // Handle ir subcommand early (before starbase) to avoid double execution
    if args.len() >= 3 && args[1] == "ir" {
        let cli = Cli::parse();
        if let Some(Commands::Ir { action }) = cli.command {
            let result = match action {
                IrAction::Migrate {
                    input,
                    output,
                    target_version,
                    force_refresh,
                    no_cache,
                    json,
                    expanded,
                } => run_migrate(
                    input,
                    output,
                    target_version,
                    force_refresh,
                    no_cache,
                    json,
                    expanded,
                ),
            };
            match result {
                Ok(Some(code)) => return Ok(std::process::ExitCode::from(code)),
                Ok(None) => return Ok(std::process::ExitCode::SUCCESS),
                Err(e) => {
                    eprintln!("Error: {}", e);
                    return Ok(std::process::ExitCode::from(1));
                }
            }
        }
    }

    let cli = Cli::parse();

    // Handle case where no command is provided
    let command = match cli.command {
        Some(cmd) => cmd,
        None => {
            Cli::command().print_help().ok();
            return Ok(std::process::ExitCode::SUCCESS);
        }
    };

    // Create session with command
    let session = MorphirSession { command };

    // Initialize and run starbase App
    let exit_code = App::default()
        .run(
            session,
            |mut session| async move { session.execute().await },
        )
        .await?;

    Ok(std::process::ExitCode::from(exit_code))
}
