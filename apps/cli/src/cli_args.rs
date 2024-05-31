use clap::{Args, Parser, Subcommand};
use std::ffi::OsString;

#[derive(Debug, Parser)]
#[command(name = "morphir")]
#[command(about = "CLI tooling/commands for the morphir ecosystem", long_about = None)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Debug, Subcommand)]
pub enum Commands {
    About(AboutArgs),
    Make(MakeArgs),
    Gen(GenArgs),
    Develop(DevelopArgs),
    Restore(RestoreArgs),
}

#[derive(Debug, Args)]
#[command(about = "Prints information about the morphir CLI tool")]
pub struct AboutArgs;

#[derive(Debug, Args)]
#[command(args_conflicts_with_subcommands = true)]
#[command(flatten_help = true)]
#[command(about = "Translate Elm sources to Morphir IR")]
pub struct MakeArgs {
    #[arg(short, long)]
    /// Root directory of the project where morphir.json is located. (default: ".")
    project_dir: Option<OsString>,
    #[arg(short, long)]
    /// Target file location where the Morphir IR will be saved. (default: "morphir-ir.json")
    output: Option<OsString>,
}

#[derive(Debug, Args)]
#[command(args_conflicts_with_subcommands = true)]
#[command(flatten_help = true)]
#[command(about = "Generate code from Morphir IR")]
pub struct GenArgs {
    #[arg(short, long)]
    /// Source location where the Morphir IR will be loaded from. (default: "morphir-ir.json")
    input: Option<OsString>,
    #[arg(short, long)]
    /// Target location where the generated code will be saved. (default: "./dist")
    output: Option<OsString>,
    #[arg(short, long)]
    /// Language to Generate (Scala | SpringBoot | cypher | triples). (default: "Scala")
    target: Option<OsString>,
    #[arg(short = 'v', long)]
    /// Language version to Generate. (default: "2.11")
    target_version: Option<OsString>,
    #[arg(short, long)]
    /// Copy the dependencies used by the generated code to the output path. (default: false)
    copy_deps: Option<OsString>,
}

#[derive(Debug, Args)]
#[command(args_conflicts_with_subcommands = true)]
#[command(flatten_help = true)]
#[command(about = "Start up a web server and expose developer tools through a web UI")]
pub struct DevelopArgs {
    #[arg(short, long)]
    /// Root directory of the project where morphir.json is located. (default: ".")
    project_dir: Option<OsString>,
}

#[derive(Debug, Args)]
#[command(args_conflicts_with_subcommands = true)]
#[command(flatten_help = true)]
#[command(about = "Restore project or workspaces by restoring dependencies.")]
pub struct RestoreArgs {
    #[arg(short, long)]
    project: Option<OsString>,
}
