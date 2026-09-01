//! Shared fixture machinery for CLI backend-extension end-to-end tests.
//!
//! `generate_extension.rs` (Avro) and `generate_json_schema.rs`
//! (morphir-openapi) both build a release WASM guest, write a schema-v2
//! local extension index, install it into an isolated `MORPHIR_HOME`, and
//! run the `morphir` CLI against it. This module holds the parts that are
//! identical between the two suites: the index record, the isolated
//! project/home/index fixture, and the shared IR fixtures.
//!
//! Cargo compiles this module afresh into each `tests/*.rs` binary that
//! includes it via `#[path = "support/mod.rs"]`, so an item one suite does
//! not call reads as dead code to that binary alone.
#![allow(dead_code)]

use morphir_distribution::Sha256Digest;
use serde_json::{Value, json};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use tempfile::TempDir;

/// Drives the `morphir` CLI against an isolated project, home, and
/// extension index with one backend extension installed.
pub struct CliMother {
    _root: TempDir,
    pub project: PathBuf,
    home: PathBuf,
    index: PathBuf,
    extension_id: &'static str,
}

impl CliMother {
    /// Build a fixture that, once installed, serves `backend` under
    /// `extension_id` from the release guest at `guest_path`.
    pub fn new(
        extension_id: &'static str,
        artifact_name: &str,
        name: &str,
        backend: Value,
        guest_path: impl AsRef<Path>,
    ) -> Self {
        let guest_path = guest_path.as_ref();
        let bytes = fs::read(guest_path).unwrap_or_else(|error| {
            panic!(
                "the release WASM guest must exist at {}: {error}",
                guest_path.display()
            )
        });
        let root = tempfile::tempdir().expect("fixture root should be created");
        let project = root.path().join("project");
        let home = root.path().join("home");
        let index = root.path().join("index");
        fs::create_dir_all(&project).expect("fixture project should be created");
        write_wasm_index(&index, extension_id, name, backend, artifact_name, &bytes);

        Self {
            _root: root,
            project,
            home,
            index,
            extension_id,
        }
    }

    pub fn write_config(&self, config: &str) -> PathBuf {
        let path = self.project.join("morphir.toml");
        fs::write(&path, config).expect("fixture config should be written");
        path
    }

    pub fn write_ir(&self, name: &str, ir: &Value) -> PathBuf {
        let path = self.project.join(name);
        fs::write(&path, serde_json::to_vec(ir).unwrap()).expect("fixture IR should be written");
        path
    }

    pub fn install_verified_wasm(&self) {
        let output = self.run(&[
            "extension",
            "install",
            self.extension_id,
            "--index",
            self.index.to_str().unwrap(),
        ]);
        assert_success(&output, "install release WASM guest");
    }

    pub fn run(&self, arguments: &[&str]) -> Output {
        Command::new(env!("CARGO_BIN_EXE_morphir"))
            .args(arguments)
            .env("MORPHIR_HOME", &self.home)
            .current_dir(&self.project)
            .output()
            .expect("morphir CLI should start")
    }
}

pub fn write_wasm_index(
    index: &Path,
    id: &str,
    name: &str,
    backend: Value,
    artifact_name: &str,
    bytes: &[u8],
) {
    let relative_source = format!("artifacts/{artifact_name}");
    let artifact_path = index.join(&relative_source);
    fs::create_dir_all(artifact_path.parent().unwrap()).unwrap();
    fs::create_dir_all(index.join("extensions")).unwrap();
    fs::write(&artifact_path, bytes).unwrap();
    let digest = Sha256Digest::of_bytes(bytes);
    let record = json!({
        "schemaVersion": 2,
        "id": id,
        "name": name,
        "version": "0.1.0",
        "channels": ["stable"],
        "mepVersions": ["0.1"],
        "capabilities": ["backend"],
        "backend": backend,
        "artifacts": [{
            "runtime": "wasm",
            "source": { "kind": "local-file", "path": relative_source },
            "sha256": digest,
            "filename": artifact_name
        }]
    });
    fs::write(
        index.join(format!("extensions/{id}.jsonl")),
        format!("{record}\n"),
    )
    .unwrap();
}

pub fn ecosystem_target_directory() -> PathBuf {
    let manifest =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../ecosystem/morphir-rust/Cargo.toml");
    let output = Command::new(std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into()))
        .args(["metadata", "--locked", "--no-deps", "--format-version", "1"])
        .arg("--manifest-path")
        .arg(&manifest)
        .output()
        .expect("cargo metadata should start");
    assert_success(&output, "resolve the ecosystem target directory");
    let metadata: Value = serde_json::from_slice(&output.stdout).unwrap();
    PathBuf::from(metadata["target_directory"].as_str().unwrap())
}

pub fn v4_library() -> Value {
    serde_json::from_str(include_str!(
        "../../../../ecosystem/morphir-rust/crates/morphir-core/tests/fixtures/ir/v4/v4-library-distribution.json"
    ))
    .unwrap()
}

pub fn v3_library() -> Value {
    serde_json::from_str(include_str!(
        "../../../../website/static/ir/examples/v3/greeting-example.json"
    ))
    .unwrap()
}

pub fn assert_success(output: &Output, operation: &str) {
    assert!(
        output.status.success(),
        "{operation} failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
