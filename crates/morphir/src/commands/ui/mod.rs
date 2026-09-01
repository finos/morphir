//! Loopback web UI host.

use std::{path::PathBuf, sync::Arc};

use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use clap::Args;

use provider::{
    SessionCapabilities, WorkspaceCapability, extension::ExtensionWorkspaceProvider,
    native::NativeWorkspaceProvider,
};
use server::BoundUiHost;

pub mod assets;
pub mod auth;
pub mod protocol;
pub mod provider;
pub mod rpc;
pub mod server;

#[derive(Clone, Debug, Args)]
pub struct UiArgs {
    /// Morphir development workspace to open. Defaults to the current directory.
    #[arg(value_name = "WORKSPACE")]
    pub workspace: Option<PathBuf>,

    /// Use one installed workspace-capability extension by ID.
    #[arg(long, value_name = "ID")]
    pub workspace_extension: Option<String>,

    /// Print the one-time launch URL instead of opening a browser.
    #[arg(long)]
    pub no_open: bool,
}

pub async fn run_ui(args: UiArgs) -> Result<Option<u8>, miette::Report> {
    let workspace = match args.workspace {
        Some(path) => path,
        None => std::env::current_dir()
            .map_err(|error| miette::miette!("Unable to resolve current directory: {error}"))?,
    };
    if !workspace.is_dir() {
        return Err(miette::miette!(
            "Morphir UI workspace must be an existing directory: {}",
            workspace.display()
        ));
    }
    let session_id = generate_session_id()?;
    let home = crate::home::MorphirHome::resolve()
        .map_err(|error| miette::miette!("Unable to resolve Morphir Home: {error}"))?;
    let provider: Arc<dyn WorkspaceCapability> = match args.workspace_extension.as_deref() {
        Some(extension_id) => Arc::new(
            ExtensionWorkspaceProvider::select(home, &workspace, &session_id, Some(extension_id))
                .map_err(miette::Report::new)?,
        ),
        None => Arc::new(
            NativeWorkspaceProvider::discover(&workspace, &session_id)
                .map_err(miette::Report::new)?,
        ),
    };
    let host = BoundUiHost::bind(
        session_id,
        SessionCapabilities {
            workspace: Some(provider),
            // No playground provider, deliberately. The web client vendored
            // under `assets/` validates the session manifest against a schema
            // that requires *every* provider it lists to advertise all four
            // core workspace capabilities at version 1. A playground provider
            // advertises `morphir/playground/*` instead, so including one
            // makes that client reject the whole manifest -- breaking `morphir
            // ui` itself, not just the playground. The provider stays wired up
            // and tested; it gets attached here once a client that understands
            // it is vendored.
            playground: None,
            ..Default::default()
        },
    )
    .await
    .map_err(miette::Report::new)?;
    let base_url = host.base_url();
    let launch_url = host.launch_url();
    tracing::info!(url = %base_url, "Morphir UI listening");
    if args.no_open {
        eprintln!("Morphir UI: {launch_url}");
    } else {
        webbrowser::open(&launch_url)
            .map_err(|error| miette::miette!("Unable to open Morphir UI in a browser: {error}"))?;
    }
    tokio::select! {
        result = host.serve() => result.map_err(miette::Report::new)?,
        signal = tokio::signal::ctrl_c() => signal
            .map_err(|error| miette::miette!("Unable to listen for shutdown signal: {error}"))?,
    }
    tracing::info!(url = %base_url, "Morphir UI stopped");
    Ok(None)
}

pub(super) fn generate_session_id() -> Result<String, miette::Report> {
    let mut bytes = [0_u8; 16];
    getrandom::fill(&mut bytes)
        .map_err(|error| miette::miette!("Unable to generate Morphir UI session ID: {error}"))?;
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}
