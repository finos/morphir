//! Scratch Playground host.

use std::sync::Arc;

use clap::Args;

use super::ui::protocol::InitialView;
use super::ui::provider::{SessionCapabilities, playground::NativePlaygroundProvider};
use super::ui::server::BoundUiHost;

#[derive(Clone, Debug, Args)]
pub struct PlaygroundArgs {
    /// Print the one-time launch URL instead of opening a browser.
    #[arg(long)]
    pub no_open: bool,
}

pub async fn run_playground(args: PlaygroundArgs) -> Result<Option<u8>, miette::Report> {
    let session_id = super::ui::generate_session_id()?;
    let home = crate::home::MorphirHome::resolve()
        .map_err(|error| miette::miette!("Unable to resolve Morphir Home: {error}"))?;
    let capabilities = SessionCapabilities {
        playground: Some(Arc::new(NativePlaygroundProvider::new(home))),
        initial_view: Some(InitialView::Playground),
        ..Default::default()
    };
    let host = BoundUiHost::bind(session_id, capabilities)
        .await
        .map_err(miette::Report::new)?;
    let base_url = host.base_url();
    let launch_url = host.launch_url();
    tracing::info!(url = %base_url, "Morphir Playground listening");
    if args.no_open {
        eprintln!("Morphir Playground: {launch_url}");
    } else {
        webbrowser::open(&launch_url)
            .map_err(|error| miette::miette!("Unable to open the Morphir Playground: {error}"))?;
    }
    tokio::select! {
        result = host.serve() => result.map_err(miette::Report::new)?,
        signal = tokio::signal::ctrl_c() => signal
            .map_err(|error| miette::miette!("Unable to listen for shutdown signal: {error}"))?,
    }
    tracing::info!(url = %base_url, "Morphir Playground stopped");
    Ok(None)
}
