use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use tempfile::TempDir;

fn greeting_v3() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json")
}

/// A single-file v4 YAML model in the readable vocabulary — the spelling the canonical
/// writer emits and the one the v4 JSON Schema accepts for `packageName` (a `Path`
/// string). See `docs/spec/ir/schemas/v4/yaml-profile.md`.
fn v4_yaml() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/migrate/yaml/v4-readable.yaml")
}

fn morphir_command() -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_morphir"));
    command.env("MORPHIR_LOG_FILE", "false");
    command
}

fn migrate(input: &Path, output: &Path, extra: &[&str]) -> Output {
    let mut command = morphir_command();
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
    let input = v4_yaml();
    let output = temp.path().join("model.json");

    assert_success(&migrate(&input, &output, &[]));

    let bytes = std::fs::read(output).unwrap();
    serde_json::from_slice::<morphir_core::ir::v4::IRFile>(&bytes).unwrap();
    // The JSON profile spells a package name as a `Path` string, not as structural words.
    let document: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(
        document["distribution"]["Library"]["packageName"],
        "example"
    );
}

#[test]
fn quoted_yaml_format_version_key_converts_to_json() {
    let temp = TempDir::new().unwrap();
    let fixture = v4_yaml();
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
    let output = morphir_command()
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
    // The YAML profile and MCK versions-0005 reject every repeated mapping key
    // as duplicate_member, including the root formatVersion key.
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("morphir::ir::yaml::duplicate_member"),
        "stderr={stderr}"
    );
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

/// Every regular file under `root`, as `/`-separated paths relative to it, sorted.
fn relative_files(root: &Path) -> Vec<String> {
    fn walk(dir: &Path, prefix: &str, out: &mut Vec<String>) {
        let mut entries: Vec<_> = std::fs::read_dir(dir)
            .unwrap_or_else(|error| panic!("{} is not readable: {error}", dir.display()))
            .map(|entry| entry.unwrap())
            .collect();
        entries.sort_by_key(std::fs::DirEntry::file_name);
        for entry in entries {
            let name = entry.file_name().to_string_lossy().into_owned();
            let relative = if prefix.is_empty() {
                name
            } else {
                format!("{prefix}/{name}")
            };
            if entry.file_type().unwrap().is_dir() {
                walk(&entry.path(), &relative, out);
            } else {
                out.push(relative);
            }
        }
    }

    let mut out = Vec::new();
    walk(root, "", &mut out);
    out.sort();
    out
}

/// The canonical document tree is the reference binding's, file for file and byte for byte.
/// The fixture is the TypeScript binding's `writeTree` (with the YAML profile and the default
/// path budget) over the same migrated v4 model, laid out by `writeTreeToDirectory`; see
/// `docs/spec/ir/schemas/v4/document-tree-files.md` and MCK cases document-tree-0001 to 0009.
/// Regenerate it with `mise run fixtures:tree-acceptance`.
#[test]
fn migrated_document_tree_matches_the_reference_writer_file_for_file() {
    let temp = TempDir::new().unwrap();
    let tree = temp.path().join("greeting.morphir-dist");
    let fixture =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/tree/greeting-example");

    assert_success(&migrate(&greeting_v3(), &tree, &["--output-layout", "vfs"]));

    let actual_paths = relative_files(&tree);
    let expected_paths = relative_files(&fixture);
    assert_eq!(
        actual_paths, expected_paths,
        "the CLI and the reference writer disagree on which files the tree holds"
    );

    for relative in &expected_paths {
        let actual = std::fs::read_to_string(tree.join(relative))
            .unwrap()
            .replace("\r\n", "\n");
        let expected = std::fs::read_to_string(fixture.join(relative))
            .unwrap()
            .replace("\r\n", "\n");
        if actual == expected {
            continue;
        }
        match actual
            .lines()
            .zip(expected.lines())
            .enumerate()
            .find(|(_, (a, e))| a != e)
        {
            Some((index, (a, e))) => panic!(
                "{relative} line {}: the CLI wrote\n  {a}\nthe reference writer wrote\n  {e}",
                index + 1
            ),
            // `.lines()` ignores a trailing newline, so two texts that agree on every line can
            // still differ in trailing newline count; byte lengths do distinguish them.
            None => panic!(
                "{relative}: the two texts agree line-for-line but are not equal \
                 — likely a trailing-newline difference: CLI {} bytes, reference {} bytes",
                actual.len(),
                expected.len()
            ),
        }
    }
}

/// The canonical YAML style is the reference binding's, byte for byte. The fixture is
/// the TypeScript binding's `writeYaml` over the value tree of the same migration (see
/// `docs/spec/ir/schemas/v4/yaml-profile.md`); if this test fails, the two writers
/// disagree and the kit's `yaml canonical` fences settle which one is wrong.
#[test]
fn migrated_yaml_matches_the_reference_writer_byte_for_byte() {
    let temp = TempDir::new().unwrap();
    let output_path = temp.path().join("greeting.yaml");

    assert_success(&migrate(&greeting_v3(), &output_path, &[]));

    let actual = std::fs::read_to_string(&output_path)
        .unwrap()
        .replace("\r\n", "\n");
    let expected = include_str!("fixtures/yaml/greeting-example.v4.yaml").replace("\r\n", "\n");

    if actual != expected {
        let first = actual
            .lines()
            .zip(expected.lines())
            .enumerate()
            .find(|(_, (a, e))| a != e);
        match first {
            Some((index, (a, e))) => panic!(
                "line {}: the CLI wrote\n  {a}\nthe reference writer wrote\n  {e}",
                index + 1
            ),
            None => {
                // `.lines()` ignores a trailing newline, so two texts that agree on
                // every line can still land here when they differ only in trailing
                // newline count (or trailing whitespace after the last line). Report
                // byte lengths, which do distinguish them, instead of the equal line
                // counts `.lines()` would otherwise print.
                panic!(
                    "the two texts agree line-for-line via `.lines()` but are not equal \
                     — likely a trailing-newline difference: CLI {} bytes, reference {} bytes",
                    actual.len(),
                    expected.len()
                )
            }
        }
    }
}

/// A v3 distribution as JSON, with each module's types and values sorted by name: a document
/// tree orders module members by path.
fn sorted_v3(path: &Path) -> serde_json::Value {
    let mut value: serde_json::Value =
        serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    for module in value["distribution"][3]["modules"].as_array_mut().unwrap() {
        for members in ["types", "values"] {
            if let Some(list) = module[1]["value"][members].as_array_mut() {
                list.sort_by_key(|entry| entry[0].to_string());
            }
        }
    }
    value
}

#[test]
fn a_v3_distribution_round_trips_through_a_v3_ion_tree() {
    let temp = TempDir::new().unwrap();
    let tree = temp.path().join("model.morphir-dist");
    let json = temp.path().join("model.json");
    let v3 = ["--target-version", "v3"];

    assert_success(&migrate(
        &greeting_v3(),
        &tree,
        &[
            &v3[..],
            &["--output-layout", "vfs", "--output-format", "ion"],
        ]
        .concat(),
    ));
    assert!(tree.join("manifest.ion").is_file());
    assert!(
        std::fs::read_to_string(tree.join("manifest.ion"))
            .unwrap()
            .contains(r#"formatVersion: "3.0.0""#)
    );
    assert_success(&migrate(
        &tree,
        &json,
        &[&v3[..], &["--output-layout", "single-file"]].concat(),
    ));
    let canonical = temp.path().join("canonical.json");
    assert_success(&migrate(&greeting_v3(), &canonical, &v3));
    assert_eq!(sorted_v3(&json), sorted_v3(&canonical));
}

#[test]
fn a_v3_ion_tree_migrates_to_v4() {
    let temp = TempDir::new().unwrap();
    let tree = temp.path().join("model.morphir-dist");
    let json = temp.path().join("model.json");

    assert_success(&migrate(
        &greeting_v3(),
        &tree,
        &[
            "--target-version",
            "v3",
            "--output-layout",
            "vfs",
            "--output-format",
            "ion",
        ],
    ));
    assert_success(&migrate(&tree, &json, &["--output-layout", "single-file"]));
    serde_json::from_slice::<morphir_core::ir::v4::IRFile>(&std::fs::read(json).unwrap()).unwrap();
}

#[test]
fn a_v3_distribution_round_trips_through_v3_json_and_yaml_trees() {
    for format in ["json", "yaml"] {
        let temp = TempDir::new().unwrap();
        let tree = temp.path().join("model.morphir-dist");
        let json = temp.path().join("model.json");
        let v3 = ["--target-version", "v3"];
        assert_success(&migrate(
            &greeting_v3(),
            &tree,
            &[
                &v3[..],
                &["--output-layout", "vfs", "--output-format", format],
            ]
            .concat(),
        ));
        let manifest = std::fs::read_to_string(tree.join(format!("manifest.{format}"))).unwrap();
        assert!(manifest.contains("3.1.0"), "{manifest}");
        assert_success(&migrate(
            &tree,
            &json,
            &[&v3[..], &["--output-layout", "single-file"]].concat(),
        ));
        let canonical = temp.path().join("canonical.json");
        assert_success(&migrate(&greeting_v3(), &canonical, &v3));
        assert_eq!(sorted_v3(&json), sorted_v3(&canonical), "{format}");
    }
}

/// A v4 JSON document tree whose manifest is replaced by `manifest`.
fn v4_json_tree_with_manifest(temp: &TempDir, manifest: &str) -> PathBuf {
    let tree = temp.path().join("model.morphir-dist");
    assert_success(&migrate(
        &greeting_v3(),
        &tree,
        &["--output-layout", "vfs", "--output-format", "json"],
    ));
    std::fs::write(tree.join("manifest.json"), manifest).unwrap();
    tree
}

/// A tree manifest that is not v3 is read as v4, so the transport reports its faults.
#[test]
fn a_v4_tree_manifest_without_format_version_gets_the_transport_diagnostic() {
    let temp = TempDir::new().unwrap();
    let tree = v4_json_tree_with_manifest(
        &temp,
        r#"{ "distribution": "Library", "package": "elm-compat", "pathBudget": 4000 }"#,
    );
    let output_path = temp.path().join("model.json");

    let output = migrate(&tree, &output_path, &["--output-layout", "single-file"]);

    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("missing_format_version"), "stderr={stderr}");
    assert!(
        !stderr.contains("morphir::ir::detection::"),
        "stderr={stderr}"
    );
    assert!(!output_path.exists());
}

#[test]
fn a_tree_manifest_at_format_version_5_gets_the_transport_diagnostic() {
    let temp = TempDir::new().unwrap();
    let tree = v4_json_tree_with_manifest(
        &temp,
        r#"{ "formatVersion": 5, "distribution": "Library", "package": "elm-compat", "pathBudget": 4000 }"#,
    );
    let output_path = temp.path().join("model.json");

    let output = migrate(&tree, &output_path, &["--output-layout", "single-file"]);

    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("unsupported_format_version_major"),
        "stderr={stderr}"
    );
    assert!(
        !stderr.contains("morphir::ir::detection::"),
        "stderr={stderr}"
    );
    assert!(!output_path.exists());
}
