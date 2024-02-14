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
    Restore {},
}

#[derive(Debug, Args)]
#[command(args_conflicts_with_subcommands = true)]
#[command(flatten_help = true)]
struct MakeArgs {
    #[arg(short, long)]
    output: Option<OsString>,
}

fn main() {
    let args = Cli::parse();
    match args.command {
        Commands::Make(args) => {
            println!("Making...");
            println!("Args: {:?}", args);
            println!("NOT IMPLEMENTED YET!");
            println!("Done!");
        }
        Commands::Restore {} => {
            println!("Restoring...");
            println!("NOT IMPLEMENTED YET!");
            println!("Done!");
        }
    }
}
