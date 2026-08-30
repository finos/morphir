use chrono::{DateTime, Utc};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use morphir_common::home::MorphirHome;
use morphir_distribution::{
    Channel, Platform, Selection, Sha256Digest, ToolId, ToolInstaller, ToolPackageStore,
    ToolRepairer, TrustedToolRepository, activate_installed_tool, list_installed_tools,
};
use semver::{Version, VersionReq};
use serde_json::Value;
use std::collections::BTreeSet;
use std::path::PathBuf;

fn fixture() -> Value {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../docs/spec/tool-release-metadata/fixtures/v1/conformance.json");
    let bytes = std::fs::read(&path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()));
    serde_json::from_slice(&bytes)
        .unwrap_or_else(|error| panic!("failed to parse {}: {error}", path.display()))
}

fn canonical_json(value: &Value) -> Vec<u8> {
    fn write(value: &Value, output: &mut String) {
        match value {
            Value::Null => output.push_str("null"),
            Value::Bool(value) => output.push_str(if *value { "true" } else { "false" }),
            Value::Number(value) => {
                assert!(value.is_i64() || value.is_u64(), "TUF JSON forbids floats");
                output.push_str(&value.to_string());
            }
            Value::String(value) => output.push_str(&serde_json::to_string(value).unwrap()),
            Value::Array(values) => {
                output.push('[');
                for (index, value) in values.iter().enumerate() {
                    if index > 0 {
                        output.push(',');
                    }
                    write(value, output);
                }
                output.push(']');
            }
            Value::Object(values) => {
                output.push('{');
                let mut keys = values.keys().collect::<Vec<_>>();
                keys.sort_unstable();
                for (index, key) in keys.iter().enumerate() {
                    if index > 0 {
                        output.push(',');
                    }
                    output.push_str(&serde_json::to_string(key).unwrap());
                    output.push(':');
                    write(&values[*key], output);
                }
                output.push('}');
            }
        }
    }

    let mut output = String::new();
    write(value, &mut output);
    output.into_bytes()
}

fn decode_hex<const N: usize>(value: &str) -> [u8; N] {
    assert_eq!(value.len(), N * 2, "unexpected hex length");
    std::array::from_fn(|index| {
        u8::from_str_radix(&value[index * 2..index * 2 + 2], 16).expect("valid hex")
    })
}

fn threshold_is_met(root: &Value, envelope: &Value, role: &str) -> bool {
    let role = &root["signed"]["roles"][role];
    let threshold = role["threshold"].as_u64().expect("role threshold") as usize;
    let trusted = role["keyids"]
        .as_array()
        .expect("role key ids")
        .iter()
        .map(|value| value.as_str().expect("key id"))
        .collect::<BTreeSet<_>>();
    let message = canonical_json(&envelope["signed"]);
    let mut verified = BTreeSet::new();

    for signature in envelope["signatures"].as_array().expect("signatures") {
        let key_id = signature["keyid"].as_str().expect("signature key id");
        if !trusted.contains(key_id) || verified.contains(key_id) {
            continue;
        }
        let public = root["signed"]["keys"][key_id]["keyval"]["public"]
            .as_str()
            .expect("Ed25519 public key");
        let key = VerifyingKey::from_bytes(&decode_hex::<32>(public)).expect("valid public key");
        let signature = Signature::from_slice(&decode_hex::<64>(
            signature["sig"].as_str().expect("signature bytes"),
        ))
        .expect("valid signature encoding");
        if key.verify(&message, &signature).is_ok() {
            verified.insert(key_id);
        }
    }

    verified.len() >= threshold
}

fn assert_fresh(envelope: &Value, reference_time: DateTime<Utc>) {
    let expires = envelope["signed"]["expires"]
        .as_str()
        .expect("metadata expiry")
        .parse::<DateTime<Utc>>()
        .expect("RFC 3339 expiry");
    assert!(expires > reference_time, "metadata unexpectedly expired");
}

fn assert_tuf_profile(envelope: &Value, expected_role: &str) {
    assert_eq!(envelope["signed"]["_type"], expected_role);
    let specification = Version::parse(
        envelope["signed"]["spec_version"]
            .as_str()
            .expect("TUF specification version"),
    )
    .expect("semantic TUF specification version");
    assert_eq!((specification.major, specification.minor), (1, 0));
    canonical_json(envelope);
}

fn assert_metadata_link(parent: &Value, name: &str, child: &Value) {
    let expected = &parent["signed"]["meta"][name];
    let bytes = canonical_json(child);
    assert_eq!(expected["length"].as_u64().unwrap(), bytes.len() as u64);
    assert_eq!(
        expected["hashes"]["sha256"].as_str().unwrap(),
        Sha256Digest::of_bytes(&bytes).to_string()
    );
    assert_eq!(
        expected["version"].as_u64().unwrap(),
        child["signed"]["version"].as_u64().unwrap()
    );
}

fn release_records(targets: &Value) -> Vec<&Value> {
    targets["signed"]["targets"]
        .as_object()
        .expect("targets map")
        .values()
        .filter(|target| target["custom"]["morphir"]["kind"] == "tool-release")
        .collect()
}

fn assert_release_descriptors_match_targets(fixture: &Value, targets: &Value) {
    let files = fixture["targetFiles"].as_object().expect("target files");
    let trusted_targets = targets["signed"]["targets"]
        .as_object()
        .expect("trusted targets");
    assert_eq!(
        files.keys().collect::<BTreeSet<_>>(),
        trusted_targets.keys().collect::<BTreeSet<_>>(),
        "every trusted target should have exactly one fixture payload"
    );

    for (path, trusted) in trusted_targets {
        let custom = &trusted["custom"]["morphir"];
        if custom["kind"] != "tool-release" {
            continue;
        }
        let descriptor: Value = serde_json::from_str(files[path].as_str().unwrap()).unwrap();
        let tool_id = custom["toolId"].as_str().unwrap();
        let version = custom["version"].as_str().unwrap();
        assert_eq!(path, &format!("releases/{tool_id}/{version}.json"));
        assert_eq!(descriptor["schemaVersion"], custom["schemaVersion"]);
        assert_eq!(descriptor["tool"]["id"], custom["toolId"]);
        assert_eq!(descriptor["version"], custom["version"]);
        assert_eq!(descriptor["channels"], custom["channels"]);
        assert_eq!(descriptor["status"], custom["status"]);
        assert_eq!(descriptor["compatibility"], custom["compatibility"]);

        let declared_platforms = descriptor["artifacts"]
            .as_array()
            .unwrap()
            .iter()
            .map(|artifact| {
                format!(
                    "{}-{}",
                    artifact["platform"]["os"].as_str().unwrap(),
                    artifact["platform"]["arch"].as_str().unwrap()
                )
            })
            .collect::<BTreeSet<_>>();
        let indexed_platforms = custom["platforms"]
            .as_array()
            .unwrap()
            .iter()
            .map(|platform| {
                format!(
                    "{}-{}",
                    platform["os"].as_str().unwrap(),
                    platform["arch"].as_str().unwrap()
                )
            })
            .collect::<BTreeSet<_>>();
        assert_eq!(declared_platforms, indexed_platforms);

        for artifact in descriptor["artifacts"].as_array().unwrap() {
            let target_path = artifact["targetPath"].as_str().unwrap();
            let artifact_custom = &trusted_targets[target_path]["custom"]["morphir"];
            assert_eq!(artifact_custom["kind"], "tool-artifact");
            assert_eq!(artifact_custom["toolId"], tool_id);
            assert_eq!(artifact_custom["version"], version);
            assert_eq!(artifact_custom["platform"], artifact["platform"]);
            assert_eq!(
                artifact["launch"]["path"],
                artifact["archive"]["entryPoint"]
            );
        }
    }
}

fn supports_platform(record: &Value, os: &str, arch: &str) -> bool {
    record["custom"]["morphir"]["platforms"]
        .as_array()
        .expect("platform list")
        .iter()
        .any(|platform| platform["os"] == os && platform["arch"] == arch)
}

fn channel_matches(channel: &str, version: &Version, channels: &[Value]) -> bool {
    match channel {
        "stable" => version.pre.is_empty() && channels.iter().any(|value| value == "stable"),
        "preview" | "insiders" => channels.iter().any(|value| {
            value.as_str().is_some_and(|value| {
                value == "preview" || value == "insiders" || value.starts_with("preview/")
            })
        }),
        segmented if segmented.starts_with("preview/") => {
            channels.iter().any(|value| value == segmented)
        }
        _ => false,
    }
}

fn resolve(targets: &Value, case: &Value) -> Result<Version, &'static str> {
    let tool_id = case["toolId"].as_str().expect("tool id");
    let os = case["platform"]["os"].as_str().expect("platform os");
    let arch = case["platform"]["arch"].as_str().expect("platform arch");
    let cli = Version::parse(case["cliVersion"].as_str().expect("CLI version")).unwrap();
    let selection = &case["selection"];
    let exact = selection["version"]
        .as_str()
        .map(Version::parse)
        .transpose()
        .unwrap();
    let channel = selection["channel"].as_str();
    let mut candidates = Vec::new();

    for target in release_records(targets) {
        let metadata = &target["custom"]["morphir"];
        if metadata["toolId"] != tool_id {
            continue;
        }
        let version = Version::parse(metadata["version"].as_str().unwrap()).unwrap();
        if exact
            .as_ref()
            .is_some_and(|requested| requested != &version)
        {
            continue;
        }
        if metadata["status"] == "revoked" {
            if exact.as_ref() == Some(&version) {
                return Err("release_revoked");
            }
            continue;
        }
        if metadata["status"] == "yanked" && exact.is_none() {
            continue;
        }
        if !supports_platform(target, os, arch) {
            continue;
        }
        if exact.is_none()
            && !channel_matches(
                channel.expect("channel selection"),
                &version,
                metadata["channels"].as_array().unwrap(),
            )
        {
            continue;
        }
        let requirement = VersionReq::parse(
            metadata["compatibility"]["morphirCli"]
                .as_str()
                .expect("CLI requirement"),
        )
        .unwrap();
        if requirement.matches(&cli) {
            candidates.push(version);
        }
    }

    candidates.into_iter().max().ok_or("no_compatible_release")
}

#[test]
fn reference_resolver_excludes_yanked_releases_from_moving_channels() {
    let fixture = fixture();
    let mut targets = fixture["metadata"]["targets"].clone();
    targets["signed"]["targets"]["releases/desktop/1.0.0.json"]["custom"]["morphir"]["status"] =
        Value::from("yanked");
    let moving = serde_json::json!({
        "toolId": "desktop",
        "selection": { "channel": "stable" },
        "cliVersion": "0.4.0",
        "platform": { "os": "windows", "arch": "x86_64" }
    });
    let exact = serde_json::json!({
        "toolId": "desktop",
        "selection": { "version": "1.0.0" },
        "cliVersion": "0.4.0",
        "platform": { "os": "windows", "arch": "x86_64" }
    });

    assert_eq!(resolve(&targets, &moving), Err("no_compatible_release"));
    assert_eq!(resolve(&targets, &exact).unwrap(), Version::new(1, 0, 0));
}

#[test]
fn reference_resolver_accepts_metadata_published_as_insiders() {
    let fixture = fixture();
    let mut targets = fixture["metadata"]["targets"].clone();
    targets["signed"]["targets"]["releases/desktop/1.1.0-preview.1.json"]["custom"]["morphir"]["channels"] =
        serde_json::json!(["insiders"]);

    for channel in ["preview", "insiders"] {
        let case = serde_json::json!({
            "toolId": "desktop",
            "selection": { "channel": channel },
            "cliVersion": "0.4.0",
            "platform": { "os": "windows", "arch": "x86_64" }
        });
        assert_eq!(
            resolve(&targets, &case).unwrap(),
            Version::parse("1.1.0-preview.1").unwrap()
        );
    }
}

#[test]
fn signed_tool_metadata_fixture_is_authenticated_and_deterministic() {
    let fixture = fixture();
    assert_eq!(fixture["contractVersion"], 1);
    let reference_time = fixture["referenceTime"]
        .as_str()
        .unwrap()
        .parse::<DateTime<Utc>>()
        .unwrap();
    let runtime_test_horizon = "2100-01-01T00:00:00Z".parse::<DateTime<Utc>>().unwrap();

    let trusted_root = &fixture["trustedRoot"];
    assert_tuf_profile(trusted_root, "root");
    assert_eq!(trusted_root["signed"]["consistent_snapshot"], true);
    assert!(
        trusted_root["signed"]["roles"]["root"]["threshold"]
            .as_u64()
            .unwrap()
            >= 2
    );
    for key in trusted_root["signed"]["keys"].as_object().unwrap().values() {
        assert_eq!(key["keytype"], "ed25519");
        assert_eq!(key["scheme"], "ed25519");
    }
    assert!(threshold_is_met(trusted_root, trusted_root, "root"));
    let mut current_root = trusted_root;
    for update in fixture["rootUpdates"].as_array().unwrap() {
        assert_tuf_profile(update, "root");
        assert_eq!(update["signed"]["consistent_snapshot"], true);
        assert_eq!(
            update["signed"]["version"].as_u64().unwrap(),
            current_root["signed"]["version"].as_u64().unwrap() + 1
        );
        assert!(threshold_is_met(current_root, update, "root"));
        assert!(threshold_is_met(update, update, "root"));
        current_root = update;
    }
    assert_fresh(current_root, reference_time);
    assert_fresh(current_root, runtime_test_horizon);

    let timestamp = &fixture["metadata"]["timestamp"];
    let snapshot = &fixture["metadata"]["snapshot"];
    let targets = &fixture["metadata"]["targets"];
    for (role, envelope) in [
        ("timestamp", timestamp),
        ("snapshot", snapshot),
        ("targets", targets),
    ] {
        assert_tuf_profile(envelope, role);
        assert!(threshold_is_met(current_root, envelope, role));
        assert_fresh(envelope, reference_time);
        assert_fresh(envelope, runtime_test_horizon);
    }
    assert_metadata_link(timestamp, "snapshot.json", snapshot);
    assert_metadata_link(snapshot, "targets.json", targets);

    for (path, content) in fixture["targetFiles"].as_object().unwrap() {
        let trusted = &targets["signed"]["targets"][path];
        let bytes = content.as_str().expect("UTF-8 fixture target").as_bytes();
        assert_eq!(trusted["length"].as_u64().unwrap(), bytes.len() as u64);
        assert_eq!(
            trusted["hashes"]["sha256"].as_str().unwrap(),
            Sha256Digest::of_bytes(bytes).to_string()
        );
    }
    assert_release_descriptors_match_targets(&fixture, targets);

    for case in fixture["resolutionCases"].as_array().unwrap() {
        match &case["expected"] {
            Value::String(expected) => {
                assert_eq!(resolve(targets, case).unwrap().to_string(), *expected)
            }
            expected => assert_eq!(resolve(targets, case).unwrap_err(), expected["diagnostic"]),
        }
    }

    let mut tampered = targets.clone();
    tampered["signed"]["targets"]
        .as_object_mut()
        .unwrap()
        .values_mut()
        .next()
        .unwrap()["length"] = Value::from(1);
    assert!(!threshold_is_met(current_root, &tampered, "targets"));

    let expired = &fixture["rejectionMetadata"]["expiredTimestamp"];
    assert!(threshold_is_met(current_root, expired, "timestamp"));
    let expires = expired["signed"]["expires"]
        .as_str()
        .unwrap()
        .parse::<DateTime<Utc>>()
        .unwrap();
    assert!(expires <= reference_time);

    let repository_id =
        Sha256Digest::of_bytes(&canonical_json(&trusted_root["signed"])).to_string();
    assert_eq!(fixture["repositoryId"], repository_id);
    assert!(fixture["mirrors"].as_array().unwrap().len() >= 2);
}

#[tokio::test]
async fn signed_fixture_drives_the_runtime_tuf_client_and_verified_download() {
    let fixture = fixture();
    let repository_root = tempfile::tempdir().unwrap();
    let metadata = repository_root.path().join("metadata");
    let targets = repository_root.path().join("targets");
    let datastore = repository_root.path().join("datastore");
    let downloads = repository_root.path().join("downloads");
    let repair_downloads = repository_root.path().join("repair-downloads");
    std::fs::create_dir_all(&metadata).unwrap();
    std::fs::create_dir_all(&targets).unwrap();
    std::fs::create_dir_all(&datastore).unwrap();
    std::fs::create_dir_all(&downloads).unwrap();
    std::fs::create_dir_all(&repair_downloads).unwrap();

    write_canonical_json(&metadata.join("1.root.json"), &fixture["trustedRoot"]);
    for root in fixture["rootUpdates"].as_array().unwrap() {
        let version = root["signed"]["version"].as_u64().unwrap();
        write_canonical_json(&metadata.join(format!("{version}.root.json")), root);
    }
    write_canonical_json(
        &metadata.join("timestamp.json"),
        &fixture["metadata"]["timestamp"],
    );
    let snapshot_version = fixture["metadata"]["snapshot"]["signed"]["version"]
        .as_u64()
        .unwrap();
    write_canonical_json(
        &metadata.join(format!("{snapshot_version}.snapshot.json")),
        &fixture["metadata"]["snapshot"],
    );
    let targets_version = fixture["metadata"]["targets"]["signed"]["version"]
        .as_u64()
        .unwrap();
    write_canonical_json(
        &metadata.join(format!("{targets_version}.targets.json")),
        &fixture["metadata"]["targets"],
    );
    write_consistent_targets(&fixture, &targets);

    let trusted_root = canonical_json(&fixture["trustedRoot"]);
    let repository =
        TrustedToolRepository::load_filesystem(&trusted_root, &metadata, &targets, &datastore)
            .await
            .unwrap();
    let tool_id = ToolId::parse("desktop").unwrap();
    let platform = Platform::new("windows", "x86_64").unwrap();
    let cli_version = Version::parse("0.4.0").unwrap();
    let resolved = repository
        .resolve(
            &tool_id,
            &Selection::Channel(Channel::Stable),
            &platform,
            &cli_version,
        )
        .await
        .unwrap();

    assert_eq!(resolved.release().version().to_string(), "1.0.0");
    assert_eq!(
        resolved.artifact().target_path().as_str(),
        "artifacts/desktop/1.0.0/windows-x86_64.zip"
    );
    let downloaded = repository.download(&resolved, &downloads).await.unwrap();
    let bytes = std::fs::read(downloaded.path()).unwrap();
    assert_eq!(Sha256Digest::of_bytes(&bytes), *resolved.digest());
    assert_eq!(bytes.len() as u64, resolved.length());
    let repair_resolved = repository
        .resolve(
            &tool_id,
            &Selection::Exact(Version::parse("1.0.0").unwrap()),
            &platform,
            &cli_version,
        )
        .await
        .unwrap();
    let repair_downloaded = repository
        .download(&repair_resolved, &repair_downloads)
        .await
        .unwrap();

    let home_path = repository_root.path().join("home");
    let home = MorphirHome::resolve_from(Some(home_path.as_os_str()), None).unwrap();
    let package = ToolPackageStore::new(&home)
        .prepare(resolved, downloaded)
        .unwrap();
    let installed = ToolInstaller::new(&home).install(package).unwrap();
    assert_eq!(installed.version(), &Version::parse("1.0.0").unwrap());
    let initial_launch = activate_installed_tool(&home, &tool_id).unwrap();
    std::fs::write(initial_launch.program(), b"corrupt").unwrap();
    drop(initial_launch);
    ToolRepairer::new(&home)
        .repair(&tool_id, repair_resolved, repair_downloaded)
        .unwrap();
    assert_eq!(
        list_installed_tools(&home).unwrap()[0].selection(),
        &Selection::Channel(Channel::Stable)
    );

    drop(repository);
    std::fs::remove_dir_all(&metadata).unwrap();
    std::fs::remove_dir_all(&targets).unwrap();
    std::fs::remove_dir_all(&downloads).unwrap();
    std::fs::remove_dir_all(&repair_downloads).unwrap();
    let launch = activate_installed_tool(&home, &tool_id).unwrap();
    assert!(
        std::fs::read(launch.program())
            .unwrap()
            .starts_with(b"fixture signed desktop executable ")
    );
}

fn write_canonical_json(path: &std::path::Path, value: &Value) {
    std::fs::write(path, canonical_json(value)).unwrap();
}

fn write_consistent_targets(fixture: &Value, targets_root: &std::path::Path) {
    let trusted = fixture["metadata"]["targets"]["signed"]["targets"]
        .as_object()
        .unwrap();
    for (target_name, content) in fixture["targetFiles"].as_object().unwrap() {
        let digest = trusted[target_name]["hashes"]["sha256"].as_str().unwrap();
        let destination = targets_root.join(format!("{digest}.{target_name}"));
        std::fs::create_dir_all(destination.parent().unwrap()).unwrap();
        std::fs::write(destination, content.as_str().unwrap().as_bytes()).unwrap();
    }
}
