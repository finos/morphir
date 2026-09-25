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
use async_trait::async_trait;
use morphir_daemon::DaemonError;
use morphir_extension_sdk::{ExtensionCapabilities, ExtensionInfo};
use morphir_host::{
    CallError, CapabilityMetadataScope, Channel, ChannelState, ExpectedChecks, ExpectedExtension,
    GuestConnection, GuestSource, HostError, InvocationMode, InvocationPolicy, JsonRpcConnection,
    ProviderOrigin, Resolved, Session,
};
use morphir_host_native::process::{ProcessChannel, ProcessLaunch};
use morphir_host_native::{CheckedConnection, InstalledSource, InstalledSourceError};
use serde::{Serialize, de::DeserializeOwned};
use std::path::Path;

/// A checked MEP connection to one provider, ready to open.
pub(crate) type ProviderConnection =
    CheckedConnection<JsonRpcConnection<Box<dyn Channel>, ExpectedChecks>>;

/// An installed provider whose failure to start reads as the CLI reported it.
///
/// It is an [`InstalledSource`] in every respect but one. The host's own
/// [`GuestSource::connect`] for an installed source prints an activation
/// failure as the bare `HostError`. The CLI has always printed it through
/// `DaemonError`, so a provider message keeps its `Extension error: `
/// prefix. This source starts the guest with [`InstalledSource::activate`]
/// and words the typed failure itself.
///
/// The registry resolves to a [`Resolved`] that does not lend its source
/// back, so the texts have to be settled here, when the guest starts, and
/// not by the caller afterwards. A failure is a [`HostError::Invalid`]
/// holding the whole CLI message; [`connect`] reports it unchanged.
pub(crate) struct InstalledProvider(InstalledSource);

impl InstalledProvider {
    pub(crate) fn new(source: InstalledSource) -> Self {
        Self(source)
    }
}

#[async_trait]
impl GuestSource for InstalledProvider {
    fn info(&self) -> &ExtensionInfo {
        self.0.info()
    }

    fn capabilities(&self) -> &ExtensionCapabilities {
        self.0.capabilities()
    }

    fn origin(&self) -> ProviderOrigin {
        self.0.origin()
    }

    fn capability_metadata_scope(&self) -> CapabilityMetadataScope {
        self.0.capability_metadata_scope()
    }

    fn invocation_mode(&self, policy: InvocationPolicy) -> InvocationMode {
        self.0.invocation_mode(policy)
    }

    fn incarnation(&self) -> Option<&str> {
        self.0.incarnation()
    }

    async fn connect(&self, workspace: &Path) -> Result<Box<dyn GuestConnection>, HostError> {
        match self.0.activate(workspace).await {
            Ok(guest) => Ok(Box::new(guest.connection)),
            Err(error) => Err(HostError::Invalid(installed_failure_text(error))),
        }
    }
}

/// The text the CLI reports when an installed provider does not start.
fn installed_failure_text(error: InstalledSourceError) -> String {
    match error {
        InstalledSourceError::Activate { id, error } => format!(
            "Failed to activate installed provider '{id}': {}",
            DaemonError::from(*error)
        ),
        // Verification texts are already the CLI's.
        other => other.to_string(),
    }
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

/// Start the guest a registry resolved, ready to open.
///
/// A built-in connects in process and cannot fail here. An installed
/// provider is an [`InstalledProvider`], whose failure already holds the
/// CLI's whole message.
pub(crate) async fn connect(
    resolved: &Resolved,
    workspace: &Path,
) -> Result<Box<dyn GuestConnection>, CliError> {
    resolved
        .connect(workspace)
        .await
        .map_err(|error| CliError::Extension {
            message: error.to_string(),
        })
}

/// Open, make one call, close. Errors keep the CLI's texts.
pub(crate) async fn call_once<G, P, R>(
    connection: G,
    provider: &str,
    method: &str,
    request: P,
) -> Result<R, CliError>
where
    G: GuestConnection + 'static,
    P: Serialize,
    R: DeserializeOwned,
{
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
        Err(CallError::Failed(error) | CallError::Open(error)) => {
            Err(failure(provider, method, error))
        }
        Err(other) => Err(CliError::Extension {
            message: format!("Provider '{provider}' failed during {method}: {other}"),
        }),
    }
}

/// Open and read what the provider negotiated, then close.
pub(crate) async fn negotiate<G: GuestConnection + 'static>(
    connection: G,
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

async fn open<G: GuestConnection + 'static>(
    connection: G,
    provider: &str,
) -> Result<Session, CliError> {
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
