//! Version-2 process bundles assembled from executable release assets.
use morphir_daemon::extensions::{
    ProcessLaunch, SpawnedProcessTransport, process::DescriptionSource,
};
use morphir_distribution::Sha256Digest;
use morphir_extension_sdk::protocol::{InitializeParams, MEP_VERSION, PeerInfo, PeerKind};
use serde_json::{Value, json};
use std::{
    fs,
    path::{Path, PathBuf},
};

pub fn host_triple() -> String {
    let suffix = match std::env::consts::OS {
        "macos" => "apple-darwin",
        "linux" => "unknown-linux-gnu",
        other => panic!("unsupported test host {other}"),
    };
    format!("{}-{suffix}", std::env::consts::ARCH)
}

pub fn write_bundle(
    root: &Path,
    declared: Value,
    short_id: &str,
    artifacts: &[(&str, &str, &[u8])],
) -> PathBuf {
    let bundle = root.join("bundle");
    fs::create_dir_all(&bundle).unwrap();
    let artifacts: Vec<_> = artifacts.iter().map(|(platform, filename, bytes)| {
        let digest = Sha256Digest::of_bytes(bytes);
        fs::write(bundle.join(filename), bytes).unwrap();
        fs::write(bundle.join(format!("{filename}.sha256")), format!("{digest}  {filename}\n")).unwrap();
        json!({"platform": platform, "runtime": "process", "filename": filename, "sha256": digest, "statement": declared})
    }).collect();
    fs::write(bundle.join("release.json"), serde_json::to_vec(&json!({
        "schemaVersion": "2.0.0-draft.1", "extensionId": declared["extension"]["id"], "shortId": short_id,
        "version": declared["extension"]["version"], "platformDifferences": "none", "artifacts": artifacts
    })).unwrap()).unwrap();
    bundle
}

/// Released process assets have no descriptor yet. Read their session metadata
/// to declare a host-platform bundle, then let CLI publish and install probe it again.
pub fn from_executable(
    scratch: &Path,
    executable: &Path,
    id: &str,
    short_id: &str,
    version: &str,
) -> PathBuf {
    fs::create_dir_all(scratch).unwrap();
    let stage = tempfile::tempdir_in(scratch).unwrap();
    let staged_executable = stage.path().join("host-extension");
    fs::copy(executable, &staged_executable).unwrap();
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let description = runtime.block_on(async {
        SpawnedProcessTransport::spawn(ProcessLaunch::new(id, &staged_executable, stage.path()))
            .await
            .unwrap()
            .describe(InitializeParams {
                protocol_versions: vec![MEP_VERSION.into()],
                host: PeerInfo {
                    kind: PeerKind::Cli,
                    name: "morphir-cli".into(),
                    version: env!("CARGO_PKG_VERSION").into(),
                },
            })
            .await
            .unwrap()
    });
    assert_eq!(description.source, DescriptionSource::SessionFallback);
    assert_eq!(description.statement.extension.id, id);
    assert_eq!(description.statement.extension.version, version);
    write_bundle(
        scratch,
        serde_json::to_value(description.statement).unwrap(),
        short_id,
        &[(
            &host_triple(),
            "host-extension",
            &fs::read(executable).unwrap(),
        )],
    )
}
