//! The TEST-ONLY signed F# recipe: exact host, frontend and backend bindings,
//! frozen closures for the six first-delivery platforms, and the trust cases
//! the existing TUF client enforces.

mod support;

use morphir_distribution::{Channel, ReleaseBundleDescriptor, Selection, ToolId, ToolProvenance};
use morphir_toolchain_contract::{
    AuthenticatedTargets, Authentication, ClaimCheck, Code, LockedDelivery, PlatformId,
    ProbeSource, read_lock, read_receipt, read_recipe, read_request, resolve_closure,
};
use semver::Version;
use serde_json::{Value, json};
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use support::repository::{self, FROZEN};

const RECIPE: &str = "toolchains/recipes/fsharp/1.0.0.json";

fn fixtures() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../docs/spec/toolchain/fixtures/0.1.0-draft.1")
}

fn read_json(path: &Path) -> Value {
    let bytes = std::fs::read(path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()));
    serde_json::from_slice(&bytes)
        .unwrap_or_else(|error| panic!("{} is not JSON: {error}", path.display()))
}

fn fixture() -> Value {
    read_json(&fixtures().join("signed/repository.json"))
}

fn targets_of(set: &Value) -> AuthenticatedTargets {
    AuthenticatedTargets::from_targets_metadata(&set["targets"]["signed"]).unwrap()
}

fn reader(fixture: &Value) -> impl Fn(&str) -> Option<Vec<u8>> + '_ {
    |path| {
        fixture["targetFiles"][path]
            .as_str()
            .map(|text| text.as_bytes().to_vec())
    }
}

fn recipe_bytes(fixture: &Value, path: &str) -> Vec<u8> {
    reader(fixture)(path).unwrap_or_else(|| panic!("no target {path}"))
}

#[test]
fn frozen_requests_and_locks_are_reproducible() {
    let targets = repository::published();
    let write = std::env::var("MORPHIR_TOOLCHAIN_FIXTURES").as_deref() == Ok("write");
    for (name, request, lock) in repository::frozen_locks(&targets) {
        let request_path = fixtures().join(format!("signed/{name}.toml"));
        let lock_path = fixtures().join(format!("signed/{name}.lock.json"));
        if write {
            std::fs::write(&request_path, &request).unwrap();
            let mut text = serde_json::to_string_pretty(&lock).unwrap();
            text.push('\n');
            std::fs::write(&lock_path, text).unwrap();
        }
        assert_eq!(
            std::fs::read_to_string(&request_path).unwrap(),
            request,
            "{name}"
        );
        assert_eq!(read_json(&lock_path), lock, "{name}");
    }
}

#[test]
fn the_fsharp_recipe_binds_authenticated_descriptors_and_artifacts() {
    let fixture = fixture();
    let targets = targets_of(&fixture["metadata"]);
    let recipe = targets
        .check_recipe(RECIPE, &recipe_bytes(&fixture, RECIPE), reader(&fixture))
        .unwrap();
    assert_eq!(recipe.hosts.len(), 4);
    assert_eq!(
        targets
            .select_recipe(&recipe.preset, &Channel::Stable)
            .unwrap()
            .as_str(),
        RECIPE
    );
    for descriptor in [
        "extensions/fsharp-frontend/0.6.0/release.json",
        "extensions/fsharp-backend/0.1.0/release.json",
    ] {
        // The existing extension descriptor reader accepts the bytes unchanged.
        let parsed =
            ReleaseBundleDescriptor::parse_json(&recipe_bytes(&fixture, descriptor)).unwrap();
        assert_eq!(parsed.schema_version().to_string(), "2.0.0-draft.2");
        assert_eq!(parsed.artifacts().len(), 6);
        // Bundle authoring leaves claims unchecked. The recipe authenticates
        // the bytes; it does not turn the claim check into `probed`.
        assert!(
            parsed
                .artifacts()
                .iter()
                .all(
                    |artifact| serde_json::to_value(artifact.claim_check()).unwrap() == "unchecked"
                )
        );
    }
}

#[test]
fn provider_binding_cases() {
    let fixture = fixture();
    let targets = targets_of(&fixture["metadata"]);
    let cases = read_json(&fixtures().join("signed/cases.json"));
    let mut failures = Vec::new();
    for case in cases["providerBindings"].as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let path = case["recipe"].as_str().unwrap();
        let actual = targets
            .check_recipe(path, &recipe_bytes(&fixture, path), reader(&fixture))
            .map(drop)
            .map_err(|refusal| (refusal.code.as_str().to_owned(), refusal.path));
        let expected = match &case["expected"] {
            Value::String(valid) if valid == "valid" => Ok(()),
            refusal => Err((
                refusal["code"].as_str().unwrap().to_owned(),
                refusal["path"].as_str().unwrap().to_owned(),
            )),
        };
        if actual != expected {
            failures.push(format!("{name}: {actual:?}, expected {expected:?}"));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn frozen_closures_are_complete_on_all_six_platforms() {
    let fixture = fixture();
    let targets = targets_of(&fixture["metadata"]);
    let recipe = read_recipe(&recipe_bytes(&fixture, RECIPE)).unwrap();
    let six = PlatformId::FIRST_DELIVERY
        .iter()
        .map(|name| PlatformId::parse(name).unwrap())
        .collect::<BTreeSet<_>>();
    for (name, _) in FROZEN {
        let request_bytes = std::fs::read(fixtures().join(format!("signed/{name}.toml"))).unwrap();
        let lock_bytes =
            std::fs::read(fixtures().join(format!("signed/{name}.lock.json"))).unwrap();
        let request = read_request(&request_bytes).unwrap();
        let lock = read_lock(&lock_bytes).unwrap();
        lock.check_request(&request).unwrap();
        assert_eq!(lock.recipe.target.as_str(), RECIPE);
        assert_eq!(
            Some(&lock.recipe.sha256),
            targets.digest(RECIPE),
            "{name} binds the authenticated recipe"
        );
        assert_eq!(
            lock.recipe.repository_id.to_string(),
            fixture["repositoryId"]
        );
        assert_eq!(
            lock.platforms.keys().copied().collect::<BTreeSet<_>>(),
            six,
            "{name}"
        );
        for (platform, closure) in &lock.platforms {
            assert_eq!(
                &resolve_closure(&recipe, &request, *platform).unwrap(),
                closure,
                "{name} {platform} is the resolution of its request"
            );
            let mut bound = vec![(&closure.host.target, &closure.host.sha256)];
            for provider in &closure.providers {
                match &provider.delivery {
                    LockedDelivery::BuiltIn { .. } => {}
                    LockedDelivery::Process {
                        descriptor,
                        artifact,
                        ..
                    }
                    | LockedDelivery::Wasm {
                        descriptor,
                        artifact,
                        ..
                    } => {
                        bound.push((&descriptor.target, &descriptor.sha256));
                        bound.push((&artifact.target, &artifact.sha256));
                    }
                    LockedDelivery::DotnetTool { package, .. } => {
                        bound.push((&package.target, &package.sha256))
                    }
                }
            }
            for (target, sha256) in bound {
                assert_eq!(
                    targets.digest(target.as_str()),
                    Some(sha256),
                    "{name} {target}"
                );
            }
        }
    }
    // The three frozen requests select three different closures on Windows x64.
    let windows = PlatformId::parse("win-x64").unwrap();
    let closures = FROZEN
        .iter()
        .map(|(name, _)| {
            let lock = std::fs::read(fixtures().join(format!("signed/{name}.lock.json"))).unwrap();
            format!("{:?}", read_lock(&lock).unwrap().platforms[&windows])
        })
        .collect::<BTreeSet<_>>();
    assert_eq!(closures.len(), FROZEN.len());
}

#[tokio::test]
async fn tampered_metadata_is_refused_by_the_tuf_client() {
    let fixture = fixture();
    let mut set = fixture["metadata"].clone();
    // Change what the targets role signed without signing it again.
    set["targets"]["signed"]["targets"][RECIPE]["hashes"]["sha256"] = json!("3".repeat(64));
    // The snapshot pins the targets metadata bytes, so the link check fails
    // before the targets signature is reached.
    let directory = tempfile::tempdir().unwrap();
    let refused = support::tuf::load_set(&fixture, &set, directory.path())
        .await
        .expect_err("altered targets metadata must not load");
    assert!(refused.to_string().contains("Hash mismatch"), "{refused}");

    // Re-link the snapshot and timestamp with the snapshot and timestamp keys.
    // The targets role's signature still covers the original bytes.
    let keys = repository::Keys::derive();
    let mut snapshot = set["snapshot"]["signed"].clone();
    snapshot["meta"]["targets.json"] = repository::meta(&set["targets"]);
    set["snapshot"] = repository::sign(snapshot, &[&keys.snapshot]);
    let mut timestamp = set["timestamp"]["signed"].clone();
    timestamp["meta"]["snapshot.json"] = repository::meta(&set["snapshot"]);
    set["timestamp"] = repository::sign(timestamp, &[&keys.timestamp]);
    let directory = tempfile::tempdir().unwrap();
    let refused = support::tuf::load_set(&fixture, &set, directory.path())
        .await
        .expect_err("targets metadata without a valid targets signature must not load");
    assert!(
        refused.to_string().to_lowercase().contains("signature"),
        "{refused}"
    );
}

#[test]
fn tampered_extension_bytes_are_refused() {
    let fixture = fixture();
    let targets = targets_of(&fixture["metadata"]);
    let path = "extensions/fsharp-frontend/0.6.0/win-x64.zip";
    let mut bytes = recipe_bytes(&fixture, path);
    let last = bytes.len() - 2;
    bytes[last] = b'?';
    assert_eq!(
        targets.authenticate(path, &bytes).unwrap_err().code,
        Code::TargetDigestMismatch
    );
}

#[tokio::test]
async fn expired_metadata_is_refused_by_the_tuf_client() {
    let fixture = fixture();
    let mut set = fixture["metadata"].clone();
    set["timestamp"] = fixture["rejectionMetadata"]["expiredTimestamp"].clone();
    assert_eq!(
        set["timestamp"]["signed"]["expires"],
        "2020-01-01T00:00:00Z"
    );
    let directory = tempfile::tempdir().unwrap();
    let refused = support::tuf::load_set(&fixture, &set, directory.path())
        .await
        .expect_err("expired timestamp metadata must not load");
    assert!(
        refused.to_string().to_lowercase().contains("expired"),
        "{refused}"
    );
}

#[tokio::test]
async fn a_learned_revocation_is_enforced_without_changing_descriptor_bytes() {
    let fixture = fixture();
    let before = targets_of(&fixture["metadata"]);
    let after = targets_of(&fixture["learnedRevocation"]);
    let release = "releases/morphir-dotnet-native-aot/1.2.3.json";
    assert_eq!(
        fixture["learnedRevocation"]["targets"]["signed"]["version"],
        2
    );
    // The descriptor bytes are the same; only the authenticated state moved.
    assert_eq!(before.digest(release), after.digest(release));
    after
        .authenticate(release, &recipe_bytes(&fixture, release))
        .unwrap();
    assert_eq!(after.custom(release).unwrap()["status"], "revoked");

    // The F# recipe still authenticates, but its native-aot binding is refused.
    let refused = after
        .check_recipe(RECIPE, &recipe_bytes(&fixture, RECIPE), reader(&fixture))
        .unwrap_err();
    assert_eq!(
        (refused.code, refused.path.as_str()),
        (Code::ReleaseRevoked, "hosts[0].version")
    );

    // The existing TUF client refuses the exact release and drops it from stable.
    let directory = tempfile::tempdir().unwrap();
    let client = support::tuf::load_set(&fixture, &fixture["learnedRevocation"], directory.path())
        .await
        .unwrap();
    let platform = PlatformId::parse("win-x64")
        .unwrap()
        .tool_platform()
        .unwrap();
    let cli = Version::parse("0.4.0").unwrap();
    let tool = ToolId::parse("morphir-dotnet-native-aot").unwrap();
    let exact = client
        .resolve(
            &tool,
            &Selection::Exact(Version::parse("1.2.3").unwrap()),
            &platform,
            &cli,
        )
        .await
        .unwrap_err();
    assert!(exact.to_string().contains("revoked"), "{exact}");
    assert!(
        client
            .resolve(&tool, &Selection::Channel(Channel::Stable), &platform, &cli)
            .await
            .is_err()
    );
    // Other offerings are unaffected.
    client
        .resolve(
            &ToolId::parse("morphir-dotnet-self-contained").unwrap(),
            &Selection::Channel(Channel::Stable),
            &platform,
            &cli,
        )
        .await
        .unwrap();
}

#[test]
fn unsigned_developer_artifacts_keep_separate_provenance() {
    let fixture = fixture();
    let targets = targets_of(&fixture["metadata"]);
    // An unsigned local build is not an authenticated target, so no recipe
    // can bind it and no portable lock can name it.
    let developer = "extensions/fsharp-frontend/0.6.0-dev/win-x64.zip";
    let refused = targets
        .authenticate(developer, b"TEST-ONLY local developer build\n")
        .unwrap_err();
    assert_eq!(refused.code, Code::TargetNotAuthenticated);
    let mut recipe: Value = serde_json::from_slice(&recipe_bytes(&fixture, RECIPE)).unwrap();
    recipe["providers"][0]["platforms"]["win-x64"]["artifactTarget"] = json!(developer);
    let recipe = read_recipe(&serde_json::to_vec(&recipe).unwrap()).unwrap();
    let refused = targets
        .check_recipe_providers(&recipe, reader(&fixture))
        .unwrap_err();
    assert_eq!(
        (refused.code, refused.path.as_str()),
        (
            Code::TargetNotAuthenticated,
            "providers[0].platforms.win-x64.artifactTarget"
        )
    );

    // Admitted by explicit developer policy, it stays labelled as such in a
    // local receipt. Probing it checks its claims; it does not authenticate it.
    let receipt = read_receipt(
        &std::fs::read(fixtures().join("receipt/developer-frontend-probed.json")).unwrap(),
    )
    .unwrap();
    let (installation, claim_check) = receipt.providers[0].installation.as_ref().unwrap();
    assert_eq!(installation.authentication, Authentication::LocalDeveloper);
    assert_eq!(*claim_check, ClaimCheck::Probed(ProbeSource::Describe));
    // The spelling is the existing tool provenance tag for local developer packages.
    assert_eq!(
        serde_json::to_value(ToolProvenance::LocalDeveloper).unwrap(),
        json!({ "kind": "local-developer" })
    );
}
