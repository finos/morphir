// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
use serde_json::Value;
use std::{fs, path::PathBuf};
fn source() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}
const PATH: &str = "spec/package/mck/fixtures/mvp-scoped-update";
#[test]
fn scoped_update_freezes_target_child_and_sibling_outcomes() {
    let path = source().join(PATH).join("signed/expected/update.lock.json");
    assert!(
        path.is_file(),
        "scoped update requires an independently frozen full lock"
    );
    let lock: Value = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
    let versions: Vec<_> = lock["graph"]["nodes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|n| {
            (
                n["release"]["packagePath"].as_str().unwrap(),
                n["release"]["version"].as_str().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        versions,
        vec![
            ("example.com/finance/loan-rules", "1.0.0"),
            ("example.com/finance/child", "1.1.0"),
            ("example.com/finance/eligibility", "1.3.0"),
            ("example.com/finance/sibling", "1.0.0")
        ]
    );
}

#[path = "../examples/package_update_fixture.rs"]
#[allow(dead_code, unused_imports)]
mod author;
use author::fixture;
#[path = "support/package_update.rs"]
#[allow(dead_code)]
mod update;
use base64::{Engine, engine::general_purpose::STANDARD};
use sha2::{Digest, Sha256};
fn digest(data: &[u8]) -> String {
    format!(
        "sha256:{}",
        Sha256::digest(data)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>()
    )
}
fn physical(reference: &Value) -> String {
    let (dir, leaf) = reference["path"]
        .as_str()
        .unwrap()
        .rsplit_once('/')
        .unwrap();
    format!(
        "registry/targets/{dir}/{}.{leaf}",
        reference["digest"]
            .as_str()
            .unwrap()
            .strip_prefix("sha256:")
            .unwrap()
    )
}
// Version-aware upstream TUF verification, independent of authoring and runtime.
fn authenticate(files: &fixture::Files, variant: Option<&str>) {
    use chrono::DateTime;
    use futures_util::io::{AsyncReadExt, Cursor};
    use tuf::{
        Database,
        client::{Client, Config},
        metadata::{MetadataPath, MetadataVersion, RawSignedMetadata, TargetPath},
        pouf::Pouf1,
        repository::{EphemeralRepository, RepositoryStorage},
    };
    let prefix = variant
        .map(|v| format!("variants/{v}"))
        .unwrap_or_else(|| "registry/metadata".into());
    futures_executor::block_on(async {
        let remote = EphemeralRepository::<Pouf1>::new();
        let root = &files["registry/metadata/1.root.json"];
        remote
            .store_metadata(
                &MetadataPath::root(),
                MetadataVersion::Number(1),
                &mut Cursor::new(root),
            )
            .await
            .unwrap();
        for role in ["targets", "snapshot", "timestamp"] {
            remote
                .store_metadata(
                    &MetadataPath::new(role).unwrap(),
                    if role == "timestamp" {
                        MetadataVersion::None
                    } else {
                        MetadataVersion::Number(2)
                    },
                    &mut Cursor::new(&files[&format!("{prefix}/2.{role}.json")]),
                )
                .await
                .unwrap();
        }
        for (path, bytes) in files {
            if let Some(path) = path.strip_prefix("registry/targets/") {
                remote
                    .store_target(&TargetPath::new(path).unwrap(), &mut Cursor::new(bytes))
                    .await
                    .unwrap();
            }
        }
        let database =
            Database::<Pouf1>::from_trusted_root(&RawSignedMetadata::new(root.clone())).unwrap();
        let mut client = Client::from_database(
            Config::default(),
            database,
            EphemeralRepository::new(),
            remote,
        );
        let at = DateTime::parse_from_rfc3339("2099-01-01T00:00:00Z")
            .unwrap()
            .to_utc();
        client.update_with_start_time(&at).await.unwrap();
        let targets: Vec<_> = client
            .database()
            .trusted_targets()
            .unwrap()
            .targets()
            .iter()
            .map(|(p, d)| (p.clone(), d.clone()))
            .collect();
        assert!(targets.len() >= 18);
        for (path, description) in targets {
            let mut stream = client
                .fetch_target_with_start_time(&path, &at)
                .await
                .unwrap();
            let mut bytes = Vec::new();
            stream.read_to_end(&mut bytes).await.unwrap();
            assert_eq!(bytes.len() as u64, description.length());
        }
    });
}
#[test]
fn update_fixture_reproduces_and_independent_tuf_and_ring_verify_every_view() {
    let frozen = fixture::read_files(&source().join(PATH).join("signed")).unwrap();
    fixture::check_files(
        &source().join(PATH).join("signed"),
        &author::generate(&source()).unwrap(),
    )
    .unwrap();
    for variant in [
        None,
        Some("scope-conflict"),
        Some("yanked-frozen"),
        Some("yanked-root"),
        Some("revoked-frozen"),
    ] {
        authenticate(&frozen, variant);
    }
    let policy: Value = serde_json::from_slice(&frozen["trust-policy.json"]).unwrap();
    let keys: Vec<String> = policy["publisherRules"][0]["publicKeys"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap().into())
        .collect();
    for (path, data) in &frozen {
        if !path.starts_with("registry/targets/records/") {
            continue;
        }
        let record: Value = serde_json::from_slice(data).unwrap();
        let envelope: Value =
            serde_json::from_slice(&frozen[&physical(&record["statement"])]).unwrap();
        assert!(fixture::verify_dsse(&envelope, &keys, 2));
        let payload: Value = serde_json::from_slice(
            &STANDARD
                .decode(envelope["payload"].as_str().unwrap())
                .unwrap(),
        )
        .unwrap();
        for field in [
            "release",
            "irPackageName",
            "dependencies",
            "manifestDigest",
            "contentDigest",
        ] {
            assert_eq!(record[field], payload[field]);
        }
        let bundle = record["source"]["path"].as_str().unwrap();
        let manifest: Value =
            serde_json::from_slice(&frozen[&format!("registry/{bundle}/manifest.json")]).unwrap();
        let canonical = serde_json::to_vec(&manifest).unwrap();
        assert_eq!(record["manifestDigest"], digest(&canonical));
        let mut content = b"morphir-package-content:0.1.0-draft.1\n".to_vec();
        content.extend(&canonical);
        assert_eq!(record["contentDigest"], digest(&content));
        for (path, expected) in manifest["content"].as_object().unwrap() {
            assert_eq!(
                *expected,
                digest(&frozen[&format!("registry/{bundle}/{path}")])
            );
        }
    }
}
#[test]
fn frozen_locks_pin_authenticated_immutable_records_and_fresh_metadata() {
    let files = fixture::read_files(&source().join(PATH).join("signed")).unwrap();
    for path in [
        "morphir.lock",
        "expected/update.lock.json",
        "expected/exact-old.lock.json",
        "expected/yanked-frozen.lock.json",
        "expected/yanked-root.lock.json",
    ] {
        let lock: Value = serde_json::from_slice(&files[path]).unwrap();
        assert_eq!(
            lock["graph"]["root"],
            serde_json::json!({"packagePath":"example.com/finance/loan-rules","version":"1.0.0"})
        );
        for acquisition in lock["acquisitions"].as_array().unwrap() {
            let data = &files[&physical(&acquisition["record"])];
            assert_eq!(acquisition["record"]["digest"], digest(data));
            let record: Value = serde_json::from_slice(data).unwrap();
            assert_eq!(record["release"], acquisition["release"]);
            assert_eq!(record["source"], acquisition["source"]);
            let node = lock["graph"]["nodes"]
                .as_array()
                .unwrap()
                .iter()
                .find(|n| n["release"] == record["release"])
                .unwrap();
            for field in ["irPackageName", "manifestDigest", "contentDigest"] {
                assert_eq!(node[field], record[field]);
            }
            let statement = lock["evidence"]
                .as_array()
                .unwrap()
                .iter()
                .find(|e| e["id"] == acquisition["statement"])
                .unwrap();
            assert_eq!(record["statement"]["digest"], statement["digest"]);
            assert_eq!(record["statement"]["path"], statement["path"]);
        }
        let mut canonical = serde_json::to_vec_pretty(&lock).unwrap();
        canonical.push(b'\n');
        assert_eq!(canonical, files[path]);
        for e in lock["evidence"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|e| e["kind"] != "release-statement")
        {
            let relative = e["path"].as_str().unwrap();
            let physical = if e["kind"] == "tuf-root" || !path.contains("yanked-") {
                format!("registry/{relative}")
            } else {
                format!(
                    "variants/{}/{}",
                    if path.contains("yanked-root") {
                        "yanked-root"
                    } else {
                        "yanked-frozen"
                    },
                    relative.strip_prefix("metadata/").unwrap()
                )
            };
            assert_eq!(e["digest"], digest(&files[&physical]));
        }
    }
    let old: Value = serde_json::from_slice(&files["registry/metadata/1.timestamp.json"]).unwrap();
    let fresh: Value =
        serde_json::from_slice(&files["registry/metadata/2.timestamp.json"]).unwrap();
    assert_eq!(old["signed"]["expires"], "2020-01-01T00:00:00Z");
    assert_eq!(fresh["signed"]["expires"], "2100-01-01T00:00:00Z");
}
#[test]
fn update_controller_prepares_isolated_cases_and_delays_state_faults() {
    let original = fixture::read_files(&source().join(PATH).join("signed")).unwrap();
    let corpus = update::load(&source());
    assert_eq!(corpus.scope, "fresh-scoped-update");
    assert_eq!(corpus.profile, update::mvp::PROFILE);
    let mut ids = std::collections::BTreeSet::new();
    for case in corpus.cases {
        assert!(ids.insert(case.id.clone()));
        assert_eq!(
            case.expected_lock.is_some(),
            case.expected == update::Expected::Updated
        );
        assert_eq!(
            case.diagnostic.is_some(),
            case.expected == update::Expected::Refused
        );
        if let Some(path) = &case.expected_lock {
            assert!(source().join(PATH).join("signed").join(path).is_file());
        }
        let temporary = tempfile::tempdir().unwrap();
        let prepared = update::prepare(&source(), temporary.path(), &case);
        assert_eq!(prepared.targets, case.targets);
        assert_ne!(prepared.restore.lock, prepared.output);
        assert!(!prepared.restore.output.exists());
        if !matches!(
            case.setup,
            update::Setup::InvalidGraph
                | update::Setup::AcquisitionPin
                | update::Setup::StatementPin
        ) {
            assert_eq!(
                fs::read(&prepared.restore.lock).unwrap(),
                original["morphir.lock"]
            );
        }
        if case.setup == update::Setup::OccupiedOutput {
            assert_eq!(fs::read(&prepared.output).unwrap(), update::mvp::SENTINEL);
        } else {
            assert!(!prepared.output.exists());
        }
        if matches!(
            case.setup,
            update::Setup::MissingEstablishedState
                | update::Setup::CorruptState
                | update::Setup::UncertainState
        ) {
            assert!(prepared.restore.initialize);
            assert!(!prepared.restore.state.exists());
            fs::create_dir(&prepared.restore.state).unwrap();
            fs::write(prepared.restore.state.join("trust.sqlite"), b"old database").unwrap();
            update::after_initialize(&case, &prepared);
            match case.setup {
                update::Setup::MissingEstablishedState => {
                    assert!(!prepared.restore.state.join("trust.sqlite").exists())
                }
                update::Setup::CorruptState => assert_eq!(
                    fs::read(prepared.restore.state.join("trust.sqlite")).unwrap(),
                    b"not a SQLite database\n"
                ),
                update::Setup::UncertainState => assert_eq!(
                    fs::read(prepared.restore.state.join("operation")).unwrap(),
                    b"unresolved prior operation\n"
                ),
                _ => unreachable!(),
            }
        }
    }
    assert_eq!(
        fixture::read_files(&source().join(PATH).join("signed")).unwrap(),
        original
    );
}

#[test]
fn update_libraries_have_valid_v4_ir_and_matching_dependency_associations() {
    let schema: Value = serde_json::from_slice(
        &fs::read(source().join("website/static/schemas/morphir-ir-v4.json")).unwrap(),
    )
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    let files = fixture::read_files(&source().join(PATH).join("signed")).unwrap();
    for (path, data) in files
        .iter()
        .filter(|(path, _)| path.ends_with("/manifest.json"))
    {
        let manifest: Value = serde_json::from_slice(data).unwrap();
        let ir: Value =
            serde_json::from_slice(&files[&path.replace("/manifest.json", "/ir.json")]).unwrap();
        let errors: Vec<_> = validator.iter_errors(&ir).map(|e| e.to_string()).collect();
        assert!(errors.is_empty(), "{path}: {errors:#?}");
        assert_eq!(
            ir["distribution"]["Library"]["packageName"],
            manifest["ir"]["packageName"]
        );
        assert_eq!(
            ir["distribution"]["Library"]["dependencies"]
                .as_object()
                .unwrap()
                .keys()
                .collect::<Vec<_>>(),
            manifest["dependencies"]
                .as_object()
                .unwrap()
                .keys()
                .collect::<Vec<_>>()
        );
    }
}

#[test]
fn executable_example_uses_the_independently_frozen_update_inputs_and_lock() {
    let files = fixture::read_files(&source().join(PATH).join("signed")).unwrap();
    let example = source().join("examples/package/local-library-update");
    let copied = fixture::read_files(&example.join("fixture")).unwrap();
    let required: fixture::Files = files
        .iter()
        .filter(|(path, _)| {
            path.starts_with("registry/")
                || matches!(path.as_str(), "trust-policy.json" | "morphir.lock")
        })
        .map(|(p, b)| (p.clone(), b.clone()))
        .collect();
    assert_eq!(copied, required);
    assert_eq!(
        fs::read(example.join("golden/update.lock.json")).unwrap(),
        files["expected/update.lock.json"]
    );
}
