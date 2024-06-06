#![allow(dead_code, unused)]

use crate::actors::workspace::{WorkspaceActor, WorkspaceCoordinator};
use crate::cli;
use crate::cli_args::{Cli, Commands};
use clap::Parser;
use coerce::actor::system::ActorSystem;
use coerce::actor::{IntoActor, LocalActorRef};
use std::ffi::OsString;
use thiserror::Error;
use tokio::sync::oneshot::channel;
use tokio::sync::oneshot::error::RecvError;

type Result<T> = std::result::Result<T, error::Error>;
pub struct MorphirApp;

impl MorphirApp {
    pub fn new() -> Self {
        Self
    }
    pub async fn run(&self, args: Vec<String>) -> Result<()> {
        async fn start_up(launch_dir: OsString) -> Result<LocalActorRef<WorkspaceActor>> {
            let system = ActorSystem::new();
            let (tx, rx) = channel();
            let workspace = WorkspaceActor::new(launch_dir, tx)
                .into_actor(Some("workspace"), &system)
                .await?;
            Ok(workspace)
        }

        let cli = Cli::parse_from(args);
        match cli.command {
            Commands::About(args) => {
                println!("About - Not Implemented Yet");
                println!("Args: {:?}", args);
                let workspace_path = std::env::current_dir()?;
                println!("Workspace: {:?}", workspace_path);
            }
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
            Commands::Restore(args) => {
                println!("Restoring - Not Implemented Yet");
                println!("Args: {:?}", args);
            }
            Commands::Run(args) => {
                println!("Running - Not Implemented Yet");
                println!("Args: {:?}", args);
            }
        }

        // let system = ActorSystem::new();
        // let (tx,rx) = channel();
        // let workspace_coordinator = WorkspaceCoordinator::new(tx);
        //
        // let _ = rx.await?;
        Ok(())
    }
}

pub mod error {
    use thiserror::Error;

    #[derive(Error, Debug)]
    pub enum Error {
        #[error("Receive error encountered: {0}")]
        RecvError(#[from] tokio::sync::oneshot::error::RecvError),
        #[error("ActorRef error encountered: {0}")]
        ActorRefError(#[from] coerce::actor::ActorRefErr),
        #[error("IO error encountered: {0}")]
        IoError(#[from] std::io::Error),
    }
}
