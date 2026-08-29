use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use tempfile::TempDir;

fn greeting_v3() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json")
}

fn migrate(input: &Path, output: &Path, extra: &[&str]) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_morphir"));
    command.args([
        "ir",
        "migrate",
        input.to_str().unwrap(),
        "--output",
        output.to_str().unwrap(),
    ]);
    command.args(extra);
    command.output().unwrap()
}

fn assert_success(output: &Output) {
    assert!(
        output.status.success(),
        "stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn extensionless_v3_to_v4_output_defaults_to_yaml() {
    let temp = TempDir::new().unwrap();
    let output = temp.path().join("model");

    assert_success(&migrate(&greeting_v3(), &output, &[]));

    assert!(
        std::fs::read_to_string(output)
            .unwrap()
            .starts_with("formatVersion: 4")
    );
}

#[test]
fn recognized_output_extensions_select_the_storage_profile() {
    let temp = TempDir::new().unwrap();
    for extension in ["yaml", "yml"] {
        let output = temp.path().join(format!("model.{extension}"));
        assert_success(&migrate(&greeting_v3(), &output, &[]));
        assert!(
            std::fs::read_to_string(output)
                .unwrap()
                .starts_with("formatVersion: 4")
        );
    }

    let output = temp.path().join("model.json");
    assert_success(&migrate(&greeting_v3(), &output, &[]));
    serde_json::from_slice::<morphir_core::ir::v4::IRFile>(&std::fs::read(output).unwrap())
        .unwrap();
}

#[test]
fn explicit_formats_support_unknown_file_extensions() {
    let temp = TempDir::new().unwrap();
    let input = temp.path().join("model.data");
    let output = temp.path().join("result.data");
    std::fs::copy(greeting_v3(), &input).unwrap();

    assert_success(&migrate(
        &input,
        &output,
        &["--input-format", "json", "--output-format", "yaml"],
    ));

    assert!(
        std::fs::read_to_string(output)
            .unwrap()
            .starts_with("formatVersion: 4")
    );
}

#[test]
fn conflicting_output_format_does_not_replace_the_destination() {
    let temp = TempDir::new().unwrap();
    let output = temp.path().join("model.yaml");
    std::fs::write(&output, "unchanged").unwrap();

    let result = migrate(&greeting_v3(), &output, &["--output-format", "json"]);

    assert!(!result.status.success());
    assert_eq!(std::fs::read_to_string(output).unwrap(), "unchanged");
    assert!(String::from_utf8_lossy(&result.stderr).contains("format"));
}

#[test]
fn yaml_document_tree_round_trips_to_json() {
    let temp = TempDir::new().unwrap();
    let tree = temp.path().join("model.morphir-dist");
    let output = temp.path().join("model.json");

    assert_success(&migrate(&greeting_v3(), &tree, &["--output-layout", "vfs"]));
    assert!(tree.join("manifest.yaml").is_file());
    assert_success(&migrate(
        &tree,
        &output,
        &["--output-layout", "single-file"],
    ));
    serde_json::from_slice::<morphir_core::ir::v4::IRFile>(&std::fs::read(output).unwrap())
        .unwrap();
}

#[test]
fn yaml_v4_single_file_converts_to_json() {
    let temp = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/migrate/yaml/v4-explicit.yaml");
    let output = temp.path().join("model.json");

    assert_success(&migrate(&input, &output, &[]));

    serde_json::from_slice::<morphir_core::ir::v4::IRFile>(&std::fs::read(output).unwrap())
        .unwrap();
}

#[test]
fn quoted_yaml_format_version_key_converts_to_json() {
    let temp = TempDir::new().unwrap();
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/migrate/yaml/v4-explicit.yaml");
    let input = temp.path().join("quoted-version.yaml");
    let output = temp.path().join("model.json");
    let source = std::fs::read_to_string(fixture).unwrap().replacen(
        "formatVersion:",
        "\"formatVersion\":",
        1,
    );
    std::fs::write(&input, source).unwrap();

    assert_success(&migrate(&input, &output, &[]));

    serde_json::from_slice::<morphir_core::ir::v4::IRFile>(&std::fs::read(output).unwrap())
        .unwrap();
}

#[test]
fn json_flag_without_output_emits_only_json_ir() {
    let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args(["migrate", greeting_v3().to_str().unwrap(), "--json"])
        .output()
        .unwrap();

    assert_success(&output);
    serde_json::from_slice::<morphir_core::ir::v4::IRFile>(&output.stdout).unwrap();
}

#[test]
fn json_flag_with_output_reports_status_without_changing_artifact_format() {
    let temp = TempDir::new().unwrap();
    let output_path = temp.path().join("model.yaml");

    let output = migrate(&greeting_v3(), &output_path, &["--json"]);

    assert_success(&output);
    let status: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(status["success"], true);
    assert!(
        std::fs::read_to_string(output_path)
            .unwrap()
            .starts_with("formatVersion: 4")
    );
}

#[test]
fn duplicate_yaml_format_version_reports_the_canonical_diagnostic() {
    let temp = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/migrate/yaml/rejected/duplicate-key.yaml");
    let output_path = temp.path().join("model.json");

    let output = migrate(&input, &output_path, &[]);

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("duplicate_format_version"));
    assert!(!output_path.exists());
}

#[test]
fn concrete_v3_json_and_yaml_convert_in_both_directions() {
    let temp = TempDir::new().unwrap();
    let yaml = temp.path().join("model.yaml");
    let json = temp.path().join("model.json");

    assert_success(&migrate(&greeting_v3(), &yaml, &["--target-version", "v3"]));
    assert_success(&migrate(&yaml, &json, &["--target-version", "v3"]));
    let original: morphir_core::ir::classic::Distribution =
        serde_json::from_slice(&std::fs::read(greeting_v3()).unwrap()).unwrap();
    let converted: morphir_core::ir::classic::Distribution =
        serde_json::from_slice(&std::fs::read(json).unwrap()).unwrap();
    assert_eq!(converted, original);
}
