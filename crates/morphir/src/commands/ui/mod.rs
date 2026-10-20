//! Loopback web UI host.

use std::{path::PathBuf, sync::Arc};

use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use clap::Args;

use provider::{
    SessionCapabilities, extension::ExtensionWorkspaceProvider, native::NativeWorkspaceProvider,
    playground::NativePlaygroundProvider,
};
use server::BoundUiHost;

pub mod artifacts;
pub mod assets;
pub mod auth;
pub(in crate::commands::ui) mod installed_observation;
pub mod model_originals;
pub(in crate::commands) mod native_mck;
mod native_startup;
pub mod protocol;
pub mod provider;
pub mod rpc;
pub mod server;
pub(in crate::commands::ui) use native_startup::prepare_native_ui_observed;

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

    /// Enable the model-originals preview before full connected qualification.
    #[arg(long)]
    pub preview_model_originals: bool,
}

#[derive(Clone, Copy)]
enum ModelOriginalsMode {
    Disabled,
    Preview,
}

pub async fn run_ui(
    args: UiArgs,
    out: crate::commands::out_context::OutOverrides,
) -> Result<Option<u8>, miette::Report> {
    let originals_mode = if args.preview_model_originals {
        ModelOriginalsMode::Preview
    } else {
        ModelOriginalsMode::Disabled
    };
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
    let workspace = workspace
        .canonicalize()
        .map_err(|error| miette::miette!("Unable to resolve Morphir UI workspace: {error}"))?;
    let session_id = generate_session_id()?;
    // Resolved up front: both the workspace-extension branch and the
    // playground read extensions out of the same Morphir Home.
    let home = crate::home::MorphirHome::resolve()
        .map_err(|error| miette::miette!("Unable to resolve Morphir Home: {error}"))?;
    let (provider, capabilities) = match args.workspace_extension.as_deref() {
        Some(extension_id) => {
            let provider = ExtensionWorkspaceProvider::select(
                home.clone(),
                &workspace,
                &session_id,
                Some(extension_id),
            )
            .map_err(miette::Report::new)?
            .with_out_overrides(out.clone());
            let provider = match originals_mode {
                ModelOriginalsMode::Disabled => provider,
                ModelOriginalsMode::Preview => provider
                    .authorize_originals_lookup(cap_std::ambient_authority())
                    .map_err(miette::Report::new)?,
            };
            let provider = provider::originals::OriginalsProvider::Installed(Arc::new(provider));
            let capabilities = SessionCapabilities {
                workspace: Some(provider.workspace()),
                playground: Some(Arc::new(NativePlaygroundProvider::in_workspace(
                    home, &workspace,
                ))),
                ..Default::default()
            };
            (provider, capabilities)
        }
        None => {
            let setup = native_startup::prepare_native_ui(
                &workspace,
                &session_id,
                home,
                morphir_devkit::ConfigLoadOptions::default(),
                out,
                originals_mode,
                native_startup::NativeStartupSource::Historical,
            )
            .map_err(miette::Report::new)?;
            (setup.originals_provider(), setup.capabilities())
        }
    };
    let host = match originals_mode {
        ModelOriginalsMode::Disabled => BoundUiHost::bind(session_id, capabilities).await,
        ModelOriginalsMode::Preview => {
            BoundUiHost::bind_with_originals(session_id, capabilities, Some(provider)).await
        }
    }
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
