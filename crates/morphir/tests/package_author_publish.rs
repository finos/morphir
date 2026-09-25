//! Real-process checks for local Library authoring and publication.
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn source() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn morphir(directory: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_morphir"))
        .current_dir(directory)
        .env("MORPHIR_HOME", directory.join("home"))
        .env("MORPHIR_LOG_FILE", "false")
        .env_remove("MORPHIR_LOG_DIR")
        .env_remove("MORPHIR_OUT_DIR")
        .arg("--no-banner")
        .args(args)
        .output()
        .expect("Morphir runs")
}

#[test]
fn create_library_preserves_compiled_ir_and_refuses_overwrite() {
    let workspace = tempfile::tempdir().unwrap();
    let fixture = source().join("spec/package/mck/fixtures/two-libraries/eligibility");
    let input = workspace.path().join("authoring.json");
    std::fs::write(
        &input,
        r#"{"packagePath":"example.com/finance/eligibility","version":"1.2.0","dependencies":{},"exports":{"decision":"decision"}}"#,
    )
    .unwrap();
    let output = workspace.path().join("library");
    let ir = fixture.join("ir.json");
    let args = [
        "package",
        "create",
        "--ir",
        ir.to_str().unwrap(),
        "--manifest-input",
        input.to_str().unwrap(),
        "--output",
        output.to_str().unwrap(),
    ];
    let created = morphir(workspace.path(), &args);
    assert!(
        created.status.success(),
        "{}",
        String::from_utf8_lossy(&created.stderr)
    );
    assert_eq!(
        std::fs::read(output.join("ir.json")).unwrap(),
        std::fs::read(fixture.join("ir.json")).unwrap()
    );
    let manifest: serde_json::Value =
        serde_json::from_slice(&std::fs::read(output.join("manifest.json")).unwrap()).unwrap();
    assert_eq!(manifest["kind"], "Library");
    assert_eq!(manifest["ir"]["packageName"], "example/eligibility");

    let repeated = morphir(workspace.path(), &args);
    assert!(!repeated.status.success());
    assert_eq!(
        std::fs::read(output.join("ir.json")).unwrap(),
        std::fs::read(fixture.join("ir.json")).unwrap()
    );
}

#[test]
fn create_and_sign_library_with_inventoried_metadata_context() {
    use serde_json::json;

    let workspace = tempfile::tempdir().unwrap();
    let source = workspace.path().join("source");
    std::fs::create_dir_all(source.join("contexts")).unwrap();
    let context = br#"{"@context":{"operationalName":"morphir://ir/pkg/example/greeting?format=4.1.0#/module/greeting/value/operational-name"}}"#;
    std::fs::write(source.join("contexts/names.jsonld"), context).unwrap();
    let ir = json!({"formatVersion":"4.1.0","distribution":{"Library":{"packageName":"example/greeting","dependencies":{},"def":{"modules":{"greeting":{"Public":{"types":{},"values":{}}}}}}},
    "$meta":{"@context":"./contexts/names.jsonld","@graph":[{
        "@id":"morphir://ir/pkg/example/greeting?format=4.1.0#/module/greeting",
        "operationalName":"sayHello"
    }]}});
    std::fs::write(source.join("ir.json"), serde_json::to_vec(&ir).unwrap()).unwrap();
    let input = workspace.path().join("authoring.json");
    std::fs::write(
        &input,
        r#"{"packagePath":"example.com/greeting","version":"1.0.0","dependencies":{},"exports":{"greeting":"greeting"}}"#,
    )
    .unwrap();
    let bundle = workspace.path().join("bundle");
    let created = morphir(
        workspace.path(),
        &[
            "package",
            "create",
            "--ir",
            source.join("ir.json").to_str().unwrap(),
            "--context-root",
            source.to_str().unwrap(),
            "--manifest-input",
            input.to_str().unwrap(),
            "--output",
            bundle.to_str().unwrap(),
        ],
    );
    assert!(
        created.status.success(),
        "{}",
        String::from_utf8_lossy(&created.stderr)
    );
    assert_eq!(
        std::fs::read(bundle.join("contexts/names.jsonld")).unwrap(),
        context
    );
    let manifest: serde_json::Value =
        serde_json::from_slice(&std::fs::read(bundle.join("manifest.json")).unwrap()).unwrap();
    assert_eq!(manifest["formatVersion"], "0.1.0-draft.2");
    assert!(manifest["contextResources"]["contexts/names.jsonld"].is_object());

    let key = workspace.path().join("publisher.key");
    std::fs::write(&key, format!("{}\n", "11".repeat(32))).unwrap();
    let release = workspace.path().join("signed");
    let signed = morphir(
        workspace.path(),
        &[
            "package",
            "sign",
            "--bundle",
            bundle.to_str().unwrap(),
            "--key-file",
            key.to_str().unwrap(),
            "--output",
            release.to_str().unwrap(),
        ],
    );
    assert!(
        signed.status.success(),
        "{}",
        String::from_utf8_lossy(&signed.stderr)
    );
    assert!(release.join("record.json").is_file());

    #[cfg(target_os = "macos")]
    {
        use morphir_package::authoring::LocalSigningKey;
        use morphir_package::digest::Digest;

        let signing_key = LocalSigningKey::from_seed([0x11; 32]);
        let key_id = signing_key.tuf_key_id().unwrap();
        let role = json!({"keyids":[key_id.clone()],"threshold":1});
        let root = signing_key
            .sign_tuf(&json!({
                "_type":"root","spec_version":"1.0.36","version":1,
                "expires":"2099-01-01T00:00:00Z","consistent_snapshot":true,
                "keys":{key_id:signing_key.tuf_public_key()},
                "roles":{"root":role,"targets":role,"snapshot":role,"timestamp":role}
            }))
            .unwrap();
        let digest = Digest::of_bytes(&root).to_string();
        let policy = json!({"formatVersion":"0.1.0-draft.3","kind":"LibraryTrustPolicy",
            "repositories":[{"identity":digest,"bootstrapRoot":{"version":1,"digest":digest},"namespaces":["example.com"]}],
            "publisherRules":[{"namespace":"example.com","publicKeys":[signing_key.public_key_hex()],"threshold":1}],
            "continuedUse":"fresh-metadata"});
        let root_file = workspace.path().join("root.json");
        let policy_file = workspace.path().join("policy.json");
        std::fs::write(&root_file, root).unwrap();
        std::fs::write(&policy_file, serde_json::to_vec(&policy).unwrap()).unwrap();
        let registry = workspace.path().join("registry");
        let publisher_state = workspace.path().join("publisher-state");
        let draft = workspace.path().join("draft");
        let proposal = workspace.path().join("proposal.json");
        let consumer_state = workspace.path().join("consumer-state");
        let lock = workspace.path().join("consumer.lock");
        let restored = workspace.path().join("restored");
        let run = |args: &[&str]| {
            let output = morphir(workspace.path(), args);
            assert!(
                output.status.success(),
                "{args:?}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            output
        };
        run(&[
            "package",
            "registry",
            "init",
            "--policy",
            policy_file.to_str().unwrap(),
            "--root",
            root_file.to_str().unwrap(),
            "--registry",
            registry.to_str().unwrap(),
            "--publisher-state",
            publisher_state.to_str().unwrap(),
        ]);
        run(&[
            "package",
            "registry",
            "prepare",
            "--bundle",
            bundle.to_str().unwrap(),
            "--release",
            release.to_str().unwrap(),
            "--policy",
            policy_file.to_str().unwrap(),
            "--registry",
            registry.to_str().unwrap(),
            "--publisher-state",
            publisher_state.to_str().unwrap(),
            "--expires",
            "2098-01-01T00:00:00Z",
            "--output",
            draft.to_str().unwrap(),
        ]);
        run(&[
            "package",
            "registry",
            "sign-proposal",
            "--draft",
            draft.join("draft.json").to_str().unwrap(),
            "--targets-key-file",
            key.to_str().unwrap(),
            "--snapshot-key-file",
            key.to_str().unwrap(),
            "--timestamp-key-file",
            key.to_str().unwrap(),
            "--output",
            proposal.to_str().unwrap(),
        ]);
        run(&[
            "package",
            "publish",
            "--bundle",
            bundle.to_str().unwrap(),
            "--release",
            release.to_str().unwrap(),
            "--predecessor",
            draft.join("predecessor.json").to_str().unwrap(),
            "--proposal",
            proposal.to_str().unwrap(),
            "--policy",
            policy_file.to_str().unwrap(),
            "--registry",
            registry.to_str().unwrap(),
            "--publisher-state",
            publisher_state.to_str().unwrap(),
        ]);
        run(&[
            "package",
            "trust",
            "init",
            "--policy",
            policy_file.to_str().unwrap(),
            "--root",
            root_file.to_str().unwrap(),
            "--state",
            consumer_state.to_str().unwrap(),
        ]);
        run(&[
            "package",
            "resolve",
            "--root",
            "example.com/greeting@1.0.0",
            "--policy",
            policy_file.to_str().unwrap(),
            "--registry",
            registry.to_str().unwrap(),
            "--state",
            consumer_state.to_str().unwrap(),
            "--output",
            lock.to_str().unwrap(),
            "--assurance",
            "portable",
        ]);
        run(&[
            "package",
            "restore",
            "--policy",
            policy_file.to_str().unwrap(),
            "--lock",
            lock.to_str().unwrap(),
            "--registry",
            registry.to_str().unwrap(),
            "--state",
            consumer_state.to_str().unwrap(),
            "--output",
            restored.to_str().unwrap(),
            "--assurance",
            "portable",
        ]);
        let installed = restored.join("example.com/greeting/1.0.0");
        assert_eq!(
            std::fs::read(installed.join("contexts/names.jsonld")).unwrap(),
            context
        );
        let queried = run(&[
            "metadata",
            "query",
            "--ir",
            installed.join("ir.json").to_str().unwrap(),
        ]);
        let result: serde_json::Value = serde_json::from_slice(&queried.stdout).unwrap();
        assert_eq!(result["facts"][0]["object"]["@value"], "sayHello");
        assert_eq!(result["semanticStatus"], "unvalidated");
    }

    std::fs::write(bundle.join("contexts/names.jsonld"), b"changed").unwrap();
    let rejected_release = workspace.path().join("rejected-release");
    let rejected = morphir(
        workspace.path(),
        &[
            "package",
            "sign",
            "--bundle",
            bundle.to_str().unwrap(),
            "--key-file",
            key.to_str().unwrap(),
            "--output",
            rejected_release.to_str().unwrap(),
        ],
    );
    assert!(!rejected.status.success());
    assert!(!rejected_release.exists());

    std::fs::remove_file(source.join("contexts/names.jsonld")).unwrap();
    let missing_bundle = workspace.path().join("missing-bundle");
    let missing = morphir(
        workspace.path(),
        &[
            "package",
            "create",
            "--ir",
            source.join("ir.json").to_str().unwrap(),
            "--context-root",
            source.to_str().unwrap(),
            "--manifest-input",
            input.to_str().unwrap(),
            "--output",
            missing_bundle.to_str().unwrap(),
        ],
    );
    assert!(!missing.status.success());
    assert!(!missing_bundle.exists());
}

#[test]
fn create_rejects_dependencies_without_publishing_a_partial_bundle() {
    let workspace = tempfile::tempdir().unwrap();
    let ir = source().join("spec/package/mck/fixtures/two-libraries/eligibility/ir.json");
    let input = workspace.path().join("authoring.json");
    std::fs::write(
        &input,
        r#"{"packagePath":"example.com/finance/eligibility","version":"1.2.0","dependencies":{"other":"1.0.0"},"exports":{"decision":"decision"}}"#,
    )
    .unwrap();
    let output = workspace.path().join("library");
    let rejected = morphir(
        workspace.path(),
        &[
            "package",
            "create",
            "--ir",
            ir.to_str().unwrap(),
            "--manifest-input",
            input.to_str().unwrap(),
            "--output",
            output.to_str().unwrap(),
        ],
    );
    assert!(!rejected.status.success());
    assert!(!output.exists());
}

#[test]
fn sign_bundle_writes_public_artifacts_without_copying_the_key() {
    let workspace = tempfile::tempdir().unwrap();
    let bundle = source().join("spec/package/mck/fixtures/two-libraries/eligibility");
    let key = workspace.path().join("publisher.key");
    std::fs::write(&key, format!("{}\n", "11".repeat(32))).unwrap();
    let output = workspace.path().join("signed");
    let signed = morphir(
        workspace.path(),
        &[
            "package",
            "sign",
            "--bundle",
            bundle.to_str().unwrap(),
            "--key-file",
            key.to_str().unwrap(),
            "--output",
            output.to_str().unwrap(),
        ],
    );
    assert!(
        signed.status.success(),
        "{}",
        String::from_utf8_lossy(&signed.stderr)
    );
    let record: serde_json::Value =
        serde_json::from_slice(&std::fs::read(output.join("record.json")).unwrap()).unwrap();
    let envelope: serde_json::Value =
        serde_json::from_slice(&std::fs::read(output.join("envelope.json")).unwrap()).unwrap();
    assert_eq!(record["kind"], "LibraryRegistryRecord");
    assert_eq!(envelope["signatures"].as_array().unwrap().len(), 1);
    let entries = std::fs::read_dir(&output)
        .unwrap()
        .map(|entry| entry.unwrap().file_name())
        .collect::<Vec<_>>();
    assert_eq!(entries.len(), 2);
    assert!(!output.join("publisher.key").exists());
}

#[test]
fn sign_rejects_invalid_key_or_extra_bundle_file_without_output() {
    let workspace = tempfile::tempdir().unwrap();
    let bundle = workspace.path().join("bundle");
    std::fs::create_dir(&bundle).unwrap();
    let fixture = source().join("spec/package/mck/fixtures/two-libraries/eligibility");
    for file in ["manifest.json", "ir.json"] {
        std::fs::copy(fixture.join(file), bundle.join(file)).unwrap();
    }
    let key = workspace.path().join("publisher.key");
    std::fs::write(&key, "not-a-key\n").unwrap();
    let output = workspace.path().join("signed");
    let args = [
        "package",
        "sign",
        "--bundle",
        bundle.to_str().unwrap(),
        "--key-file",
        key.to_str().unwrap(),
        "--output",
        output.to_str().unwrap(),
    ];
    let invalid_key = morphir(workspace.path(), &args);
    assert!(!invalid_key.status.success());
    assert!(!output.exists());

    std::fs::write(&key, format!("{}\n", "11".repeat(32))).unwrap();
    std::fs::write(bundle.join("unlisted.json"), "{}").unwrap();
    let extra_file = morphir(workspace.path(), &args);
    assert!(!extra_file.status.success());
    assert!(!output.exists());
}

#[test]
fn registry_key_info_and_sign_metadata_require_explicit_key() {
    use serde_json::json;

    let workspace = tempfile::tempdir().unwrap();
    let key_file = workspace.path().join("operator.key");
    std::fs::write(&key_file, format!("{}\n", "15".repeat(32))).unwrap();
    let info = morphir(
        workspace.path(),
        &[
            "package",
            "registry",
            "key-info",
            "--key-file",
            key_file.to_str().unwrap(),
            "--json",
        ],
    );
    assert!(
        info.status.success(),
        "{}",
        String::from_utf8_lossy(&info.stderr)
    );
    let key: serde_json::Value = serde_json::from_slice(&info.stdout).unwrap();
    let id = key["keyId"].as_str().unwrap();
    let role = json!({"keyids":[id],"threshold":1});
    let unsigned = workspace.path().join("unsigned-root.json");
    std::fs::write(
        &unsigned,
        serde_json::to_vec(&json!({
            "_type":"root","spec_version":"1.0.36","version":1,
            "expires":"2099-01-01T00:00:00Z","consistent_snapshot":true,
            "keys":{(id):key["tufKey"]},
            "roles":{"root":role,"targets":role,"snapshot":role,"timestamp":role}
        }))
        .unwrap(),
    )
    .unwrap();
    let root = workspace.path().join("root.json");
    let signed = morphir(
        workspace.path(),
        &[
            "package",
            "registry",
            "sign-metadata",
            "--input",
            unsigned.to_str().unwrap(),
            "--key-file",
            key_file.to_str().unwrap(),
            "--output",
            root.to_str().unwrap(),
        ],
    );
    assert!(
        signed.status.success(),
        "{}",
        String::from_utf8_lossy(&signed.stderr)
    );
    let root: serde_json::Value = serde_json::from_slice(&std::fs::read(root).unwrap()).unwrap();
    assert_eq!(root["signed"]["_type"], "root");
    assert_eq!(root["signatures"][0]["keyid"], id);
}

#[cfg(target_os = "macos")]
#[test]
fn local_registry_cli_publishes_signed_library_from_an_absent_registry() {
    use morphir_package::digest::Digest;
    use serde_json::json;

    let workspace = tempfile::tempdir().unwrap();
    let base = workspace.path().canonicalize().unwrap();
    let make_key = |name: &str, byte: &str| {
        let path = base.join(format!("{name}.key"));
        std::fs::write(&path, format!("{}\n", byte.repeat(32))).unwrap();
        let info = morphir(
            &base,
            &[
                "package",
                "registry",
                "key-info",
                "--key-file",
                path.to_str().unwrap(),
                "--json",
            ],
        );
        assert!(
            info.status.success(),
            "{name}: {}",
            String::from_utf8_lossy(&info.stderr)
        );
        (
            path,
            serde_json::from_slice::<serde_json::Value>(&info.stdout).unwrap(),
        )
    };
    let (publisher_key, publisher_info) = make_key("publisher", "11");
    let (root_key, root_info) = make_key("root", "22");
    let (targets_key, targets_info) = make_key("targets", "33");
    let (snapshot_key, snapshot_info) = make_key("snapshot", "44");
    let (timestamp_key, timestamp_info) = make_key("timestamp", "55");
    let role = |key: &serde_json::Value| json!({"keyids":[key["keyId"]],"threshold":1});
    let root_id = root_info["keyId"].as_str().unwrap();
    let targets_id = targets_info["keyId"].as_str().unwrap();
    let snapshot_id = snapshot_info["keyId"].as_str().unwrap();
    let timestamp_id = timestamp_info["keyId"].as_str().unwrap();
    let unsigned_root = base.join("unsigned-root.json");
    std::fs::write(
        &unsigned_root,
        serde_json::to_vec(&json!({
            "_type":"root","spec_version":"1.0.36","version":1,
            "expires":"2099-01-01T00:00:00Z","consistent_snapshot":true,
            "keys":{
                (root_id):root_info["tufKey"],
                (targets_id):targets_info["tufKey"],
                (snapshot_id):snapshot_info["tufKey"],
                (timestamp_id):timestamp_info["tufKey"]
            },
            "roles":{
                "root":role(&root_info),
                "targets":role(&targets_info),
                "snapshot":role(&snapshot_info),
                "timestamp":role(&timestamp_info)
            }
        }))
        .unwrap(),
    )
    .unwrap();
    let root_file = base.join("root.json");
    let signed_root = morphir(
        &base,
        &[
            "package",
            "registry",
            "sign-metadata",
            "--input",
            unsigned_root.to_str().unwrap(),
            "--key-file",
            root_key.to_str().unwrap(),
            "--output",
            root_file.to_str().unwrap(),
        ],
    );
    assert!(
        signed_root.status.success(),
        "{}",
        String::from_utf8_lossy(&signed_root.stderr)
    );
    let root = std::fs::read(&root_file).unwrap();
    let root_digest = Digest::of_bytes(&root).to_string();
    let policy = json!({"formatVersion":"0.1.0-draft.3","kind":"LibraryTrustPolicy",
        "repositories":[{"identity":root_digest,"bootstrapRoot":{"version":1,"digest":root_digest},"namespaces":["example.com"]}],
        "publisherRules":[{"namespace":"example.com","publicKeys":[publisher_info["publicKey"]],"threshold":1}],
        "continuedUse":"fresh-metadata"});
    let policy_file = base.join("policy.json");
    std::fs::write(&policy_file, serde_json::to_vec(&policy).unwrap()).unwrap();

    let author = base.join("author");
    std::fs::create_dir(&author).unwrap();
    std::fs::create_dir(author.join("src")).unwrap();
    std::fs::copy(
        source().join("examples/package/local-library-publish/morphir.toml"),
        author.join("morphir.toml"),
    )
    .unwrap();
    std::fs::copy(
        source().join("examples/package/local-library-publish/src/main.gleam"),
        author.join("src/main.gleam"),
    )
    .unwrap();
    let compiled_ir = author.join("compiled/morphir-ir.json");
    let compiled = morphir(
        &author,
        &[
            "compile",
            "--ir-version",
            "4",
            "--output",
            "compiled",
            "--json",
        ],
    );
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    assert!(compiled_ir.exists());
    let input = base.join("authoring.json");
    std::fs::copy(
        source().join("examples/package/local-library-publish/authoring.json"),
        &input,
    )
    .unwrap();
    let bundle = base.join("bundle");
    let signed = base.join("signed");
    let registry = base.join("registry");
    let state = base.join("publisher-state");
    let draft = base.join("draft");
    let proposal = base.join("proposal.json");
    let ir = compiled_ir;
    let draft_json = draft.join("draft.json");
    let predecessor_json = draft.join("predecessor.json");

    let run = |args: &[&str]| {
        let output = morphir(&base, args);
        assert!(
            output.status.success(),
            "{args:?}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    };
    run(&[
        "package",
        "create",
        "--ir",
        ir.to_str().unwrap(),
        "--manifest-input",
        input.to_str().unwrap(),
        "--output",
        bundle.to_str().unwrap(),
    ]);
    run(&[
        "package",
        "sign",
        "--bundle",
        bundle.to_str().unwrap(),
        "--key-file",
        publisher_key.to_str().unwrap(),
        "--output",
        signed.to_str().unwrap(),
    ]);
    run(&[
        "package",
        "registry",
        "init",
        "--policy",
        policy_file.to_str().unwrap(),
        "--root",
        root_file.to_str().unwrap(),
        "--registry",
        registry.to_str().unwrap(),
        "--publisher-state",
        state.to_str().unwrap(),
    ]);
    run(&[
        "package",
        "registry",
        "prepare",
        "--bundle",
        bundle.to_str().unwrap(),
        "--release",
        signed.to_str().unwrap(),
        "--policy",
        policy_file.to_str().unwrap(),
        "--registry",
        registry.to_str().unwrap(),
        "--publisher-state",
        state.to_str().unwrap(),
        "--expires",
        "2098-01-01T00:00:00Z",
        "--output",
        draft.to_str().unwrap(),
    ]);
    run(&[
        "package",
        "registry",
        "sign-proposal",
        "--draft",
        draft_json.to_str().unwrap(),
        "--targets-key-file",
        targets_key.to_str().unwrap(),
        "--snapshot-key-file",
        snapshot_key.to_str().unwrap(),
        "--timestamp-key-file",
        timestamp_key.to_str().unwrap(),
        "--output",
        proposal.to_str().unwrap(),
    ]);
    run(&[
        "package",
        "publish",
        "--bundle",
        bundle.to_str().unwrap(),
        "--release",
        signed.to_str().unwrap(),
        "--predecessor",
        predecessor_json.to_str().unwrap(),
        "--proposal",
        proposal.to_str().unwrap(),
        "--policy",
        policy_file.to_str().unwrap(),
        "--registry",
        registry.to_str().unwrap(),
        "--publisher-state",
        state.to_str().unwrap(),
    ]);
    let timestamp: serde_json::Value =
        serde_json::from_slice(&std::fs::read(registry.join("metadata/timestamp.json")).unwrap())
            .unwrap();
    assert_eq!(timestamp["signed"]["version"], 1);

    let consumer = base.join("consumer");
    std::fs::create_dir(&consumer).unwrap();
    let consumer_state = consumer.join("trust-state");
    let lock = consumer.join("morphir.lock");
    let restored = consumer.join("libraries");
    run(&[
        "package",
        "trust",
        "init",
        "--policy",
        policy_file.to_str().unwrap(),
        "--root",
        root_file.to_str().unwrap(),
        "--state",
        consumer_state.to_str().unwrap(),
    ]);
    run(&[
        "package",
        "resolve",
        "--root",
        "example.com/finance/hello@1.0.0",
        "--policy",
        policy_file.to_str().unwrap(),
        "--registry",
        registry.to_str().unwrap(),
        "--state",
        consumer_state.to_str().unwrap(),
        "--output",
        lock.to_str().unwrap(),
        "--assurance",
        "portable",
    ]);
    run(&[
        "package",
        "restore",
        "--policy",
        policy_file.to_str().unwrap(),
        "--lock",
        lock.to_str().unwrap(),
        "--registry",
        registry.to_str().unwrap(),
        "--state",
        consumer_state.to_str().unwrap(),
        "--output",
        restored.to_str().unwrap(),
        "--assurance",
        "portable",
    ]);
    let restored_ir = restored.join("example.com/finance/hello/1.0.0/ir.json");
    assert_eq!(
        std::fs::read(&restored_ir).unwrap(),
        std::fs::read(&ir).unwrap()
    );
    let config = consumer.join("morphir.toml");
    std::fs::copy(
        source().join("examples/package/local-library-publish/consumer/morphir.toml"),
        &config,
    )
    .unwrap();
    let generated = consumer.join("generated");
    let compiled = consumer.join("compiled");
    run(&[
        "gleam",
        "--json",
        "generate",
        "--config",
        config.to_str().unwrap(),
        "--input",
        restored_ir.to_str().unwrap(),
        "--output",
        generated.to_str().unwrap(),
    ]);
    assert!(generated.join("main.gleam").exists());
    run(&[
        "gleam",
        "--json",
        "compile",
        "--config",
        config.to_str().unwrap(),
        "--input",
        generated.to_str().unwrap(),
        "--output",
        compiled.to_str().unwrap(),
    ]);
}
