//! Runs `docs/spec/toolchain/fixtures/0.1.0-draft.1/signed/cases.json`
//! against the TEST-ONLY signed repository: offering selection, recipe and
//! provider bindings, trust cases expressed as declared mutations of the
//! committed files, frozen locks and lock-against-recipe bindings.

mod support;

use morphir_distribution::{Channel, Selection, ToolId, ToolReleaseRecord};
use morphir_toolchain_contract::{
    AuthenticatedTargets, Code, Operation, PlatformId, PresetId, read_lock, read_recipe,
    read_request, resolve_closure,
};
use semver::{Version, VersionReq};
use serde_json::{Value, json};
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

async fn authenticated(fixture: &Value, set: &Value) -> (tempfile::TempDir, AuthenticatedTargets) {
    let directory = tempfile::tempdir().unwrap();
    let targets = support::tuf::targets_of(fixture, set, directory.path())
        .await
        .expect("the test-only repository authenticates");
    (directory, targets)
}

fn outcome<T>(result: morphir_toolchain_contract::Result<T>) -> Result<(), (String, String)> {
    result
        .map(drop)
        .map_err(|refusal| (refusal.code.as_str().to_owned(), refusal.path))
}

fn expected(case: &Value) -> Result<(), (String, String)> {
    match &case["expected"] {
        Value::String(valid) if valid == "valid" => Ok(()),
        success if success.get("code").is_none() => Ok(()),
        refusal => Err((
            refusal["code"].as_str().expect("expected code").to_owned(),
            refusal["path"].as_str().expect("expected path").to_owned(),
        )),
    }
}

#[test]
fn committed_fixtures_are_reproducible_from_their_labels() {
    let write = std::env::var("MORPHIR_TOOLCHAIN_FIXTURES").as_deref() == Ok("write");
    let store = |path: PathBuf, value: &Value| {
        if write {
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            let mut text = serde_json::to_string_pretty(value).unwrap();
            text.push('\n');
            std::fs::write(&path, text).unwrap();
        }
        assert_eq!(
            read_json(&path),
            *value,
            "{}: regenerate with MORPHIR_TOOLCHAIN_FIXTURES=write",
            path.display()
        );
    };
    store(signed_dir().join("repository.json"), &repository::fixture());
    let locks = repository::frozen_locks(&repository::published());
    for (name, request, lock) in &locks {
        let request_path = signed_dir().join(format!("{name}.toml"));
        if write {
            std::fs::write(&request_path, request).unwrap();
        }
        assert_eq!(
            &std::fs::read_to_string(&request_path).unwrap(),
            request,
            "{name}"
        );
        store(signed_dir().join(format!("{name}.lock.json")), lock);
    }
    store(
        signed_dir().join("negative/lock-provider-not-in-recipe.lock.json"),
        &repository::lock_with_unbound_provider(&locks[0].2),
    );
}

#[test]
fn every_fixture_key_is_derived_from_its_test_only_label() {
    let fixture = fixture();
    let listed = fixture["testOnlyKeys"].as_array().unwrap();
    let root_keys = fixture["trustedRoot"]["signed"]["keys"]
        .as_object()
        .unwrap();
    assert_eq!(listed.len(), root_keys.len());
    let derived = repository::Keys::derive();
    for key in listed {
        let label = key["label"].as_str().unwrap();
        assert!(label.starts_with(KEY_LABEL_PREFIX));
        let rederived = derived
            .all()
            .into_iter()
            .find(|candidate| candidate.label == label)
            .unwrap();
        assert_eq!(rederived.public_hex(), key["public"], "{label}");
        assert_eq!(
            root_keys[key["keyId"].as_str().unwrap()]["keyval"]["public"],
            key["public"]
        );
    }
    assert!(
        fixture["testOnly"]
            .as_str()
            .unwrap()
            .starts_with("TEST-ONLY.")
    );
    for (path, bytes) in fixture["targetFiles"].as_object().unwrap() {
        if path.starts_with("artifacts/") || path.starts_with("packages/") || path.ends_with(".zip")
        {
            assert!(
                bytes.as_str().unwrap().starts_with("TEST-ONLY synthetic "),
                "{path}"
            );
        }
    }
}

#[tokio::test]
async fn the_v1_tool_client_selects_each_offering_by_tool_id_and_platform() {
    let fixture = fixture();
    let directory = tempfile::tempdir().unwrap();
    let client = support::tuf::load_set(&fixture, &fixture["metadata"], directory.path())
        .await
        .unwrap();
    let (_keep, targets) = authenticated(&fixture, &fixture["metadata"]).await;
    let recipe = targets
        .check_recipe("toolchains/recipes/fsharp-builtin/1.0.0.json")
        .await
        .unwrap();
    let cli = Version::parse(cases()["referenceClient"]["cliVersion"].as_str().unwrap()).unwrap();
    let mut selected = BTreeSet::new();
    for offering in &ARCHIVE_OFFERINGS {
        let host = recipe
            .hosts()
            .iter()
            .find(|host| host.deployment().as_str() == offering.deployment)
            .unwrap();
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
            let binding = &host.platforms()[&platform];
            assert_eq!(
                resolved.artifact().target_path().as_str(),
                binding.target.as_str()
            );
            assert_eq!(resolved.digest(), binding.sha256.digest());
            selected.insert(resolved.digest().clone());
        }
    }
    // Implementation, deployment and platform are each part of the identity,
    // although every Windows archive's entry point is morphir.exe.
    assert_eq!(selected.len(), 18);
}

/// `>=0.0.0` matches no prerelease, so a v1 offering published with it is
/// invisible to every prerelease Morphir CLI. Managers do not pass a CLI
/// version for offerings; see the toolset recipe page.
#[test]
fn a_zero_floor_matches_no_prerelease_cli() {
    let floor = VersionReq::parse(">=0.0.0").unwrap();
    assert!(!floor.matches(&Version::parse("0.4.0-beta.12").unwrap()));
    assert!(floor.matches(&Version::parse("0.4.0").unwrap()));
}

#[tokio::test]
async fn offering_releases_are_unchanged_v1_descriptors() {
    let fixture = fixture();
    let (_keep, targets) = authenticated(&fixture, &fixture["metadata"]).await;
    let schema = read_json(
        &PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../website/static/schemas/tool-release-v1.schema.json"),
    );
    let validator = jsonschema::validator_for(&schema).unwrap();
    let mut releases = 0;
    for path in fixture["targetFiles"].as_object().unwrap().keys() {
        if !path.starts_with("releases/") {
            continue;
        }
        releases += 1;
        let bytes = targets.read(path).await.unwrap();
        let record: ToolReleaseRecord = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(record.schema_version(), 1, "{path}");
        assert!(
            validator.is_valid(&serde_json::from_slice::<Value>(&bytes).unwrap()),
            "{path}"
        );
        assert_eq!(targets.custom(path).unwrap()["kind"], "tool-release");
    }
    assert_eq!(releases, ARCHIVE_OFFERINGS.len() + 1);
}

fn summarize(closure: &morphir_toolchain_contract::PlatformClosure) -> Vec<Value> {
    closure
        .providers()
        .iter()
        .map(|provider| {
            let (operation, member, id) = match provider.operation() {
                Operation::Compile { language } => ("compile", "language", language),
                Operation::Generate { target } => ("generate", "target", target),
            };
            json!({
                "operation": operation,
                member: id.as_str(),
                "delivery": provider.delivery().kind().as_str(),
                "extensionId": provider.extension_id().as_str()
            })
        })
        .collect()
}

#[tokio::test]
async fn selection_distinguishes_implementation_deployment_and_platform() {
    let fixture = fixture();
    let (_keep, targets) = authenticated(&fixture, &fixture["metadata"]).await;
    let mut failures = Vec::new();
    for case in cases()["selection"].as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let recipe = targets
            .check_recipe(case["recipe"].as_str().unwrap())
            .await
            .unwrap();
        let request = read_request(case["request"].as_str().unwrap().as_bytes()).unwrap();
        let platform = PlatformId::parse(case["platform"].as_str().unwrap()).unwrap();
        let result = resolve_closure(&recipe, &request, platform);
        match (&result, expected(case)) {
            (Ok(closure), Ok(())) => {
                let host_target = case["expected"]["hostTarget"].as_str().unwrap();
                if closure.host().target.as_str() != host_target
                    || Some(&closure.host().sha256) != targets.digest(host_target)
                    || Value::Array(summarize(closure)) != case["expected"]["providers"]
                {
                    failures.push(format!("{name}: {closure:?}"));
                }
            }
            _ => {
                let actual = outcome(result);
                if actual != expected(case) {
                    failures.push(format!("{name}: {actual:?}"));
                }
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[tokio::test]
async fn recipe_checks() {
    let fixture = fixture();
    let (_keep, targets) = authenticated(&fixture, &fixture["metadata"]).await;
    let mut failures = Vec::new();
    for case in cases()["recipeChecks"].as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let actual = outcome(targets.check_recipe(case["recipe"].as_str().unwrap()).await);
        if actual != expected(case) {
            failures.push(format!("{name}: {actual:?}, expected {:?}", expected(case)));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// Apply a trust case's declared mutations to the committed files.
fn mutate(fixture: &Value, case: &Value) -> (Value, Value) {
    let mut fixture = fixture.clone();
    let mut set = fixture[case["metadata"].as_str().unwrap()].clone();
    for mutation in case["mutations"].as_array().unwrap() {
        match mutation["op"].as_str().unwrap() {
            "set-signed-member" => {
                let role = mutation["role"].as_str().unwrap();
                *set[role]["signed"]
                    .pointer_mut(mutation["pointer"].as_str().unwrap())
                    .expect("pointer names a member") = mutation["value"].clone();
            }
            "relink" => repository::relink(&mut set),
            "replace-role" => {
                let from = mutation["from"]
                    .as_str()
                    .unwrap()
                    .split('.')
                    .fold(&fixture, |value, key| &value[key])
                    .clone();
                set[mutation["role"].as_str().unwrap()] = from;
            }
            "replace-target-bytes" => {
                let with = fixture["targetFiles"][mutation["with"].as_str().unwrap()].clone();
                assert!(with.is_string());
                fixture["targetFiles"][mutation["target"].as_str().unwrap()] = with;
            }
            "replace-target-text" => {
                let target = mutation["target"].as_str().unwrap();
                let text = fixture["targetFiles"][target].as_str().unwrap();
                let find = mutation["find"].as_str().unwrap();
                assert!(text.contains(find), "{target} contains {find}");
                let replaced = text.replacen(find, mutation["replace"].as_str().unwrap(), 1);
                fixture["targetFiles"][target] = json!(replaced);
            }
            other => panic!("unknown mutation {other}"),
        }
    }
    (fixture, set)
}

#[tokio::test]
async fn trust_cases() {
    let committed = fixture();
    let mut failures = Vec::new();
    for case in cases()["trust"].as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let (fixture, set) = mutate(&committed, case);
        let directory = tempfile::tempdir().unwrap();
        let loaded = support::tuf::targets_of(&fixture, &set, directory.path()).await;
        let action = &case["action"];
        let actual = match (action["op"].as_str().unwrap(), loaded) {
            ("load", loaded) => outcome(loaded),
            (_, Err(refusal)) => outcome::<()>(Err(refusal)),
            ("read", Ok(targets)) => {
                outcome(targets.read(action["target"].as_str().unwrap()).await)
            }
            ("check-recipe", Ok(targets)) => outcome(
                targets
                    .check_recipe(action["recipe"].as_str().unwrap())
                    .await,
            ),
            ("authenticate", Ok(targets)) => outcome(targets.authenticate(
                action["target"].as_str().unwrap(),
                action["text"].as_str().unwrap().as_bytes(),
            )),
            ("check-recipe-bindings", Ok(targets)) => {
                let bytes = targets
                    .read(action["recipe"].as_str().unwrap())
                    .await
                    .unwrap();
                let mut document: Value = serde_json::from_slice(&bytes).unwrap();
                for change in action["documentMutations"].as_array().unwrap() {
                    *document
                        .pointer_mut(change["pointer"].as_str().unwrap())
                        .expect("pointer names a member") = change["value"].clone();
                }
                let recipe = read_recipe(&serde_json::to_vec(&document).unwrap()).unwrap();
                outcome(targets.check_recipe_bindings(&recipe).await)
            }
            (other, _) => panic!("unknown action {other}"),
        };
        if actual != expected(case) {
            failures.push(format!("{name}: {actual:?}, expected {:?}", expected(case)));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[tokio::test]
async fn frozen_locks_equal_the_resolution_of_their_requests() {
    let fixture = fixture();
    let (_keep, targets) = authenticated(&fixture, &fixture["metadata"]).await;
    let six = PlatformId::FIRST_DELIVERY
        .iter()
        .map(|name| PlatformId::parse(name).unwrap())
        .collect::<BTreeSet<_>>();
    for case in cases()["frozen"].as_array().unwrap() {
        assert_eq!(case["expected"], "lock-equals-resolution");
        let recipe_path = case["recipe"].as_str().unwrap();
        let recipe = targets.check_recipe(recipe_path).await.unwrap();
        let read = |member: &str| {
            std::fs::read(signed_dir().join(case[member].as_str().unwrap())).unwrap()
        };
        let request = read_request(&read("request")).unwrap();
        let lock = read_lock(&read("lock")).unwrap();
        lock.check_request(&request).unwrap();
        assert_eq!(Some(&lock.recipe().sha256), targets.digest(recipe_path));
        assert_eq!(
            lock.platforms().keys().copied().collect::<BTreeSet<_>>(),
            six
        );
        for (platform, closure) in lock.platforms() {
            assert_eq!(
                &resolve_closure(&recipe, &request, *platform).unwrap(),
                closure,
                "{platform}"
            );
        }
    }
}

#[tokio::test]
async fn locks_bind_closures_the_recipe_allows() {
    let fixture = fixture();
    let (_keep, targets) = authenticated(&fixture, &fixture["metadata"]).await;
    let mut failures = Vec::new();
    for case in cases()["lockRecipe"].as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let recipe_bytes = targets
            .read(case["recipe"].as_str().unwrap())
            .await
            .unwrap();
        let recipe = read_recipe(&recipe_bytes).unwrap();
        let lock_bytes = std::fs::read(signed_dir().join(case["lock"].as_str().unwrap())).unwrap();
        let lock = read_lock(&lock_bytes).unwrap();
        let actual = outcome(lock.check_recipe(&recipe_bytes, &recipe));
        if actual != expected(case) {
            failures.push(format!("{name}: {actual:?}, expected {:?}", expected(case)));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// A repository may list a recipe target whose path is not portable; selection
/// refuses it with a code instead of failing.
#[tokio::test]
async fn a_non_portable_recipe_target_is_refused_without_panicking() {
    let keys = repository::Keys::derive();
    let mut published = repository::Targets::new();
    let recipe = json!({ "preset": "con", "version": "1.0.0" });
    repository::add_recipe(&mut published, &recipe, &["stable"], "active", |_| {});
    let fixture = json!({
        "trustedRoot": repository::root(&keys),
        "targetFiles": published
            .iter()
            .map(|(path, target)| (path.clone(), Value::String(target.bytes.clone())))
            .collect::<serde_json::Map<_, _>>()
    });
    let set = repository::metadata(&keys, &published, 1, repository::NEVER);
    let (_keep, targets) = authenticated(&fixture, &set).await;
    let refused = targets
        .select_recipe(&PresetId::parse("con").unwrap(), &Channel::Stable)
        .unwrap_err();
    assert_eq!(refused.code, Code::NonPortablePath);
    let refused = targets
        .check_recipe("toolchains/recipes/con/1.0.0.json")
        .await
        .unwrap_err();
    assert_eq!(
        (refused.code, refused.path.as_str()),
        (Code::NonPortablePath, "")
    );
}
