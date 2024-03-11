use clap::{Args, Parser, Subcommand};
use std::ffi::OsString;

#[derive(Debug, Parser)]
#[command(name = "morphir")]
#[command(about = "CLI tooling/commands for the morphir ecosystem", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    Make(MakeArgs),
    Gen(GenArgs),
    Develop(DevelopArgs),
    Restore,
}

#[derive(Debug, Args)]
#[command(args_conflicts_with_subcommands = true)]
#[command(flatten_help = true)]
#[command(about = "Translate Elm sources to Morphir IR")]
struct MakeArgs {
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
struct GenArgs {
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
struct DevelopArgs {
    #[arg(short, long)]
    /// Root directory of the project where morphir.json is located. (default: ".")
    project_dir: Option<OsString>,
}

fn main() {
    let args = Cli::parse();
    match args.command {
        Commands::Make(args) => {
            println!("Make - Not Implemented Yet");
            println!("Args: {:?}", args);
        }
        Commands::Gen(args) => {
            println!("Generating - Not Implemented Yet");
            println!("Args: {:?}", args);
        }
        Commands::Develop(args) => {
            println!("Develop (Starting Server) - Not Implemented Yet");
            println!("Args: {:?}", args);
        }
        Commands::Restore => {
            println!("Restoring - Not Implemented Yet");
        }
    }
}