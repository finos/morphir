use super::*;
use morphir_extension_sdk::protocol::MEP_VERSION;

fn guest_bytes() -> &'static [u8] {
    static BYTES: std::sync::OnceLock<Vec<u8>> = std::sync::OnceLock::new();
    BYTES.get_or_init(|| {
        let temp = TempDir::new().unwrap();
        let executable = temp.path().join("probe-guest");
        let output = std::process::Command::new("rustc")
            .arg(
                PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/extension_probe.rs"),
            )
            .env("MEP_VERSION", MEP_VERSION)
            .arg("-o")
            .arg(&executable)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        std::fs::read(executable).unwrap()
    })
}

fn setup(mode: &str) -> (TempDir, PathBuf, TestIndex) {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let index = write_test_index(
        temp.path(),
        "morphir-test",
        "Morphir test frontend",
        "1.2.3",
        guest_bytes(),
    );
    let path = index.root.join("extensions/morphir-test.jsonl");
    let mut record: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    record["schemaVersion"] = "2.0.0-draft.2".into();
    record["frontend"]["incremental"] = false.into();
    record["frontend"]["fragments"] = false.into();
    record["artifacts"][0]["claims"] = serde_json::json!({
        "claimsVersion": "0.1.0-draft.2", "protocolVersions": [MEP_VERSION],
        "extension": {"id": "morphir-test", "name": "Morphir test frontend", "version": "1.2.3", "types": ["frontend"]},
        "capabilities": {"frontend": record["frontend"].clone()}
    });
    record["artifacts"][0]["args"] = serde_json::json!([mode]);
    if mode == "wasm" {
        record["artifacts"][0]["runtime"] = "wasm".into();
        record["artifacts"][0]
            .as_object_mut()
            .unwrap()
            .remove("platform");
        record["artifacts"][0]["args"] = serde_json::json!([]);
        record["artifacts"][0]["executable"] = false.into();
    }
    std::fs::write(path, format!("{record}\n")).unwrap();
    assert!(
        add_test_repository("local", &index.root, &home, temp.path())
            .status
            .success()
    );
    (temp, home, index)
}

fn installed(home: &std::path::Path) -> serde_json::Value {
    let catalog: serde_json::Value =
        serde_json::from_slice(&std::fs::read(home.join("catalog/extensions.json")).unwrap())
            .unwrap();
    catalog["extensions"][0].clone()
}

#[test]
fn describe_records_probed_claims_and_lists_source() {
    let (temp, home, _) = setup("describe");
    let output = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local",
        ],
        &home,
        temp.path(),
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let entry = installed(&home);
    assert_eq!(entry["claimCheck"], "probed");
    assert_eq!(entry["probeSource"], "describe");
    assert!(String::from_utf8_lossy(&output.stdout).contains("frontend"));
    let list = run_morphir(&["extension", "list"], &home, temp.path());
    assert!(
        list.status.success(),
        "{}",
        String::from_utf8_lossy(&list.stderr)
    );
    let text = String::from_utf8_lossy(&list.stdout);
    assert!(
        text.contains("probed (describe)") && text.contains("frontend"),
        "{text}"
    );
}

/// An index record in the draft.1 spelling, as hosts 0.4.0-beta.5 and beta.6 wrote it, still
/// installs, and the catalog this host writes uses only the draft.2 names (kb `morphir-extensions`
/// decision 0007).
#[test]
fn draft1_index_record_installs_with_draft2_catalog() {
    let (temp, home, index) = setup("describe");
    let path = index.root.join("extensions/morphir-test.jsonl");
    let mut record: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    record["schemaVersion"] = "2.0.0-draft.1".into();
    let artifact = record["artifacts"][0].as_object_mut().unwrap();
    let mut claims = artifact.remove("claims").unwrap();
    let claims_object = claims.as_object_mut().unwrap();
    claims_object.remove("claimsVersion");
    claims_object.insert("statementVersion".into(), "0.1.0-draft.1".into());
    artifact.insert("statement".into(), claims);
    std::fs::write(&path, format!("{record}\n")).unwrap();

    let output = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local",
        ],
        &home,
        temp.path(),
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let catalog: serde_json::Value =
        serde_json::from_slice(&std::fs::read(home.join("catalog/extensions.json")).unwrap())
            .unwrap();
    let written = catalog.to_string();
    assert!(!written.contains("\"statement"), "{written}");
    let entry = &catalog["extensions"][0];
    assert_eq!(entry["claimCheck"], "probed");
    assert_eq!(entry["probeSource"], "describe");
    assert_eq!(entry["claims"]["claimsVersion"], "0.1.0-draft.2");
}

#[test]
fn session_fallback_records_probed_claims() {
    let (temp, home, _) = setup("fallback");
    let output = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local",
        ],
        &home,
        temp.path(),
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(installed(&home)["claimCheck"], "probed");
    assert_eq!(installed(&home)["probeSource"], "session-fallback");
}

#[test]
fn disagreement_and_probe_failure_leave_no_install_state() {
    for (mode, message, legacy) in [
        ("disagree", "capabilities.frontend.compile", false),
        ("fallback-disagree", "capabilities.frontend.compile", false),
        ("fallback-disagree", "capabilities.frontend.compile", true),
        ("fail", "probe", false),
    ] {
        let (temp, home, index) = setup(mode);
        if legacy {
            make_legacy(&index);
        }
        let output = run_morphir(
            &[
                "extension",
                "install",
                "morphir-test",
                "--repository",
                "local",
            ],
            &home,
            temp.path(),
        );
        assert!(!output.status.success(), "{mode} must refuse installation");
        assert!(
            String::from_utf8_lossy(&output.stderr).contains(message),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(!home.join("catalog/extensions.json").exists());
        assert!(!home.join("locks/extensions/morphir-test.json").exists());
        assert!(!home.join("locks/extensions.state.lock").exists());
        assert!(!home.join("store/extensions").exists());
        assert_eq!(std::fs::read_dir(home.join("tmp")).unwrap().count(), 0);
    }
}

#[test]
fn no_probe_does_not_run_guest_and_records_unchecked() {
    let (temp, home, _) = setup("fail");
    let output = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local",
            "--no-probe",
        ],
        &home,
        temp.path(),
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(installed(&home)["claimCheck"], "unchecked");
    assert!(installed(&home)["probeSource"].is_null());
    assert_eq!(
        String::from_utf8_lossy(&output.stderr)
            .matches("not checked")
            .count(),
        1
    );
}

#[test]
fn wasm_keeps_claims_unchecked() {
    let (temp, home, _) = setup("wasm");
    let output = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local",
        ],
        &home,
        temp.path(),
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(installed(&home)["claimCheck"], "unchecked");
}

#[test]
fn failed_probe_preserves_existing_catalog_locks_and_store() {
    let (temp, home, _) = setup("disagree");
    let other = write_test_index(
        &temp.path().join("other"),
        "other",
        "Other",
        "1.0.0",
        b"existing bytes",
    );
    assert!(
        add_test_repository("other", &other.root, &home, temp.path())
            .status
            .success()
    );
    let output = run_morphir(
        &[
            "extension",
            "install",
            "other",
            "--repository",
            "other",
            "--no-probe",
        ],
        &home,
        temp.path(),
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    fn snapshot(path: &std::path::Path) -> Vec<(PathBuf, Vec<u8>)> {
        let mut entries = vec![];
        for entry in std::fs::read_dir(path).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                entries.extend(snapshot(&path));
            } else {
                entries.push((path.clone(), std::fs::read(path).unwrap()));
            }
        }
        entries.sort();
        entries
    }
    let before = ["catalog", "locks/extensions", "store"].map(|path| snapshot(&home.join(path)));
    let output = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local",
        ],
        &home,
        temp.path(),
    );
    assert!(!output.status.success());
    let after = ["catalog", "locks/extensions", "store"].map(|path| snapshot(&home.join(path)));
    assert_eq!(before, after);
}

#[test]
fn no_probe_preserves_unknown_declared_members_and_clears_publisher_provenance() {
    let (temp, home, index) = setup("fail");
    let path = index.root.join("extensions/morphir-test.jsonl");
    let mut record: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    record["artifacts"][0]["claims"]["future"] = serde_json::json!({"preserve": true});
    record["artifacts"][0]["claimCheck"] = "probed".into();
    std::fs::write(path, format!("{record}\n")).unwrap();
    let output = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local",
            "--no-probe",
        ],
        &home,
        temp.path(),
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(installed(&home)["claimCheck"], "unchecked");
    assert_eq!(installed(&home)["claims"]["future"]["preserve"], true);
}

#[test]
fn fallback_preserves_the_full_declaration_and_keeps_lock_consistent() {
    let (temp, home, index) = setup("fallback");
    let path = index.root.join("extensions/morphir-test.jsonl");
    let mut record: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    let claims = &mut record["artifacts"][0]["claims"];
    claims["protocolVersions"] = serde_json::json!([MEP_VERSION, "future-protocol"]);
    claims["extension"]["types"] = serde_json::json!(["frontend", "validator"]);
    claims["capabilities"]["validator"] = serde_json::json!({"validate": true});
    claims["future"] = serde_json::json!({"preserve": true});
    let declared = claims.clone();
    std::fs::write(path, format!("{record}\n")).unwrap();
    let output = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local",
        ],
        &home,
        temp.path(),
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(installed(&home)["claims"], declared);
    let list = run_morphir(&["extension", "list"], &home, temp.path());
    assert!(
        list.status.success(),
        "{}",
        String::from_utf8_lossy(&list.stderr)
    );
    assert!(String::from_utf8_lossy(&list.stdout).contains("probed (session fallback)"));
}

#[test]
fn fallback_preserves_artifact_host_requirements_for_later_activation() {
    let (temp, home, index) = setup("fallback");
    let path = index.root.join("extensions/morphir-test.jsonl");
    let mut record: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    record["requires"] = serde_json::json!({"host": [format!("<={}", env!("CARGO_PKG_VERSION"))]});
    record["critical"] = serde_json::json!(["requires.host"]);
    record["artifacts"][0]["claims"]["requires"] =
        serde_json::json!({"host": [format!(">={}", env!("CARGO_PKG_VERSION"))]});
    record["artifacts"][0]["claims"]["critical"] = serde_json::json!(["requires.host"]);
    std::fs::write(path, format!("{record}\n")).unwrap();
    let output = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local",
        ],
        &home,
        temp.path(),
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let home =
        morphir_common::home::MorphirHome::resolve_from(Some(home.as_os_str()), None).unwrap();
    let catalog = morphir_distribution::InstalledCatalog::load(&home).unwrap();
    let id = morphir_distribution::ExtensionId::parse("morphir-test").unwrap();
    let entry = catalog.get(&id).unwrap();
    assert!(
        entry
            .check_host(&env!("CARGO_PKG_VERSION").parse().unwrap())
            .is_ok()
    );
    assert!(
        entry.check_host(&"99.0.0".parse().unwrap()).is_err(),
        "fallback must also retain release requirements"
    );
    assert!(
        entry.check_host(&"0.0.1".parse().unwrap()).is_err(),
        "fallback must retain the artifact's admission requirements"
    );
}

fn make_legacy(index: &TestIndex) {
    let path = index.root.join("extensions/morphir-test.jsonl");
    let mut record: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    record["schemaVersion"] = "1.0".into();
    record["artifacts"][0]
        .as_object_mut()
        .unwrap()
        .remove("claims");
    record["frontend"]
        .as_object_mut()
        .unwrap()
        .remove("incremental");
    record["frontend"]
        .as_object_mut()
        .unwrap()
        .remove("fragments");
    std::fs::write(path, format!("{record}\n")).unwrap();
}

/// An extension that answers `describe` reports members a version-1 record cannot express. The
/// host's converted claims carry defaults for those, so the answer is checked like a session, and
/// the install keeps the version-1 catalog shape (Elm extension 0.4.0 through a version-1 index).
#[test]
fn legacy_record_accepts_a_describe_answer_with_members_it_cannot_express() {
    let (temp, home, index) = setup("describe");
    make_legacy(&index);
    let output = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local",
        ],
        &home,
        temp.path(),
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let entry = installed(&home);
    for member in ["claims", "claimCheck", "probeSource"] {
        assert!(entry.get(member).is_none(), "{entry}");
    }
}

#[test]
fn legacy_probe_accepts_extra_session_members_and_keeps_old_catalog_shape() {
    check_legacy_catalog(false);
}

#[test]
fn legacy_no_probe_keeps_old_catalog_shape() {
    check_legacy_catalog(true);
}

fn check_legacy_catalog(no_probe: bool) {
    let (temp, home, index) = setup("fallback");
    make_legacy(&index);
    let mut args = vec![
        "extension",
        "install",
        "morphir-test",
        "--repository",
        "local",
    ];
    if no_probe {
        args.push("--no-probe");
    }
    let output = run_morphir(&args, &home, temp.path());
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let mut actual: serde_json::Value =
        serde_json::from_slice(&std::fs::read(home.join("catalog/extensions.json")).unwrap())
            .unwrap();
    let mut expected: serde_json::Value =
        serde_json::from_str(include_str!("../fixtures/extension-catalog-v1.json")).unwrap();
    expected["extensions"][0]["mepVersions"] = serde_json::json!([MEP_VERSION]);
    // Only machine-dependent values are normalized. All members and other values are frozen.
    let entry = &mut actual["extensions"][0];
    for pointer in [
        "/platform/os",
        "/platform/arch",
        "/digest",
        "/storePath",
        "/index/identity",
        "/index/revision",
    ] {
        *entry.pointer_mut(pointer).expect("old catalog member") =
            expected["extensions"][0].pointer(pointer).unwrap().clone();
    }
    assert_eq!(actual, expected);
    let list = run_morphir(&["extension", "list"], &home, temp.path());
    assert!(list.status.success());
    assert!(String::from_utf8_lossy(&list.stdout).contains("Claims: unchecked"));
}

#[test]
fn describe_and_bypass_store_identical_raw_declarations() {
    let mut bodies = vec![];
    for no_probe in [false, true] {
        let (temp, home, index) = setup("describe");
        let path = index.root.join("extensions/morphir-test.jsonl");
        let mut record: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        record["artifacts"][0]["claims"]["future"] = serde_json::json!({"raw": [1, true]});
        let declared = record["artifacts"][0]["claims"].clone();
        std::fs::write(path, format!("{record}\n")).unwrap();
        let mut args = vec![
            "extension",
            "install",
            "morphir-test",
            "--repository",
            "local",
        ];
        if no_probe {
            args.push("--no-probe");
        }
        let output = run_morphir(&args, &home, temp.path());
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let entry = installed(&home);
        assert_eq!(entry["claims"], declared);
        bodies.push(entry["claims"].clone());
    }
    assert_eq!(bodies[0], bodies[1]);
}

fn resolve(index: &TestIndex) -> morphir_distribution::ResolvedArtifact {
    use morphir_distribution::{Channel, ExtensionId, LocalIndex, Platform, Selection};
    LocalIndex::open(&index.root)
        .unwrap()
        .resolve(
            &ExtensionId::parse("morphir-test").unwrap(),
            Selection::Channel(Channel::Stable),
            &Platform::current(),
            &env!("CARGO_PKG_VERSION").parse().unwrap(),
        )
        .unwrap()
}

#[tokio::test]
async fn staging_is_private_under_home_and_removed_after_success_or_failure() {
    use morphir_distribution::{DistributionError, ExtensionInstaller};
    for succeeds in [false, true] {
        let (_temp, path, index) = setup("describe");
        let home =
            morphir_common::home::MorphirHome::resolve_from(Some(path.as_os_str()), None).unwrap();
        let result = ExtensionInstaller::new(&home)
            .install_with_probe(
                resolve(&index),
                &env!("CARGO_PKG_VERSION").parse().unwrap(),
                async |artifact| {
                    let staging_root = std::fs::canonicalize(home.temp_dir()).unwrap();
                    assert!(
                        artifact.path().starts_with(&staging_root),
                        "{}",
                        artifact.path().display()
                    );
                    let staging = artifact
                        .path()
                        .ancestors()
                        .find(|path| path.parent() == Some(staging_root.as_path()))
                        .unwrap();
                    #[cfg(unix)]
                    {
                        use std::os::unix::fs::PermissionsExt;
                        assert_eq!(
                            std::fs::metadata(staging).unwrap().permissions().mode() & 0o777,
                            0o700
                        );
                    }
                    if succeeds {
                        Ok(artifact.selected().artifact().declared_claims_record())
                    } else {
                        Err(DistributionError::Probe("injected refusal".into()))
                    }
                },
            )
            .await;
        assert_eq!(result.is_ok(), succeeds);
        assert_eq!(std::fs::read_dir(home.temp_dir()).unwrap().count(), 0);
    }
}

#[tokio::test]
async fn install_rechecks_catalog_after_a_competing_install_commits() {
    use morphir_distribution::ExtensionInstaller;
    let (_temp, path, index) = setup("describe");
    let home =
        morphir_common::home::MorphirHome::resolve_from(Some(path.as_os_str()), None).unwrap();
    let selected = resolve(&index);
    let host = env!("CARGO_PKG_VERSION").parse().unwrap();
    let mut committed = None;
    let result = ExtensionInstaller::new(&home)
        .install_with_probe(selected.clone(), &host, async |artifact| {
            // Both installs have resolved before the winner commits. No timing or sleeps required.
            ExtensionInstaller::new(&home)
                .install_with_probe(selected.clone(), &host, async |winner| {
                    Ok(winner.selected().artifact().declared_claims_record())
                })
                .await
                .unwrap();
            committed = Some(std::fs::read(home.extensions_catalog_file()).unwrap());
            Ok(artifact.selected().artifact().declared_claims_record())
        })
        .await;
    assert!(
        result.is_err(),
        "a competing install must not overwrite the winner"
    );
    assert!(
        result
            .unwrap_err()
            .to_string()
            .contains("already installed")
    );
    assert_eq!(
        std::fs::read(home.extensions_catalog_file()).unwrap(),
        committed.unwrap()
    );
    assert_eq!(std::fs::read_dir(home.temp_dir()).unwrap().count(), 0);
}
