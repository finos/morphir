//! Process bundle publication through real CLI subprocesses.
use super::*;
use morphir_distribution::{Channel, ExtensionId, LocalIndex, Platform, Selection, Sha256Digest};
use morphir_extension_sdk::protocol::MEP_VERSION;
use serde_json::{Value, json};

fn statement() -> Value {
    json!({
        "statementVersion": "0.1.0-draft.1", "protocolVersions": [MEP_VERSION],
        "extension": {"id": "morphir-avro", "name": "Morphir Avro", "version": "1.2.3", "types": ["backend"]},
        "capabilities": {"backend": {"targets": ["avro"], "irVersions": ["3"], "generate": true}}
    })
}

fn host_triple() -> String {
    let suffix = match std::env::consts::OS {
        "macos" => "apple-darwin",
        "linux" => "unknown-linux-gnu",
        other => panic!("unsupported test host {other}"),
    };
    format!("{}-{suffix}", std::env::consts::ARCH)
}

fn bundle(root: &std::path::Path, bytes: &[u8], declared: Value) -> PathBuf {
    let bundle = root.join("bundle");
    std::fs::create_dir_all(&bundle).unwrap();
    let other = if host_triple() == "x86_64-pc-windows-msvc" {
        "aarch64-apple-darwin"
    } else {
        "x86_64-pc-windows-msvc"
    };
    let artifacts: Vec<_> = [(host_triple(), "host-extension", bytes), (other.into(), "other-extension", b"foreign executable".as_slice())]
        .into_iter().map(|(platform, filename, bytes)| {
            let digest = Sha256Digest::of_bytes(bytes);
            std::fs::write(bundle.join(filename), bytes).unwrap();
            std::fs::write(bundle.join(format!("{filename}.sha256")), format!("{digest}  {filename}\n")).unwrap();
            json!({"platform": platform, "runtime": "process", "filename": filename, "sha256": digest, "statement": declared})
        }).collect();
    std::fs::write(bundle.join("release.json"), serde_json::to_vec(&json!({
        "schemaVersion": "2.0.0-draft.1", "extensionId": declared["extension"]["id"], "shortId": "avro",
        "version": declared["extension"]["version"], "platformDifferences": "none", "artifacts": artifacts
    })).unwrap()).unwrap();
    bundle
}

fn fixture() -> Vec<u8> {
    backend_process_script().replace(
        "if method == \"morphir.initialize\":",
        &format!("if method == \"morphir.extension.describe\":\n        result = json.loads({:?})\n    elif method == \"morphir.initialize\":", statement().to_string()),
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
    let bundle = bundle(temp.path(), &fixture(), statement());
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
    assert_eq!(record["artifacts"][0]["statementSource"], "probed");
    assert_eq!(record["artifacts"][0]["probeSource"], "describe");
    assert_eq!(record["artifacts"][1]["statementSource"], "declared");
    assert_eq!(record["artifacts"][1]["statement"], statement());
}

#[test]
fn process_bundle_refuses_digest_mismatch() {
    let temp = TempDir::new().unwrap();
    let bundle = bundle(temp.path(), &fixture(), statement());
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
    let mut declared = statement();
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
#[ignore = "requires MORPHIR_SCALA_ELM_EXTENSION_BIN pointing at the real 0.5.0-M08 executable"]
fn real_published_morphir_scala_elm_resolves_host() {
    use morphir_daemon::extensions::{ProcessLaunch, SpawnedProcessTransport};
    use morphir_extension_sdk::protocol::{InitializeParams, PeerInfo};
    let executable = std::env::var_os("MORPHIR_SCALA_ELM_EXTENSION_BIN")
        .map(PathBuf::from)
        .expect("set MORPHIR_SCALA_ELM_EXTENSION_BIN");
    let temp = TempDir::new().unwrap();
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let description = runtime.block_on(async {
        SpawnedProcessTransport::spawn(ProcessLaunch::new(
            "morphir-scala-elm",
            &executable,
            temp.path(),
        ))
        .await
        .unwrap()
        .describe(InitializeParams {
            protocol_versions: vec![MEP_VERSION.into()],
            host: PeerInfo {
                name: "morphir-cli".into(),
                version: env!("CARGO_PKG_VERSION").into(),
            },
        })
        .await
        .unwrap()
    });
    assert_eq!(description.statement.extension.version, "0.5.0-M08");
    let declared = serde_json::to_value(description.statement).unwrap();
    let bundle = bundle(
        temp.path(),
        &std::fs::read(executable).unwrap(),
        declared.clone(),
    );
    let output = publish(temp.path(), &bundle);
    assert!(output.status.success(), "{}", compacted_stderr(&output));
    let index = LocalIndex::open(temp.path().join("repository")).unwrap();
    let selected = index
        .resolve(
            &ExtensionId::parse("morphir-scala-elm").unwrap(),
            Selection::Exact("0.5.0-M08".parse().unwrap()),
            &Platform::current(),
            &env!("CARGO_PKG_VERSION").parse().unwrap(),
        )
        .unwrap();
    assert_eq!(
        serde_json::to_value(selected.artifact().statement().unwrap()).unwrap(),
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
    let mut declared = statement();
    declared["extension"]["types"] = json!(["backend", "workspace"]);
    declared["capabilities"]["workspace"] =
        json!({"discover": true, "protocolVersions": ["0.1.0-draft.1"]});
    declared["protocolVersions"] = json!([MEP_VERSION, "future"]);
    declared["requires"] = json!({"host": [">=0.1.0"]});
    declared["critical"] = json!(["requires.host"]);
    declared["future"] = json!({"retained": true});
    let script = backend_process_script()
        .replace("if method == \"morphir.initialize\":", "if method == \"morphir.extension.describe\":\n        result = {\"code\": -32601, \"message\": \"method not found\"}\n    elif method == \"morphir.initialize\":")
        .replace("elif method == \"morphir.backend.generate\":", &format!("elif method == \"morphir.initialized\":\n        continue\n    elif method == \"morphir.extension.capabilities\":\n        result = json.loads({:?})\n    elif method == \"morphir.backend.generate\":", statement()["capabilities"].to_string()))
        .replace("{\"jsonrpc\": \"2.0\", \"id\": identifier, \"result\": result}", "{\"jsonrpc\": \"2.0\", \"id\": identifier, (\"error\" if \"code\" in result else \"result\"): result}");
    let bundle = bundle(temp.path(), script.as_bytes(), declared.clone());
    let output = publish(temp.path(), &bundle);
    assert!(output.status.success(), "{}", compacted_stderr(&output));
    let record: Value = serde_json::from_slice(
        &std::fs::read(temp.path().join("repository/extensions/morphir-avro.jsonl")).unwrap(),
    )
    .unwrap();
    assert_eq!(record["artifacts"][0]["statement"], declared);
    assert_eq!(record["artifacts"][0]["statementSource"], "probed");
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
        let mut declared = statement();
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
