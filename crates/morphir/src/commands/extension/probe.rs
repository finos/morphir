//! Probe the verified selected artifact before distribution commits the install.
use morphir_daemon::extensions::process::DescriptionSource;
use morphir_daemon::extensions::{ProcessLaunch, SpawnedProcessTransport};
use morphir_distribution::{
    ArtifactRuntime, DistributionError, InstalledExtension, ProbeSource, StatementProvenance,
    StatementRecord, VerifiedArtifact,
};
use morphir_extension_sdk::protocol::{InitializeParams, SUPPORTED_MEP_VERSIONS};

pub(super) async fn statement(
    artifact: &VerifiedArtifact,
    no_probe: bool,
) -> morphir_distribution::Result<StatementRecord> {
    let selected = artifact.selected().artifact();
    let declared = selected
        .statement()
        .expect("resolved artifact has a statement");
    let record = selected.declared_statement_record();
    if no_probe || selected.runtime() == ArtifactRuntime::Wasm {
        if no_probe {
            eprintln!("Note: extension statement was not probed (--no-probe).");
        } else {
            eprintln!("Note: WASM extension statement was not probed; keeping declared statement.");
        }
        return Ok(record);
    }
    let launch = selected.args().iter().fold(
        ProcessLaunch::new(
            &declared.extension.id,
            artifact.path(),
            artifact
                .path()
                .parent()
                .expect("staged artifact has a directory"),
        ),
        |launch, arg| launch.arg(arg),
    );
    let transport = SpawnedProcessTransport::spawn(launch)
        .await
        .map_err(|error| DistributionError::Probe(error.to_string()))?;
    let description = transport
        .describe(InitializeParams {
            protocol_versions: SUPPORTED_MEP_VERSIONS
                .iter()
                .map(|version| (*version).into())
                .collect(),
            host: super::host_peer(),
        })
        .await
        .map_err(|error| DistributionError::Probe(error.to_string()))?;
    let source = match description.source {
        DescriptionSource::Describe => {
            declared
                .check_statement(&description.statement)
                .map_err(|error| DistributionError::Probe(error.to_string()))?;
            ProbeSource::Describe
        }
        DescriptionSource::SessionFallback => {
            record
                .check_session(
                    &description.statement.protocol_versions[0],
                    &description.statement.extension,
                    &description.statement.capabilities,
                )
                .map_err(|error| DistributionError::Probe(error.to_string()))?;
            ProbeSource::SessionFallback
        }
    };
    Ok(record.probed(source))
}

pub(super) fn print_statement(entry: &InstalledExtension) {
    let provenance = match (entry.statement_provenance(), entry.probe_source()) {
        (StatementProvenance::Declared, _) => "declared",
        (StatementProvenance::Probed, Some(ProbeSource::Describe)) => "probed (describe)",
        (StatementProvenance::Probed, Some(ProbeSource::SessionFallback)) => {
            "probed (session fallback)"
        }
        (StatementProvenance::Probed, None) => "probed",
    };
    let kinds = entry
        .statement()
        .extension
        .types
        .iter()
        .map(|kind| {
            serde_json::to_value(kind)
                .expect("capability kind serializes")
                .as_str()
                .expect("kind is a string")
                .to_owned()
        })
        .collect::<Vec<_>>();
    println!(
        "  Statement: {provenance}; capabilities: {}",
        if kinds.is_empty() {
            "none".into()
        } else {
            kinds.join(", ")
        }
    );
}
