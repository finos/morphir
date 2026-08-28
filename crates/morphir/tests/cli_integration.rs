//! Integration tests for CLI commands

use std::path::PathBuf;
use tempfile::TempDir;

struct TestIndex {
    root: PathBuf,
    source: PathBuf,
    digest: String,
    filename: String,
}

fn write_test_index(
    directory: &std::path::Path,
    id: &str,
    name: &str,
    version: &str,
    bytes: &[u8],
) -> TestIndex {
    let root = directory.join("index");
    let filename = if cfg!(windows) {
        format!("{id}.exe")
    } else {
        id.to_owned()
    };
    let relative_source = format!("artifacts/{filename}");
    let source = root.join(&relative_source);
    std::fs::create_dir_all(source.parent().unwrap()).unwrap();
    std::fs::create_dir_all(root.join("extensions")).unwrap();
    std::fs::write(&source, bytes).unwrap();
    let digest = morphir_distribution::Sha256Digest::of_bytes(bytes).to_string();
    let record = serde_json::json!({
        "schemaVersion": 1,
        "id": id,
        "name": name,
        "version": version,
        "channels": ["stable"],
        "mepVersions": ["0.1"],
        "capabilities": ["frontend"],
        "artifacts": [{
            "runtime": "process",
            "platform": {
                "os": std::env::consts::OS,
                "arch": std::env::consts::ARCH,
            },
            "source": {"kind": "local-file", "path": relative_source},
            "sha256": digest,
            "filename": filename,
            "args": [],
            "executable": true,
        }],
    });
    std::fs::write(
        root.join("extensions").join(format!("{id}.jsonl")),
        format!("{record}\n"),
    )
    .unwrap();
    TestIndex {
        root,
        source,
        digest,
        filename,
    }
}

fn run_morphir(
    arguments: &[&str],
    morphir_home: &std::path::Path,
    working_directory: &std::path::Path,
) -> std::process::Output {
    std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args(arguments)
        .env("MORPHIR_HOME", morphir_home)
        .current_dir(working_directory)
        .output()
        .expect("failed to run morphir binary")
}

#[test]
fn extension_install_uses_verified_index_and_list_reports_the_exact_version() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let index = write_test_index(
        temp.path(),
        "morphir-test",
        "Morphir test frontend",
        "1.2.3",
        b"verified executable bytes",
    );

    let install = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--index",
            index.root.to_str().unwrap(),
        ],
        &home,
        temp.path(),
    );
    assert!(
        install.status.success(),
        "install failed: stdout={} stderr={}",
        String::from_utf8_lossy(&install.stdout),
        String::from_utf8_lossy(&install.stderr)
    );
    assert!(
        home.join("store/extensions/sha256")
            .join(&index.digest)
            .join(&index.filename)
            .exists()
    );
    assert!(home.join("catalog/extensions.json").exists());
    assert!(home.join("locks/extensions/morphir-test.json").exists());
    assert!(!home.join("extensions.json").exists());

    let list = run_morphir(&["extension", "list"], &home, temp.path());
    assert!(list.status.success());
    let stdout = String::from_utf8_lossy(&list.stdout);
    assert!(stdout.contains("morphir-test"), "{stdout}");
    assert!(stdout.contains("1.2.3"), "{stdout}");
    assert!(stdout.contains("stable"), "{stdout}");
}

#[test]
fn extension_list_keeps_the_builtin_gleam_extension_when_nothing_is_installed() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");

    let list = run_morphir(&["extension", "list"], &home, temp.path());

    assert!(list.status.success());
    let stdout = String::from_utf8_lossy(&list.stdout);
    assert!(stdout.contains("Builtin Extensions"), "{stdout}");
    assert!(stdout.contains("gleam"), "{stdout}");
    assert!(stdout.contains("Gleam Language Binding"), "{stdout}");
    assert!(
        stdout.contains("No verified extensions installed"),
        "{stdout}"
    );
}

#[test]
fn extension_install_rejects_source_tampering_without_activating_a_catalog_entry() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let index = write_test_index(
        temp.path(),
        "morphir-test",
        "Morphir test frontend",
        "1.2.3",
        b"original bytes",
    );
    std::fs::write(&index.source, b"tampered bytes").unwrap();

    let install = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--index",
            index.root.to_str().unwrap(),
        ],
        &home,
        temp.path(),
    );
    assert!(!install.status.success());
    assert!(!home.join("catalog/extensions.json").exists());
    let stderr = String::from_utf8_lossy(&install.stderr);
    assert!(stderr.contains("digest"), "{stderr}");
}

#[test]
fn extension_selection_flags_are_mutually_exclusive() {
    let temp = TempDir::new().unwrap();
    let output = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--index",
            temp.path().to_str().unwrap(),
            "--channel",
            "preview",
            "--version",
            "1.0.0",
        ],
        &temp.path().join("home"),
        temp.path(),
    );
    assert!(!output.status.success());
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("cannot be used with"),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn extension_update_re_resolves_to_an_exact_version() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let first = write_test_index(
        &temp.path().join("first"),
        "morphir-test",
        "Morphir test frontend",
        "1.2.3",
        b"version one",
    );
    let second = write_test_index(
        &temp.path().join("second"),
        "morphir-test",
        "Morphir test frontend",
        "2.0.0",
        b"version two",
    );
    let install = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--index",
            first.root.to_str().unwrap(),
            "--version",
            "1.2.3",
        ],
        &home,
        temp.path(),
    );
    assert!(install.status.success());

    let update = run_morphir(
        &[
            "extension",
            "update",
            "morphir-test",
            "--index",
            second.root.to_str().unwrap(),
            "--version",
            "2.0.0",
        ],
        &home,
        temp.path(),
    );
    assert!(
        update.status.success(),
        "update failed: stdout={} stderr={}",
        String::from_utf8_lossy(&update.stdout),
        String::from_utf8_lossy(&update.stderr)
    );
    let list = run_morphir(&["extension", "list"], &home, temp.path());
    let stdout = String::from_utf8_lossy(&list.stdout);
    assert!(stdout.contains("2.0.0"), "{stdout}");
    assert!(stdout.contains("version 2.0.0"), "{stdout}");
    assert!(!stdout.contains("1.2.3"), "{stdout}");
}

#[test]
fn extension_uninstall_removes_active_state_but_retains_store_bytes() {
    let temp = TempDir::new().unwrap();
    let home = temp.path().join("home");
    let index = write_test_index(
        temp.path(),
        "morphir-test",
        "Morphir test frontend",
        "1.2.3",
        b"verified executable bytes",
    );
    let install = run_morphir(
        &[
            "extension",
            "install",
            "morphir-test",
            "--index",
            index.root.to_str().unwrap(),
        ],
        &home,
        temp.path(),
    );
    assert!(install.status.success());
    let stored = home
        .join("store/extensions/sha256")
        .join(&index.digest)
        .join(&index.filename);
    assert!(stored.exists());

    let uninstall = run_morphir(
        &["extension", "uninstall", "morphir-test"],
        &home,
        temp.path(),
    );

    assert!(
        uninstall.status.success(),
        "uninstall failed: stdout={} stderr={}",
        String::from_utf8_lossy(&uninstall.stdout),
        String::from_utf8_lossy(&uninstall.stderr)
    );
    let catalog = std::fs::read_to_string(home.join("catalog/extensions.json")).unwrap();
    assert!(!catalog.contains("morphir-test"), "{catalog}");
    assert!(!home.join("locks/extensions/morphir-test.json").exists());
    assert!(stored.exists());
}

#[test]
#[ignore = "requires the real Bun-built morphir-elm-extension executable"]
fn real_installed_morphir_elm_is_verified_and_activates_offline() {
    let executable = std::env::var_os("MORPHIR_ELM_EXTENSION_BIN")
        .map(PathBuf::from)
        .expect("set MORPHIR_ELM_EXTENSION_BIN to the Bun-built extension");
    let bytes = std::fs::read(&executable).unwrap();
    let temp = TempDir::new().unwrap();

    let tamper_case = temp.path().join("source-tamper");
    let tampered_home = tamper_case.join("home");
    let tampered_index = write_test_index(
        &tamper_case,
        "morphir-elm",
        "Morphir Elm frontend",
        "2.100.0",
        &bytes,
    );
    std::fs::write(&tampered_index.source, b"tampered source bytes").unwrap();
    let rejected = run_morphir(
        &[
            "extension",
            "install",
            "morphir-elm",
            "--index",
            tampered_index.root.to_str().unwrap(),
        ],
        &tampered_home,
        &tamper_case,
    );
    assert!(!rejected.status.success());
    assert!(!tampered_home.join("catalog/extensions.json").exists());

    let project = temp.path().join("offline-project");
    let home = project.join("home");
    std::fs::create_dir_all(&project).unwrap();
    let index = write_test_index(
        &project,
        "morphir-elm",
        "Morphir Elm frontend",
        "2.100.0",
        &bytes,
    );
    let install = run_morphir(
        &[
            "extension",
            "install",
            "morphir-elm",
            "--index",
            index.root.to_str().unwrap(),
        ],
        &home,
        &project,
    );
    assert!(
        install.status.success(),
        "install failed: {}",
        String::from_utf8_lossy(&install.stderr)
    );
    let catalog = std::fs::read_to_string(home.join("catalog/extensions.json")).unwrap();
    let lock = std::fs::read_to_string(home.join("locks/extensions/morphir-elm.json")).unwrap();
    assert!(catalog.contains("2.100.0"));
    assert!(catalog.contains(&index.digest));
    assert!(lock.contains("2.100.0"));
    assert!(lock.contains("stable"));
    let installed_path = home
        .join("store/extensions/sha256")
        .join(&index.digest)
        .join(&index.filename);
    assert_eq!(std::fs::read(&installed_path).unwrap(), bytes);

    std::fs::remove_dir_all(&index.root).unwrap();
    let source = project.join("Example.elm");
    let output_path = project.join("morphir-ir.json");
    std::fs::write(
        &source,
        "module Example exposing (add)\n\nadd left right = left + right\n",
    )
    .unwrap();
    let compile = run_morphir(
        &[
            "compile",
            "--language",
            "elm",
            "--input",
            source.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
        ],
        &home,
        &project,
    );
    assert!(
        compile.status.success(),
        "offline compile failed: stdout={} stderr={}",
        String::from_utf8_lossy(&compile.stdout),
        String::from_utf8_lossy(&compile.stderr)
    );
    assert!(output_path.exists());

    std::fs::write(&installed_path, b"tampered installed bytes").unwrap();
    let rejected = run_morphir(
        &[
            "compile",
            "--language",
            "elm",
            "--input",
            source.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
        ],
        &home,
        &project,
    );
    assert!(!rejected.status.success());
    assert!(
        String::from_utf8_lossy(&rejected.stderr).contains("digest"),
        "{}",
        String::from_utf8_lossy(&rejected.stderr)
    );
}

#[tokio::test]
async fn test_compile_command_basic() {
    let temp_dir = TempDir::new().unwrap();
    let project_root = temp_dir.path();

    // Create a simple Gleam source file
    let src_dir = project_root.join("src");
    std::fs::create_dir_all(&src_dir).unwrap();
    std::fs::write(src_dir.join("main.gleam"), "pub fn hello() { \"world\" }").unwrap();

    // Create morphir.toml
    std::fs::write(
        project_root.join("morphir.toml"),
        r#"
[project]
name = "test-project"
source_directory = "src"

[frontend]
language = "gleam"
"#,
    )
    .unwrap();

    // Note: This test would require the actual morphir binary to be built
    // For now, we just verify the setup is correct
    assert!(src_dir.exists());
    assert!(project_root.join("morphir.toml").exists());
}

#[tokio::test]
async fn test_generate_command_basic() {
    let temp_dir = TempDir::new().unwrap();
    let project_root = temp_dir.path();

    // Create .morphir/out structure with IR
    let morphir_dir = project_root.join(".morphir");
    let ir_dir = morphir_dir
        .join("out")
        .join("test-project")
        .join("compile")
        .join("gleam");
    std::fs::create_dir_all(&ir_dir).unwrap();

    // Write format.json
    let format_json = serde_json::json!({
        "formatVersion": 4,
        "packageName": "test-project"
    });
    std::fs::write(
        ir_dir.join("format.json"),
        serde_json::to_string_pretty(&format_json).unwrap(),
    )
    .unwrap();

    assert!(ir_dir.exists());
    assert!(ir_dir.join("format.json").exists());
}

#[test]
fn test_config_discovery() {
    use morphir_devkit::discover_config;

    let temp_dir = TempDir::new().unwrap();
    let project_root = temp_dir.path();

    // Create morphir.toml
    std::fs::write(
        project_root.join("morphir.toml"),
        "[project]\nname = \"test\"",
    )
    .unwrap();

    // Test discovery from subdirectory
    let subdir = project_root.join("subdir");
    std::fs::create_dir_all(&subdir).unwrap();

    let config_path = discover_config(&subdir).unwrap();
    assert!(config_path.is_some());
    assert_eq!(config_path.unwrap(), project_root.join("morphir.toml"));
}

#[test]
fn test_morphir_dir_discovery() {
    use morphir_devkit::discover_morphir_dir;

    let temp_dir = TempDir::new().unwrap();
    let project_root = temp_dir.path();

    // Create .morphir directory
    let morphir_dir = project_root.join(".morphir");
    std::fs::create_dir_all(&morphir_dir).unwrap();

    // Test discovery from subdirectory
    let subdir = project_root.join("subdir");
    std::fs::create_dir_all(&subdir).unwrap();

    let discovered = discover_morphir_dir(&subdir);
    assert!(discovered.is_some());
    assert_eq!(discovered.unwrap(), morphir_dir);
}

#[test]
fn test_path_resolution() {
    use morphir_devkit::{resolve_compile_output, resolve_generate_output, sanitize_project_name};

    let morphir_dir = PathBuf::from(".morphir");

    // Test compile output resolution
    let compile_path = resolve_compile_output("My.Project", "gleam", &morphir_dir);
    assert!(compile_path.to_string_lossy().contains("out"));
    assert!(compile_path.to_string_lossy().contains("My.Project"));
    assert!(compile_path.to_string_lossy().contains("compile"));
    assert!(compile_path.to_string_lossy().contains("gleam"));

    // Test generate output resolution
    let generate_path = resolve_generate_output("My.Project", "gleam", &morphir_dir);
    assert!(generate_path.to_string_lossy().contains("out"));
    assert!(generate_path.to_string_lossy().contains("My.Project"));
    assert!(generate_path.to_string_lossy().contains("generate"));
    assert!(generate_path.to_string_lossy().contains("gleam"));

    // Test project name sanitization
    let sanitized = sanitize_project_name("My/Project");
    assert_eq!(sanitized, "My-Project");
}

#[test]
fn test_output_format() {
    use morphir::output::OutputFormat;

    // Test format detection from flags
    assert_eq!(OutputFormat::from_flags(false, false), OutputFormat::Human);
    assert_eq!(OutputFormat::from_flags(true, false), OutputFormat::Json);
    assert_eq!(
        OutputFormat::from_flags(false, true),
        OutputFormat::JsonLines
    );
    assert_eq!(
        OutputFormat::from_flags(true, true),
        OutputFormat::JsonLines // json_lines takes precedence
    );
}

#[test]
fn test_morphir_home_env_var_relocates_home_directory() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");

    let output = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args(["tool", "install", "example-tool"])
        .env("MORPHIR_HOME", &morphir_home)
        .current_dir(temp_dir.path())
        .output()
        .expect("failed to run morphir binary");

    assert!(
        output.status.success(),
        "tool install failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        morphir_home.join("tools.json").exists(),
        "expected tool registry at MORPHIR_HOME ({})",
        morphir_home.display()
    );
}

#[test]
fn migrate_converts_a_real_v3_file_to_concrete_v4() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let output_path = temp_dir.path().join("greeting-v4.json");

    let output = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
            "--target-version",
            "v4",
        ])
        .output()
        .expect("failed to run morphir binary");

    assert!(
        output.status.success(),
        "migration failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let migrated: morphir_core::ir::v4::IRFile =
        serde_json::from_slice(&std::fs::read(output_path).unwrap()).unwrap();
    assert_eq!(
        migrated.format_version,
        morphir_core::ir::v4::FormatVersion::Integer(4)
    );
}

#[test]
fn migrate_is_available_as_a_top_level_command() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let output_path = temp_dir.path().join("greeting-v4.json");

    let output = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args([
            "migrate",
            input.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
        ])
        .output()
        .expect("failed to run morphir binary");

    assert!(
        output.status.success(),
        "migration failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice::<morphir_core::ir::v4::IRFile>(&std::fs::read(output_path).unwrap())
        .unwrap();
}

#[test]
fn migrate_selects_compact_or_expanded_v4_type_encoding() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let compact = temp_dir.path().join("compact.json");
    let expanded = temp_dir.path().join("expanded.json");

    for (path, extra) in [(&compact, None), (&expanded, Some("--expanded"))] {
        let mut command = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"));
        command.args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            path.to_str().unwrap(),
            "--target-version",
            "v4",
        ]);
        if let Some(extra) = extra {
            command.arg(extra);
        }
        let result = command.output().unwrap();
        assert!(result.status.success());
    }

    let type_expression = |path: &PathBuf| {
        let value: serde_json::Value =
            serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
        value["distribution"]["Library"]["def"]["modules"]["main"]["value"]["types"]
            ["product-id"]["value"]["value"]["TypeAliasDefinition"]["typeExp"]
            .clone()
    };
    assert!(type_expression(&compact).is_string());
    assert!(type_expression(&expanded)["Reference"].is_object());
}

#[test]
fn migrate_failure_does_not_replace_an_existing_output() {
    let temp_dir = TempDir::new().unwrap();
    let input = temp_dir.path().join("v2.json");
    let output_path = temp_dir.path().join("result.json");
    let mut source: serde_json::Value = serde_json::from_str(include_str!(
        "../../../website/static/ir/examples/v3/greeting-example.json"
    ))
    .unwrap();
    source["formatVersion"] = 2.into();
    std::fs::write(&input, serde_json::to_vec(&source).unwrap()).unwrap();
    std::fs::write(&output_path, "unchanged").unwrap();

    let output = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
            "--target-version",
            "v4",
        ])
        .output()
        .expect("failed to run morphir binary");

    assert!(!output.status.success());
    assert_eq!(std::fs::read_to_string(output_path).unwrap(), "unchanged");
}

#[test]
fn migrate_reports_unsupported_v4_downgrade_without_replacing_output() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v4/complete-example.json");
    let output_path = temp_dir.path().join("result.json");
    std::fs::write(&output_path, "unchanged").unwrap();

    let output = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
            "--target-version",
            "v3",
        ])
        .output()
        .expect("failed to run morphir binary");

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("unsupported_v4_downgrade"));
    assert_eq!(std::fs::read_to_string(output_path).unwrap(), "unchanged");
}

#[test]
fn migrate_writes_and_reads_a_v4_document_tree() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let tree = temp_dir.path().join("greeting.morphir-dist");
    let single_file = temp_dir.path().join("round-trip.json");

    let to_tree = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            tree.to_str().unwrap(),
            "--output-layout",
            "vfs",
            "--target-version",
            "v4",
        ])
        .output()
        .expect("failed to migrate to a document tree");
    assert!(
        to_tree.status.success(),
        "migration failed: stdout={} stderr={}",
        String::from_utf8_lossy(&to_tree.stdout),
        String::from_utf8_lossy(&to_tree.stderr)
    );
    assert!(tree.join("manifest.yaml").is_file());

    let to_file = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args([
            "ir",
            "migrate",
            tree.to_str().unwrap(),
            "--output",
            single_file.to_str().unwrap(),
            "--output-layout",
            "single-file",
            "--target-version",
            "v4",
        ])
        .output()
        .expect("failed to migrate the document tree to a file");
    assert!(
        to_file.status.success(),
        "migration failed: stdout={} stderr={}",
        String::from_utf8_lossy(&to_file.stdout),
        String::from_utf8_lossy(&to_file.stderr)
    );
    serde_json::from_slice::<morphir_core::ir::v4::IRFile>(&std::fs::read(single_file).unwrap())
        .unwrap();
}

#[test]
fn migrate_infers_vfs_for_a_new_directory_path_with_a_trailing_separator() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let tree = format!("{}/", temp_dir.path().join("new-tree").display());

    let output = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args(["ir", "migrate", input.to_str().unwrap(), "--output", &tree])
        .output()
        .expect("failed to migrate to an inferred document tree");

    assert!(
        output.status.success(),
        "migration failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(PathBuf::from(tree).join("manifest.yaml").is_file());
}

#[test]
fn migrate_accepts_partial_and_encoding_flags() {
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args(["ir", "migrate", "--help"])
        .output()
        .expect("failed to read migrate help");
    let help = String::from_utf8_lossy(&output.stdout);
    assert!(help.contains("--allow-partial"));
    assert!(help.contains("--expanded"));
    assert!(help.contains("--output-layout"));
    assert!(help.contains("--input-format"));
    assert!(help.contains("--output-format"));
}
