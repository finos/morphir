//! Command-line interface definitions for morphir-live.
//! This module is only compiled for native (non-WASM) targets.

use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "morphir-live")]
#[command(about = "Interactive visualization and management tool for Morphir IR")]
pub struct Cli {
    /// Path to morphir.toml, morphir.json, or directory containing one
    #[arg(long, short)]
    pub path: Option<PathBuf>,

    #[command(subcommand)]
    pub command: Option<Commands>,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Print version information
    Version,
    /// Start the Morphir Live server
    Serve,
}
