#![allow(dead_code, unused)]

use crate::actors::workspace::{WorkspaceActor, WorkspaceCoordinator};
use crate::cli;
use crate::cli_args::{Cli, Commands};
use crate::models::tools::ToolId;
use crate::models::workspace::WorkspaceRoot;
use clap::Parser;
use coerce::actor::system::ActorSystem;
use coerce::actor::{IntoActor, LocalActorRef};
use std::ffi::OsString;
use thiserror::Error;
use tokio::sync::oneshot::error::RecvError;
use tokio::sync::oneshot::{channel, Receiver};

type Result<T> = std::result::Result<T, error::Error>;

#[derive(Debug, Default)]
pub struct CliApp {
    pub tool_id: ToolId,
}

impl CliApp {
    pub fn new(tool_id: ToolId) -> Self {
        Self { tool_id }
    }
    pub async fn run(&self, args: Vec<String>) -> Result<()> {
        let cli = Cli::parse_from(args);
        match cli.command {
            Commands::About(args) => {
                let (system, rx, workspace_actor) =
                    Self::start_up(self.tool_id.clone(), OsString::from(".")).await?;
                println!("Args: {:?}", args);
                println!("Startup path: {:?}", std::env::current_dir()?);
                let workspace_root = rx.await?;
                println!("Workspace Root: {:?}", workspace_root);
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
    async fn start_up(
        tool_id: ToolId,
        start_dir: OsString,
    ) -> Result<(
        ActorSystem,
        Receiver<Option<WorkspaceRoot>>,
        LocalActorRef<WorkspaceActor>,
    )> {
        let system = ActorSystem::new();
        let (tx, rx) = channel();
        let workspace = WorkspaceActor::new(tool_id, start_dir, tx)
            .into_actor(Some("workspace"), &system)
            .await?;
        Ok((system, rx, workspace))
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
