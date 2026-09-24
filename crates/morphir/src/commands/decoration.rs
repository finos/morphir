use clap::{Args, Subcommand};
use morphir_core::node_address::NodeUri;
use morphir_decoration::project::DecorationProject;
use std::path::PathBuf;

#[derive(Clone, Args)]
pub struct DecorationInput {
    /// Project config containing the named decoration
    #[arg(long, default_value = "morphir.json")]
    config: PathBuf,
    /// Exact V3 or V4 target IR JSON to decorate
    #[arg(long)]
    ir: PathBuf,
    /// Decoration name from the project config
    name: String,
}

#[derive(Clone, Subcommand)]
pub enum DecorationAction {
    /// Add or replace one typed value at a semantic node URI
    Set {
        #[command(flatten)]
        input: DecorationInput,
        /// Portable Morphir node URI
        target: String,
        /// File containing one JSON value
        #[arg(long)]
        value: PathBuf,
    },
    /// Read and validate a sidecar, then print its JSON
    Show {
        #[command(flatten)]
        input: DecorationInput,
    },
    /// Check all configured targets and values
    Validate {
        #[command(flatten)]
        input: DecorationInput,
    },
    /// Replace a legacy flat V3 NodeID map with URI keys
    MigrateV3 {
        #[command(flatten)]
        input: DecorationInput,
    },
}

pub fn run(action: &DecorationAction) -> miette::Result<()> {
    match action {
        DecorationAction::Set {
            input,
            target,
            value,
        } => {
            let project = open(input)?;
            let uri = NodeUri::parse(target).map_err(|error| miette::miette!("{error}"))?;
            let text = std::fs::read_to_string(value)
                .map_err(|error| miette::miette!("{}: {error}", value.display()))?;
            let value = morphir_core::ir::json::read(&text)
                .map_err(|error| miette::miette!("invalid decoration value JSON: {error:?}"))?;
            project
                .set(uri, value)
                .map_err(|error| miette::miette!("{error}"))?;
            println!("Updated {}", project.sidecar_path.display());
        }
        DecorationAction::Show { input } => {
            let project = open(input)?;
            let json = project
                .load()
                .map_err(|error| miette::miette!("{error}"))?
                .to_json()
                .map_err(|error| miette::miette!("{error}"))?;
            print!("{json}");
        }
        DecorationAction::Validate { input } => {
            let project = open(input)?;
            let sidecar = project.load().map_err(|error| miette::miette!("{error}"))?;
            println!(
                "Validated {} targets in {}",
                sidecar.targets().len(),
                project.sidecar_path.display()
            );
        }
        DecorationAction::MigrateV3 { input } => {
            let project = open(input)?;
            project
                .migrate_v3()
                .map_err(|error| miette::miette!("{error}"))?;
            println!("Migrated {}", project.sidecar_path.display());
        }
    }
    Ok(())
}

fn open(input: &DecorationInput) -> miette::Result<DecorationProject> {
    DecorationProject::open(&input.config, &input.name, &input.ir)
        .map_err(|error| miette::miette!("{error}"))
}
