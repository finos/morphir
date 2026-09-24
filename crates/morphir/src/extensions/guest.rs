//! One-shot MEP calls to a provider through `morphir_host::Session`.
//!
//! A connection is opened for one negotiation or one call and closed again.
//! Every connection checks method results (artifact paths, compile IR,
//! workspace snapshots) before the CLI sees them, and the session core
//! refuses a method or an invocation the provider did not negotiate.
//!
//! The error texts are the ones the CLI reported when these calls ran on the
//! daemon's typestate session. A `HostError` is formatted through
//! `DaemonError` so a provider message keeps its `Extension error: ` prefix.
//!
//! "Guest" is the morphir-host word for an extension provider: a
//! [`ProviderConnection`] and a `provider` parameter elsewhere in this crate
//! name the same thing seen from the CLI.

use super::NegotiatedProvider;
use crate::error::CliError;
use crate::home::MorphirHome;
use morphir_daemon::DaemonError;
use morphir_distribution::{InstalledExtensionSnapshot, activate_installed_snapshot};
use morphir_extension_sdk::NativeExtension;
use morphir_host::{
    CallError, Channel, ChannelState, ExpectedChecks, ExpectedExtension, HostError,
    JsonRpcConnection, Session,
};
use morphir_host_native::process::{ProcessChannel, ProcessLaunch};
use morphir_host_native::{CheckedConnection, NativeChannel};
use serde::{Serialize, de::DeserializeOwned};
use std::path::Path;

/// A checked MEP connection to one provider, ready to open.
pub(crate) type ProviderConnection =
    CheckedConnection<JsonRpcConnection<Box<dyn Channel>, ExpectedChecks>>;

/// The provider a caller already resolved and checked is present for its
/// selected invocation mode.
///
/// Callers of [`resolved`] have already matched on
/// [`InvocationMode`](morphir_daemon::extensions::InvocationMode) and
/// reported their own "unavailable mode" text when the mode they need is
/// missing, so `resolved` itself never needs to re-check the mode or hold an
/// unreachable branch for it.
pub(crate) enum GuestSource<'a> {
    /// A `NativeMep` resolution: the built-in provider runs in this process.
    Native(&'a NativeExtension),
    /// A `ProcessMep` or `WasmMep` resolution: an installed provider is
    /// activated as a separate guest.
    Installed(&'a InstalledExtensionSnapshot),
}

/// Open a connection to a configured process provider.
pub(crate) async fn configured(
    launch: ProcessLaunch,
    provider: &str,
) -> Result<ProviderConnection, CliError> {
    let channel = ProcessChannel::spawn(launch)
        .await
        .map_err(|error| CliError::Extension {
            message: format!(
                "Failed to start provider '{provider}': {}",
                DaemonError::from(error)
            ),
        })?;
    let expectation = channel.expectation();
    Ok(checked(Box::new(channel), expectation))
}

/// Open a connection to a resolved provider that speaks MEP
/// (`NativeMep`, `ProcessMep` or `WasmMep`).
///
/// The caller passes exactly the source its resolved invocation mode
/// selected; see [`GuestSource`].
pub(crate) async fn resolved(
    home: &MorphirHome,
    workspace: &Path,
    provider: &str,
    source: GuestSource<'_>,
) -> Result<ProviderConnection, CliError> {
    match source {
        GuestSource::Native(native) => {
            let channel = NativeChannel::new(native);
            let expectation = channel.expectation();
            Ok(checked(Box::new(channel), expectation))
        }
        GuestSource::Installed(snapshot) => {
            let artifact = activate_installed_snapshot(home, snapshot).map_err(|error| {
                CliError::Extension {
                    message: format!("Failed to verify installed provider '{provider}': {error}"),
                }
            })?;
            let guest = morphir_host_native::activate(artifact, workspace)
                .await
                .map_err(|error| CliError::Extension {
                    message: format!(
                        "Failed to activate installed provider '{provider}': {}",
                        DaemonError::from(error)
                    ),
                })?;
            Ok(guest.connection)
        }
    }
}

/// Open, make one call, close. Errors keep the CLI's texts.
pub(crate) async fn call_once<P: Serialize, R: DeserializeOwned>(
    connection: ProviderConnection,
    provider: &str,
    method: &str,
    request: P,
) -> Result<R, CliError> {
    let mut session = open(connection, provider).await?;
    match session.call::<P, R>(method, request).await {
        Ok(result) => {
            close(session, provider).await?;
            Ok(result)
        }
        Err(CallError::Rejected(error)) => {
            let mut message = format!(
                "Provider '{provider}' rejected '{method}': {}",
                DaemonError::from(error)
            );
            if let Err(close) = session.close().await {
                message.push_str(&format!(
                    "; orderly shutdown also failed: {}",
                    failure_text(close)
                ));
            }
            Err(CliError::Extension { message })
        }
        Err(CallError::Failed(error)) => Err(failure(provider, method, error)),
    }
}

/// Open and read what the provider negotiated, then close.
pub(crate) async fn negotiate(
    connection: ProviderConnection,
    provider: &str,
) -> Result<NegotiatedProvider, CliError> {
    let session = open(connection, provider).await?;
    let negotiated = NegotiatedProvider {
        info: session.negotiated().extension().clone(),
        capabilities: session.negotiated().capabilities().clone(),
    };
    close(session, provider).await?;
    Ok(negotiated)
}

fn checked(channel: Box<dyn Channel>, expectation: ExpectedExtension) -> ProviderConnection {
    CheckedConnection::new(JsonRpcConnection::new(
        channel,
        ExpectedChecks::new(expectation),
    ))
}

async fn open(connection: ProviderConnection, provider: &str) -> Result<Session, CliError> {
    Session::open(connection, &crate::commands::extension::host_config())
        .await
        .map_err(|error| failure(provider, "initialize", error))
}

async fn close(session: Session, provider: &str) -> Result<(), CliError> {
    session
        .close()
        .await
        .map_err(|error| failure(provider, "shutdown", error))
}

fn failure(provider: &str, operation: &str, error: HostError) -> CliError {
    CliError::Extension {
        message: format!(
            "Provider '{provider}' failed during {operation}: {}",
            failure_text(error)
        ),
    }
}

/// The text of a failure that ended the session.
///
/// A transport that cannot prove the provider stopped says so, as the
/// daemon's indeterminate session state did.
fn failure_text(error: HostError) -> String {
    let indeterminate = matches!(
        error,
        HostError::Channel {
            state: ChannelState::Indeterminate,
            ..
        }
    );
    let text = DaemonError::from(error).to_string();
    if indeterminate {
        format!("{text}; transport state is indeterminate")
    } else {
        text
    }
}
