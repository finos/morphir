//! Offering-specific tool ids and authenticated recipe targets in a TEST-ONLY
//! repository that follows the tool release metadata v1 profile.

mod support;

use morphir_distribution::{
    Channel, Selection, Sha256Digest, ToolId, ToolReleaseRecord, TrustedToolRepository,
};
use morphir_toolchain_contract::{
    AuthenticatedTargets, Code, Operation, PlatformId, read_recipe, read_request, resolve_closure,
};
use semver::Version;
use serde_json::Value;
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use support::repository::{self, ARCHIVE_OFFERINGS, KEY_LABEL_PREFIX};

fn signed_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../docs/spec/toolchain/fixtures/0.1.0-draft.1/signed")
}

fn read_json(path: &Path) -> Value {
    let bytes = std::fs::read(path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()));
    serde_json::from_slice(&bytes)
        .unwrap_or_else(|error| panic!("{} is not JSON: {error}", path.display()))
}

fn fixture() -> Value {
    read_json(&signed_dir().join("repository.json"))
}

fn cases() -> Value {
    read_json(&signed_dir().join("cases.json"))
}

fn target_bytes(fixture: &Value, path: &str) -> Vec<u8> {
    fixture["targetFiles"][path]
        .as_str()
        .unwrap_or_else(|| panic!("the fixture publishes no target {path}"))
        .as_bytes()
        .to_vec()
}

fn authenticated(fixture: &Value) -> AuthenticatedTargets {
    AuthenticatedTargets::from_targets_metadata(&fixture["metadata"]["targets"]["signed"])
        .expect("targets metadata")
}

#[test]
fn committed_fixture_is_reproducible_from_its_labels() {
    let generated = repository::fixture();
    let path = signed_dir().join("repository.json");
    if std::env::var("MORPHIR_TOOLCHAIN_FIXTURES").as_deref() == Ok("write") {
        let mut text = serde_json::to_string_pretty(&generated).unwrap();
        text.push('\n');
        std::fs::write(&path, text).unwrap();
    }
    assert_eq!(
        read_json(&path),
        generated,
        "regenerate with MORPHIR_TOOLCHAIN_FIXTURES=write"
    );
}

#[test]
fn every_fixture_key_is_labelled_test_only() {
    let fixture = fixture();
    let listed = fixture["testOnlyKeys"].as_array().unwrap();
    let root_keys = fixture["trustedRoot"]["signed"]["keys"]
        .as_object()
        .unwrap();
    assert_eq!(listed.len(), root_keys.len());
    for key in listed {
        assert!(key["label"].as_str().unwrap().starts_with(KEY_LABEL_PREFIX));
        let tuf_key = &root_keys[key["keyId"].as_str().unwrap()];
        assert_eq!(tuf_key["keyval"]["public"], key["public"]);
    }
    assert!(
        fixture["testOnly"]
            .as_str()
            .unwrap()
            .starts_with("TEST-ONLY.")
    );
    for (path, bytes) in fixture["targetFiles"].as_object().unwrap() {
        let text = bytes.as_str().unwrap();
        if path.starts_with("artifacts/") || path.starts_with("packages/") {
            assert!(text.starts_with("TEST-ONLY synthetic "), "{path}");
        }
    }
}

async fn load(fixture: &Value, root: &Path) -> TrustedToolRepository {
    let metadata = root.join("metadata");
    let targets = root.join("targets");
    std::fs::create_dir_all(&metadata).unwrap();
    std::fs::create_dir_all(&targets).unwrap();
    let canonical = |value: &Value| repository::canonical(value);
    std::fs::write(
        metadata.join("1.root.json"),
        canonical(&fixture["trustedRoot"]),
    )
    .unwrap();
    let set = &fixture["metadata"];
    std::fs::write(
        metadata.join("timestamp.json"),
        canonical(&set["timestamp"]),
    )
    .unwrap();
    let snapshot_version = set["snapshot"]["signed"]["version"].as_u64().unwrap();
    std::fs::write(
        metadata.join(format!("{snapshot_version}.snapshot.json")),
        canonical(&set["snapshot"]),
    )
    .unwrap();
    let targets_version = set["targets"]["signed"]["version"].as_u64().unwrap();
    std::fs::write(
        metadata.join(format!("{targets_version}.targets.json")),
        canonical(&set["targets"]),
    )
    .unwrap();
    let signed_targets = set["targets"]["signed"]["targets"].as_object().unwrap();
    for (name, content) in fixture["targetFiles"].as_object().unwrap() {
        let digest = signed_targets[name]["hashes"]["sha256"].as_str().unwrap();
        let destination = targets.join(format!("{digest}.{name}"));
        std::fs::create_dir_all(destination.parent().unwrap()).unwrap();
        std::fs::write(destination, content.as_str().unwrap()).unwrap();
    }
    TrustedToolRepository::load_filesystem(
        &canonical(&fixture["trustedRoot"]),
        &metadata,
        &targets,
        &root.join("datastore"),
    )
    .await
    .expect("the TUF client authenticates the test-only repository")
}

#[tokio::test]
async fn the_tuf_client_selects_each_offering_by_tool_id_and_platform() {
    let fixture = fixture();
    let directory = tempfile::tempdir().unwrap();
    let client = load(&fixture, directory.path()).await;
    let recipe_bytes = target_bytes(&fixture, "toolchains/recipes/fsharp-builtin/1.0.0.json");
    let recipe = read_recipe(&recipe_bytes).unwrap();
    let cli = Version::parse(cases()["cliVersion"].as_str().unwrap()).unwrap();

    let mut selected = BTreeSet::new();
    for offering in &ARCHIVE_OFFERINGS {
        let host = recipe
            .hosts
            .iter()
            .find(|host| host.deployment.as_str() == offering.deployment)
            .expect("the recipe maps every archive offering");
        for platform in repository::platforms() {
            let resolved = client
                .resolve(
                    &ToolId::parse(offering.tool_id).unwrap(),
                    &Selection::Channel(Channel::Stable),
                    &platform.tool_platform().unwrap(),
                    &cli,
                )
                .await
                .unwrap_or_else(|error| panic!("{} {platform}: {error}", offering.tool_id));
            let binding = &host.platforms[&platform];
            assert_eq!(
                resolved.artifact().target_path().as_str(),
                binding.target.as_str()
            );
            assert_eq!(resolved.digest(), binding.sha256.digest());
            selected.insert((
                resolved.artifact().target_path().as_str().to_owned(),
                resolved.digest().clone(),
            ));
        }
    }
    // Eighteen distinct targets and digests: implementation, deployment and
    // platform are each part of the identity, although every Windows
    // archive's entry point is morphir.exe.
    assert_eq!(selected.len(), 18);
    assert_eq!(
        selected
            .iter()
            .map(|(_, digest)| digest)
            .collect::<BTreeSet<&Sha256Digest>>()
            .len(),
        18
    );
}

#[tokio::test]
async fn the_tuf_client_refuses_substituted_artifacts() {
    let native = "artifacts/morphir-dotnet-native-aot/1.2.3/win-x64.zip";
    // Another deployment's bytes (a different length), and another platform's
    // bytes of exactly the same length, served where the native-aot Windows
    // archive belongs.
    for (substitute, reason) in [
        (
            "artifacts/morphir-dotnet-self-contained/1.2.3/win-x64.zip",
            "Maximum size",
        ),
        (
            "artifacts/morphir-dotnet-native-aot/1.2.3/osx-x64.tar.gz",
            "Hash mismatch",
        ),
    ] {
        let mut fixture = fixture();
        assert_ne!(
            fixture["targetFiles"][native],
            fixture["targetFiles"][substitute]
        );
        fixture["targetFiles"][native] = fixture["targetFiles"][substitute].clone();
        let refused = substituted_download(&fixture).await;
        assert!(refused.contains(reason), "{substitute}: {refused}");
    }
}

async fn substituted_download(fixture: &Value) -> String {
    let directory = tempfile::tempdir().unwrap();
    let client = load(fixture, directory.path()).await;
    let resolved = client
        .resolve(
            &ToolId::parse("morphir-dotnet-native-aot").unwrap(),
            &Selection::Channel(Channel::Stable),
            &PlatformId::parse("win-x64")
                .unwrap()
                .tool_platform()
                .unwrap(),
            &Version::parse("0.4.0").unwrap(),
        )
        .await
        .unwrap();
    let staging = directory.path().join("staging");
    std::fs::create_dir_all(&staging).unwrap();
    let refused = client
        .download(&resolved, &staging)
        .await
        .expect_err("substituted bytes must not verify");
    assert!(
        std::fs::read_dir(&staging).unwrap().next().is_none(),
        "nothing is staged"
    );
    refused.to_string()
}

#[test]
fn offering_releases_are_unchanged_v1_descriptors() {
    let fixture = fixture();
    let schema = read_json(
        &PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../website/static/schemas/tool-release-v1.schema.json"),
    );
    let validator = jsonschema::validator_for(&schema).unwrap();
    let targets = authenticated(&fixture);
    let mut releases = 0;
    for (path, content) in fixture["targetFiles"].as_object().unwrap() {
        if !path.starts_with("releases/") {
            continue;
        }
        releases += 1;
        let bytes = content.as_str().unwrap().as_bytes();
        targets.authenticate(path, bytes).unwrap();
        let record: ToolReleaseRecord = serde_json::from_slice(bytes).unwrap();
        assert_eq!(record.schema_version(), 1, "{path}");
        let value: Value = serde_json::from_slice(bytes).unwrap();
        assert!(
            validator.is_valid(&value),
            "{path} is a plain v1 descriptor"
        );
        let custom = targets.custom(path).unwrap();
        assert_eq!(custom["schemaVersion"], 1);
        assert_eq!(custom["kind"], "tool-release");
    }
    assert_eq!(releases, ARCHIVE_OFFERINGS.len());
}

fn expected_error(expected: &Value) -> Option<(String, String)> {
    expected["code"].as_str().map(|code| {
        (
            code.to_owned(),
            expected["path"].as_str().unwrap_or_default().to_owned(),
        )
    })
}

#[test]
fn selection_distinguishes_implementation_deployment_and_platform() {
    let fixture = fixture();
    let targets = authenticated(&fixture);
    let mut failures = Vec::new();
    for case in cases()["selection"].as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let recipe_path = case["recipe"].as_str().unwrap();
        let recipe_bytes = target_bytes(&fixture, recipe_path);
        targets.authenticate(recipe_path, &recipe_bytes).unwrap();
        let recipe = read_recipe(&recipe_bytes).unwrap();
        let request = read_request(case["request"].as_str().unwrap().as_bytes()).unwrap();
        let platform = PlatformId::parse(case["platform"].as_str().unwrap()).unwrap();
        let expected = &case["expected"];
        match (
            resolve_closure(&recipe, &request, platform),
            expected_error(expected),
        ) {
            (Ok(closure), None) => {
                let host_target = expected["hostTarget"].as_str().unwrap();
                if closure.host.target.as_str() != host_target {
                    failures.push(format!("{name}: selected {}", closure.host.target));
                }
                if Some(&closure.host.sha256) != targets.digest(host_target) {
                    failures.push(format!("{name}: the digest is not the authenticated one"));
                }
                let providers = closure
                    .providers
                    .iter()
                    .map(|provider| {
                        let (operation, member, id) = match &provider.operation {
                            Operation::Compile { language } => ("compile", "language", language),
                            Operation::Generate { target } => ("generate", "target", target),
                        };
                        serde_json::json!({
                            "operation": operation,
                            member: id.as_str(),
                            "delivery": provider.delivery.kind().as_str(),
                            "extensionId": provider.extension_id.as_str()
                        })
                    })
                    .collect::<Vec<_>>();
                if Value::Array(providers.clone()) != expected["providers"] {
                    failures.push(format!("{name}: providers {providers:?}"));
                }
            }
            (Err(diagnostic), Some((code, path))) => {
                if diagnostic.code.as_str() != code || diagnostic.path != path {
                    failures.push(format!("{name}: refused with {diagnostic}"));
                }
            }
            (actual, _) => failures.push(format!("{name}: unexpected {actual:?}")),
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn recipe_bindings_must_name_authenticated_artifacts_of_their_offering() {
    let fixture = fixture();
    let targets = authenticated(&fixture);
    let read = |path: &str| {
        fixture["targetFiles"][path]
            .as_str()
            .map(|text| text.as_bytes().to_vec())
    };
    let mut failures = Vec::new();
    for case in cases()["recipeBindings"].as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let path = case["recipe"].as_str().unwrap();
        let bytes = target_bytes(&fixture, path);
        // Each recipe is validly signed: authentication alone accepts it.
        targets.authenticate(path, &bytes).unwrap();
        let recipe = read_recipe(&bytes).unwrap();
        let actual = targets
            .check_recipe_hosts(&recipe, read)
            .map_err(|diagnostic| (diagnostic.code.as_str().to_owned(), diagnostic.path));
        let expected = match &case["expected"] {
            Value::String(valid) if valid == "valid" => Ok(()),
            expected => Err(expected_error(expected).unwrap()),
        };
        if actual != expected {
            failures.push(format!("{name}: {actual:?}, expected {expected:?}"));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn tampered_recipe_bytes_are_refused() {
    let fixture = fixture();
    let targets = authenticated(&fixture);
    let path = "toolchains/recipes/fsharp-builtin/1.0.0.json";
    let bytes = target_bytes(&fixture, path);

    let mut same_length = bytes.clone();
    let position = same_length
        .windows(5)
        .position(|window| window == b"1.2.3")
        .unwrap();
    same_length[position + 4] = b'4';
    let refused = targets.authenticate(path, &same_length).unwrap_err();
    assert_eq!(refused.code, Code::TargetDigestMismatch);

    let mut longer = bytes;
    longer.push(b' ');
    let refused = targets.authenticate(path, &longer).unwrap_err();
    assert_eq!(refused.code, Code::TargetLengthMismatch);

    let refused = targets
        .authenticate("toolchains/recipes/fsharp/9.9.9.json", b"{}")
        .unwrap_err();
    assert_eq!(refused.code, Code::TargetNotAuthenticated);
}

#[test]
fn moving_channels_select_recipe_targets_by_their_authenticated_state() {
    let fixture = fixture();
    let targets = authenticated(&fixture);
    let preset = |name: &str| morphir_toolchain_contract::PresetId::parse(name).unwrap();
    assert_eq!(
        targets
            .select_recipe(&preset("fsharp-builtin"), &Channel::Stable)
            .unwrap()
            .as_str(),
        "toolchains/recipes/fsharp-builtin/1.0.0.json"
    );
    // A recipe on no channel is reachable only by its exact target.
    let refused = targets
        .select_recipe(&preset("negative-digest-substituted"), &Channel::Stable)
        .unwrap_err();
    assert_eq!(refused.code, Code::UnsupportedArtifact);
}
