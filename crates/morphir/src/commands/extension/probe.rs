//! Probe the verified selected artifact before distribution commits the install.
use morphir_daemon::extensions::process::DescriptionSource;
use morphir_daemon::extensions::{ProcessLaunch, SpawnedProcessTransport};
use morphir_distribution::{
    ArtifactRuntime, ClaimCheck, ClaimsRecord, DistributionError, InstalledExtension, ProbeSource,
    VerifiedArtifact,
};
pub(super) async fn claims(
    artifact: &VerifiedArtifact,
    no_probe: bool,
) -> morphir_distribution::Result<ClaimsRecord> {
    let selected = artifact.selected().artifact();
    let declared = selected
        .claims()
        .expect("resolved artifact has a claim set");
    let record = selected.declared_claims_record();
    if no_probe || selected.runtime() == ArtifactRuntime::Wasm {
        if no_probe {
            eprintln!("Note: extension claims were not checked (--no-probe).");
        } else {
            eprintln!("Note: WASM extension claims were not checked; keeping them unchecked.");
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
        .describe(super::host_config().initialize_params())
        .await
        .map_err(|error| DistributionError::Probe(error.to_string()))?;
    let source = match description.source {
        DescriptionSource::Describe => {
            declared
                .check_claims(&description.claims)
                .map_err(|error| DistributionError::Probe(error.to_string()))?;
            ProbeSource::Describe
        }
        DescriptionSource::SessionFallback => {
            record
                .check_session(
                    &description.claims.protocol_versions[0],
                    &description.claims.extension,
                    &description.claims.capabilities,
                )
                .map_err(|error| DistributionError::Probe(error.to_string()))?;
            ProbeSource::SessionFallback
        }
    };
    Ok(record.probed(source))
}

pub(super) fn print_claims(entry: &InstalledExtension) {
    let check = match (entry.claim_check(), entry.probe_source()) {
        (ClaimCheck::Unchecked, _) => "unchecked",
        (ClaimCheck::Probed, Some(ProbeSource::Describe)) => "probed (describe)",
        (ClaimCheck::Probed, Some(ProbeSource::SessionFallback)) => "probed (session fallback)",
        (ClaimCheck::Probed, None) => "probed",
    };
    let kinds = entry
        .claims()
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
        "  Claims: {check}; capabilities: {}",
        if kinds.is_empty() {
            "none".into()
        } else {
            kinds.join(", ")
        }
    );
}
