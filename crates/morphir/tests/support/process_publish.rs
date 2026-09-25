//! Process bundle publication through real CLI subprocesses.
use super::*;
use morphir_distribution::{Channel, ExtensionId, LocalIndex, Platform, Selection, Sha256Digest};
use morphir_extension_sdk::protocol::MEP_VERSION;
use serde_json::{Value, json};

fn claim_set() -> Value {
    json!({
        "claimsVersion": "0.1.0-draft.2", "protocolVersions": [MEP_VERSION],
        "extension": {"id": "morphir-avro", "name": "Morphir Avro", "version": "1.2.3", "types": ["backend"]},
        "capabilities": {"backend": {"targets": ["avro"], "irVersions": ["3"], "generate": true}}
    })
}

#[path = "process_bundle.rs"]
mod process_bundle;
use process_bundle::host_triple;

fn bundle(root: &std::path::Path, bytes: &[u8], declared: Value) -> PathBuf {
    process_bundle::write_bundle(
        root,
        declared,
        "avro",
        &[
            (&host_triple(), "host-extension", bytes),
            (
                "x86_64-pc-windows-msvc",
                "other-extension",
                b"foreign executable",
            ),
        ],
    )
}

fn fixture() -> Vec<u8> {
    backend_process_script().replace(
        "if method == \"morphir.initialize\":",
        &format!("if method == \"morphir.extension.describe\":\n        result = json.loads({:?})\n    elif method == \"morphir.initialize\":", claim_set().to_string()),
    ).into_bytes()
}

fn publish(root: &std::path::Path, bundle: &std::path::Path) -> std::process::Output {
    let home = root.join("home");
    let repository = root.join("repository");
    morphir_distribution::LocalExtensionRepository::init(&repository).unwrap();
    assert!(
        add_test_repository("local", &repository, &home, root)
            .status
            .success()
    );
    run_morphir(
        &[
            "extension",
            "repository",
            "publish",
            "local",
            "--bundle",
            bundle.to_str().unwrap(),
        ],
        &home,
        root,
    )
}

#[test]
fn process_bundle_publishes_and_resolves_host() {
    let temp = TempDir::new().unwrap();
    let bundle = bundle(temp.path(), &fixture(), claim_set());
    let output = publish(temp.path(), &bundle);
    assert!(output.status.success(), "{}", compacted_stderr(&output));
    let index = LocalIndex::open(temp.path().join("repository")).unwrap();
    let resolved = index
        .resolve(
            &ExtensionId::parse("morphir-avro").unwrap(),
            Selection::Channel(Channel::Stable),
            &Platform::current(),
            &"1.0.0".parse().unwrap(),
        )
        .unwrap();
    assert_eq!(resolved.artifact().filename().as_str(), "host-extension");
    let record: Value = serde_json::from_slice(
        &std::fs::read(temp.path().join("repository/extensions/morphir-avro.jsonl")).unwrap(),
    )
    .unwrap();
    assert_eq!(record["artifacts"][0]["claimCheck"], "probed");
    assert_eq!(record["artifacts"][0]["probeSource"], "describe");
    assert_eq!(record["artifacts"][1]["claimCheck"], "unchecked");
    assert_eq!(record["artifacts"][1]["claims"], claim_set());
}

#[test]
fn process_bundle_refuses_digest_mismatch() {
    let temp = TempDir::new().unwrap();
    let bundle = bundle(temp.path(), &fixture(), claim_set());
    std::fs::write(bundle.join("other-extension"), b"tampered").unwrap();
    let output = publish(temp.path(), &bundle);
    assert!(!output.status.success());
    let error = compacted_stderr(&output);
    assert!(
        error.contains("digestmismatch") && error.contains("other-extension"),
        "{error}"
    );
    assert!(
        !temp
            .path()
            .join("repository/extensions/morphir-avro.jsonl")
            .exists()
    );
}

#[test]
fn process_bundle_refuses_describe_disagreement() {
    let temp = TempDir::new().unwrap();
    let mut declared = claim_set();
    declared["capabilities"]["backend"]["generate"] = json!(false);
    let bundle = bundle(temp.path(), &fixture(), declared);
    let output = publish(temp.path(), &bundle);
    assert!(!output.status.success());
    assert!(
        compacted_stderr(&output).contains("capabilities.backend.generate"),
        "{}",
        compacted_stderr(&output)
    );
    assert!(
        !temp
            .path()
            .join("repository/extensions/morphir-avro.jsonl")
            .exists()
    );
}

#[test]
#[ignore = "requires MORPHIR_SCALA_ELM_EXTENSION_BIN and MORPHIR_SCALA_ELM_EXTENSION_VERSION for a real executable"]
fn real_published_morphir_scala_elm_resolves_host() {
    let executable = std::env::var_os("MORPHIR_SCALA_ELM_EXTENSION_BIN")
        .map(PathBuf::from)
        .expect("set MORPHIR_SCALA_ELM_EXTENSION_BIN");
    let version = std::env::var("MORPHIR_SCALA_ELM_EXTENSION_VERSION")
        .expect("set MORPHIR_SCALA_ELM_EXTENSION_VERSION to the executable's version");
    let temp = TempDir::new().unwrap();
    let bundle = process_bundle::from_executable(
        &temp.path().join("scratch"),
        &executable,
        "morphir-scala-elm",
        "scala-elm",
        &version,
    );
    let descriptor: Value =
        serde_json::from_slice(&std::fs::read(bundle.join("release.json")).unwrap()).unwrap();
    let declared = descriptor["artifacts"][0]["claims"].clone();
    let output = publish(temp.path(), &bundle);
    assert!(output.status.success(), "{}", compacted_stderr(&output));
    let index = LocalIndex::open(temp.path().join("repository")).unwrap();
    let selected = index
        .resolve(
            &ExtensionId::parse("morphir-scala-elm").unwrap(),
            Selection::Exact(version.parse().unwrap()),
            &Platform::current(),
            &env!("CARGO_PKG_VERSION").parse().unwrap(),
        )
        .unwrap();
    assert_eq!(
        serde_json::to_value(selected.artifact().claims().unwrap()).unwrap(),
        declared
    );
    assert_eq!(
        selected.artifact().digest(),
        &Sha256Digest::of_bytes(&std::fs::read(bundle.join("host-extension")).unwrap())
    );
}

#[test]
fn wasm_bundle_keeps_version_one_index_output() {
    let temp = TempDir::new().unwrap();
    let bundle = write_test_release_bundle(temp.path());
    let output = publish(temp.path(), &bundle);
    assert!(output.status.success(), "{}", compacted_stderr(&output));
    let actual: Value = serde_json::from_slice(
        &std::fs::read(temp.path().join("repository/extensions/morphir-avro.jsonl")).unwrap(),
    )
    .unwrap();
    assert_eq!(
        actual,
        json!({
            "schemaVersion": "1.0", "id": "morphir-avro", "name": "Morphir Avro", "version": "0.1.0",
            "channels": ["stable"], "mepVersions": [MEP_VERSION], "capabilities": ["backend"],
            "backend": {"targets": ["avro"], "irVersions": ["3"], "generate": true},
            "artifacts": [{"runtime": "wasm", "filename": "morphir-avro.wasm", "sha256": Sha256Digest::of_bytes(b"verified avro wasm bytes"),
                "source": {"kind": "local-file", "path": "artifacts/morphir-avro.wasm"}, "args": [], "executable": false}]
        })
    );
}

#[test]
fn process_bundle_accepts_an_agreeing_session_fallback() {
    let temp = TempDir::new().unwrap();
    let mut declared = claim_set();
    declared["extension"]["types"] = json!(["backend", "workspace"]);
    declared["capabilities"]["workspace"] =
        json!({"discover": true, "protocolVersions": ["0.1.0-draft.1"]});
    declared["protocolVersions"] = json!([MEP_VERSION, "future"]);
    declared["requires"] = json!({"host": [">=0.1.0"]});
    declared["critical"] = json!(["requires.host"]);
    declared["future"] = json!({"retained": true});
    let script = backend_process_script()
        .replace("if method == \"morphir.initialize\":", "if method == \"morphir.extension.describe\":\n        result = {\"code\": -32601, \"message\": \"method not found\"}\n    elif method == \"morphir.initialize\":")
        .replace("elif method == \"morphir.backend.generate\":", &format!("elif method == \"morphir.initialized\":\n        continue\n    elif method == \"morphir.extension.capabilities\":\n        result = json.loads({:?})\n    elif method == \"morphir.backend.generate\":", claim_set()["capabilities"].to_string()))
        .replace("{\"jsonrpc\": \"2.0\", \"id\": identifier, \"result\": result}", "{\"jsonrpc\": \"2.0\", \"id\": identifier, (\"error\" if \"code\" in result else \"result\"): result}");
    let bundle = bundle(temp.path(), script.as_bytes(), declared.clone());
    let output = publish(temp.path(), &bundle);
    assert!(output.status.success(), "{}", compacted_stderr(&output));
    let record: Value = serde_json::from_slice(
        &std::fs::read(temp.path().join("repository/extensions/morphir-avro.jsonl")).unwrap(),
    )
    .unwrap();
    assert_eq!(record["artifacts"][0]["claims"], declared);
    assert_eq!(record["artifacts"][0]["claimCheck"], "probed");
    assert_eq!(record["artifacts"][0]["probeSource"], "session-fallback");
}

#[test]
fn process_publication_stages_privately_under_home_and_cleans_up() {
    for succeeds in [true, false] {
        let temp = TempDir::new().unwrap();
        let observation = temp.path().join("staging.json");
        let script = String::from_utf8(fixture()).unwrap().replace(
            "import json",
            &format!("import os, pathlib, stat\npathlib.Path({:?}).write_text(__import__('json').dumps({{'path': os.getcwd(), 'mode': stat.S_IMODE(os.stat('.').st_mode)}}))\nimport json", observation.to_str().unwrap()),
        );
        let mut declared = claim_set();
        if !succeeds {
            declared["capabilities"]["backend"]["generate"] = json!(false);
        }
        let bundle = bundle(temp.path(), script.as_bytes(), declared);
        let output = publish(temp.path(), &bundle);
        assert_eq!(
            output.status.success(),
            succeeds,
            "{}",
            compacted_stderr(&output)
        );
        let observed: Value = serde_json::from_slice(&std::fs::read(observation).unwrap()).unwrap();
        let stage = PathBuf::from(observed["path"].as_str().unwrap());
        let home = std::fs::canonicalize(temp.path().join("home")).unwrap();
        assert!(stage.starts_with(home.join("tmp")), "{}", stage.display());
        assert_eq!(observed["mode"], 0o700);
        assert!(!stage.exists());
    }
}
