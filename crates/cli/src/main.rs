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
struct MakeArgs {
    #[arg(short, long)]
    project_dir: Option<OsString>,
    #[arg(short, long)]
    output: Option<OsString>,
}

#[derive(Debug, Args)]
#[command(args_conflicts_with_subcommands = true)]
#[command(flatten_help = true)]
struct GenArgs {
    #[arg(short, long)]
    input: Option<OsString>,
    #[arg(short, long)]
    output: Option<OsString>,
    #[arg(short, long)]
    target: Option<OsString>,
    #[arg(short = 'v', long)]
    target_version: Option<OsString>,
    #[arg(short, long)]
    copy_deps: Option<OsString>,
}

#[derive(Debug, Args)]
#[command(args_conflicts_with_subcommands = true)]
#[command(flatten_help = true)]
struct DevelopArgs {
    #[arg(short, long)]
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
