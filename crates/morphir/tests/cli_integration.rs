//! Integration tests for CLI commands

use std::path::PathBuf;
use tempfile::TempDir;

struct TestIndex {
    root: PathBuf,
    source: PathBuf,
    digest: String,
    filename: String,
}

fn morphir_command() -> std::process::Command {
    let mut command = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"));
    command.env("MORPHIR_LOG_FILE", "false");
    command
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
    morphir_command()
        .args(arguments)
        .env("MORPHIR_HOME", morphir_home)
        .current_dir(working_directory)
        .output()
        .expect("failed to run morphir binary")
}

#[test]
fn compile_help_documents_explicit_extension_selection() {
    let temp = TempDir::new().unwrap();
    let output = run_morphir(
        &["compile", "--help"],
        &temp.path().join("home"),
        temp.path(),
    );

    assert!(output.status.success());
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert!(stdout.contains("--extension <EXTENSION>"), "{stdout}");
    assert!(stdout.contains("single-file Elm compilation"), "{stdout}");
    // Clap wraps help to the terminal width, so compare against text with its
    // whitespace collapsed rather than against the wrapped lines.
    let flowed = stdout.split_whitespace().collect::<Vec<_>>().join(" ");
    assert!(
        flowed.contains("Defaults to morphir- followed by the language name"),
        "{stdout}"
    );
    // Deliberately not `morphir-{language}`. Help text is copied verbatim into
    // docs/cli/compile.md, which Docusaurus parses as MDX, where a brace opens a
    // JSX expression and the page fails to render.
    assert!(
        !flowed.contains("morphir-{"),
        "braces in prose help become a JSX expression in the generated docs: {stdout}"
    );
}

#[test]
fn compile_rejects_an_invalid_explicit_extension_id() {
    let temp = TempDir::new().unwrap();
    let source = temp.path().join("Example.elm");
    std::fs::write(&source, "module Example exposing (value)\n\nvalue = 1\n").unwrap();

    let output = run_morphir(
        &[
            "compile",
            "--input",
            source.to_str().unwrap(),
            "--extension",
            "Morphir Scala Elm",
        ],
        &temp.path().join("home"),
        temp.path(),
    );

    assert!(!output.status.success());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(stderr.contains("Invalid extension id"), "{stderr}");
}

#[test]
fn compile_reports_the_selected_extension_when_it_is_not_installed() {
    let temp = TempDir::new().unwrap();
    let source = temp.path().join("Example.elm");
    std::fs::write(&source, "module Example exposing (value)\n\nvalue = 1\n").unwrap();

    let output = run_morphir(
        &[
            "compile",
            "--input",
            source.to_str().unwrap(),
            "--extension",
            "morphir-scala-elm",
        ],
        &temp.path().join("home"),
        temp.path(),
    );

    assert!(!output.status.success());
    let stderr = String::from_utf8(output.stderr).unwrap();
    let compact_stderr = stderr.split_whitespace().collect::<String>();
    assert!(
        compact_stderr.contains("extensionmorphir-scala-elmisnotinstalled"),
        "{stderr}"
    );
}

#[test]
fn compile_rejects_explicit_extension_selection_on_the_legacy_path() {
    let temp = TempDir::new().unwrap();
    let source = temp.path().join("Example.gleam");
    std::fs::write(&source, "pub fn value() { 1 }\n").unwrap();

    let output = run_morphir(
        &[
            "compile",
            "--language",
            "gleam",
            "--input",
            source.to_str().unwrap(),
            "--extension",
            "morphir-other-gleam",
        ],
        &temp.path().join("home"),
        temp.path(),
    );

    assert!(!output.status.success());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(
        stderr.contains("Explicit extension selection currently requires"),
        "{stderr}"
    );
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
    verify_real_installed_elm_provider(
        "MORPHIR_ELM_EXTENSION_BIN",
        "morphir-elm",
        "Morphir Elm frontend",
        "2.100.0",
        false,
    );
}

#[test]
#[ignore = "requires the real GraalVM-built morphir-scala-elm executable"]
fn real_installed_morphir_scala_elm_is_selected_and_activates_offline() {
    let version = std::env::var("MORPHIR_SCALA_ELM_EXTENSION_VERSION")
        .expect("set MORPHIR_SCALA_ELM_EXTENSION_VERSION to the packaged extension version");
    verify_real_installed_elm_provider(
        "MORPHIR_SCALA_ELM_EXTENSION_BIN",
        "morphir-scala-elm",
        "Morphir Scala Elm frontend",
        &version,
        true,
    );
}

fn verify_real_installed_elm_provider(
    executable_environment_variable: &str,
    extension_id: &str,
    extension_name: &str,
    version: &str,
    select_explicitly: bool,
) {
    let executable = std::env::var_os(executable_environment_variable)
        .map(PathBuf::from)
        .unwrap_or_else(|| panic!("set {executable_environment_variable} to the extension"));
    let bytes = std::fs::read(&executable).unwrap();
    let temp = TempDir::new().unwrap();

    let tamper_case = temp.path().join("source-tamper");
    let tampered_home = tamper_case.join("home");
    let tampered_index =
        write_test_index(&tamper_case, extension_id, extension_name, version, &bytes);
    std::fs::write(&tampered_index.source, b"tampered source bytes").unwrap();
    let rejected = run_morphir(
        &[
            "extension",
            "install",
            extension_id,
            "--index",
            tampered_index.root.to_str().unwrap(),
            "--version",
            version,
        ],
        &tampered_home,
        &tamper_case,
    );
    assert!(!rejected.status.success());
    assert!(!tampered_home.join("catalog/extensions.json").exists());

    let project = temp.path().join("offline-project");
    let home = project.join("home");
    std::fs::create_dir_all(&project).unwrap();
    let index = write_test_index(&project, extension_id, extension_name, version, &bytes);
    let install = run_morphir(
        &[
            "extension",
            "install",
            extension_id,
            "--index",
            index.root.to_str().unwrap(),
            "--version",
            version,
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
    let lock = std::fs::read_to_string(
        home.join("locks/extensions")
            .join(format!("{extension_id}.json")),
    )
    .unwrap();
    assert!(catalog.contains(version));
    assert!(catalog.contains(&index.digest));
    assert!(lock.contains(version));
    assert!(lock.contains(r#""kind": "exact""#), "{lock}");
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
        "module Example exposing (add)\n\nadd : Int -> Int -> Int\nadd left right = left + right\n",
    )
    .unwrap();
    let mut compile_arguments = vec![
        "compile",
        "--language",
        "elm",
        "--input",
        source.to_str().unwrap(),
        "--output",
        output_path.to_str().unwrap(),
    ];
    if select_explicitly {
        compile_arguments.extend_from_slice(&["--extension", extension_id]);
    }
    let compile = run_morphir(&compile_arguments, &home, &project);
    assert!(
        compile.status.success(),
        "offline compile failed: stdout={} stderr={}",
        String::from_utf8_lossy(&compile.stdout),
        String::from_utf8_lossy(&compile.stderr)
    );
    assert!(output_path.exists());
    let ir: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&output_path).unwrap()).unwrap();
    assert_eq!(ir["formatVersion"], 3, "{ir}");

    std::fs::write(&installed_path, b"tampered installed bytes").unwrap();
    let rejected = run_morphir(&compile_arguments, &home, &project);
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

    let output = morphir_command()
        .args(["tool", "install", "example-tool"])
        .env("MORPHIR_HOME", &morphir_home)
        .env_remove("MORPHIR_LOG_DIR")
        .env("MORPHIR_LOG_FILE", "true")
        .env_remove("MORPHIR_LOGGING__FILE_LEVEL")
        .env_remove("MORPHIR_LOG_FILE_LEVEL")
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
    let cli_log_root = morphir_home.join("logs/cli");
    let session_log = std::fs::read_dir(&cli_log_root)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .filter(|entry| entry.path().is_dir())
        .flat_map(|entry| std::fs::read_dir(entry.path()).into_iter().flatten())
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .find(|path| path.extension().is_some_and(|ext| ext == "jsonl"))
        .unwrap_or_else(|| {
            panic!(
                "expected a CLI JSONL session log beneath {}",
                cli_log_root.display()
            )
        });
    let first_record = std::fs::read_to_string(&session_log)
        .unwrap()
        .lines()
        .next()
        .map(str::to_owned)
        .expect("session log should contain its startup event");
    let event: serde_json::Value = serde_json::from_str(&first_record).unwrap();
    assert_eq!(event["fields"]["schema_version"], 1);
    assert_eq!(event["fields"]["component"], "cli");
    assert_eq!(event["fields"]["event_name"], "cli.session.start");
    assert!(event["fields"]["process_id"].is_number());
    assert!(event["fields"]["session_id"].is_string());
}

#[test]
fn diagnostics_path_reports_shared_log_locations() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");

    let output = morphir_command()
        .args(["diagnostics", "path", "--json"])
        .env("MORPHIR_HOME", &morphir_home)
        .output()
        .expect("failed to run morphir binary");

    assert!(
        output.status.success(),
        "diagnostics path failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let paths: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        paths["morphirHome"],
        morphir_home.to_string_lossy().as_ref()
    );
    assert_eq!(
        paths["logs"],
        morphir_home.join("logs").to_string_lossy().as_ref()
    );
    assert_eq!(
        paths["cliLogs"],
        morphir_home
            .join("logs")
            .join("cli")
            .to_string_lossy()
            .as_ref()
    );
    assert_eq!(
        paths["desktopLogs"],
        morphir_home
            .join("logs")
            .join("desktop")
            .to_string_lossy()
            .as_ref()
    );
}

#[test]
fn diagnostics_path_reports_the_effective_cli_log_directory() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");
    let cli_logs = temp_dir.path().join("managed-cli-logs");

    let output = morphir_command()
        .args(["diagnostics", "path", "--json"])
        .env("MORPHIR_HOME", &morphir_home)
        .env("MORPHIR_LOG_DIR", &cli_logs)
        .output()
        .expect("failed to run morphir binary");

    assert!(output.status.success());
    let paths: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(paths["cliLogs"], cli_logs.to_string_lossy().as_ref());
}

#[test]
fn diagnostics_show_finds_correlated_events_and_redacts_legacy_secrets() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");
    let log_dir = morphir_home.join("logs").join("desktop").join("2026-08-30");
    std::fs::create_dir_all(&log_dir).unwrap();
    let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
    let events = [
        serde_json::json!({
            "timestamp": "2026-08-30T03:04:05Z",
            "level": "INFO",
            "fields": {
                "operation_id": operation_id,
                "event_name": "desktop.session.start",
                "authorization": "Bearer SHOULD_NOT_ESCAPE",
                "apiKey": "CAMEL_API_KEY_SHOULD_NOT_ESCAPE",
                "api_key": "SNAKE_API_KEY_SHOULD_NOT_ESCAPE",
                "accessKey": "ACCESS_KEY_SHOULD_NOT_ESCAPE",
                "credential": "CREDENTIAL_SHOULD_NOT_ESCAPE",
                "message": "retry failed? see https://example.com/status",
                "urls": "https://public.example/status then https://alice:hunter2@private.example/artifact",
                "punctuated_urls": "https://public.example/status,https://bob:password@private.example/artifact",
                "auth_message": "Authorization: Basic dXNlcjpwYXNz"
            }
        }),
        serde_json::json!({
            "timestamp": "2026-08-30T03:04:06Z",
            "level": "INFO",
            "fields": {
                "operation_id": "op-123e4567-e89b-42d3-a456-426614174999",
                "event_name": "unrelated"
            }
        }),
    ];
    std::fs::write(
        log_dir.join("fixture.jsonl"),
        events
            .iter()
            .map(serde_json::Value::to_string)
            .collect::<Vec<_>>()
            .join("\n"),
    )
    .unwrap();

    let output = morphir_command()
        .args(["diagnostics", "show", "--operation", operation_id, "--json"])
        .env("MORPHIR_HOME", &morphir_home)
        .output()
        .expect("failed to run morphir binary");

    assert!(
        output.status.success(),
        "diagnostics show failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let shown: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(shown["operationId"], operation_id);
    assert_eq!(shown["events"].as_array().unwrap().len(), 1);
    assert_eq!(
        shown["events"][0]["fields"]["event_name"],
        "desktop.session.start"
    );
    assert_eq!(shown["events"][0]["fields"]["authorization"], "[REDACTED]");
    for field in ["apiKey", "api_key", "accessKey", "credential"] {
        assert_eq!(shown["events"][0]["fields"][field], "[REDACTED]");
    }
    assert_eq!(
        shown["events"][0]["fields"]["message"],
        "retry failed? see https://example.com/status"
    );
    assert_eq!(
        shown["events"][0]["fields"]["urls"],
        "https://public.example/status then https://[REDACTED]@private.example/artifact"
    );
    assert_eq!(
        shown["events"][0]["fields"]["punctuated_urls"],
        "https://public.example/status,https://[REDACTED]@private.example/artifact"
    );
    assert_eq!(shown["events"][0]["fields"]["auth_message"], "[REDACTED]");
    assert!(!String::from_utf8_lossy(&output.stdout).contains("SHOULD_NOT_ESCAPE"));
    assert!(!String::from_utf8_lossy(&output.stdout).contains("hunter2"));
    assert!(!String::from_utf8_lossy(&output.stdout).contains("dXNlcjpwYXNz"));
}

#[test]
fn diagnostics_show_honors_the_cli_log_directory_override() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");
    let log_dir = temp_dir.path().join("managed-cli-logs");
    let session_dir = log_dir.join("2026-08-30");
    std::fs::create_dir_all(&session_dir).unwrap();
    let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
    std::fs::write(
        session_dir.join("fixture.jsonl"),
        serde_json::json!({
            "timestamp": "2026-08-30T03:04:05Z",
            "level": "INFO",
            "fields": {
                "operation_id": operation_id,
                "event_name": "cli.operation.finish"
            }
        })
        .to_string(),
    )
    .unwrap();

    let output = morphir_command()
        .args(["diagnostics", "show", "--operation", operation_id, "--json"])
        .env("MORPHIR_HOME", &morphir_home)
        .env("MORPHIR_LOG_DIR", &log_dir)
        .output()
        .expect("failed to run morphir binary");

    assert!(output.status.success());
    let shown: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(shown["events"].as_array().unwrap().len(), 1);
    assert_eq!(
        shown["events"][0]["fields"]["event_name"],
        "cli.operation.finish"
    );
}

#[test]
fn diagnostics_collect_creates_an_inspectable_sanitized_archive() {
    use std::io::Read as _;

    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("private-user-home").join(".morphir");
    let cli_log_root = temp_dir.path().join("private-user-logs");
    let private_workspace = temp_dir.path().join("private-workspace").join("model.json");
    let log_dir = cli_log_root.join("2026-08-30");
    std::fs::create_dir_all(&log_dir).unwrap();
    let operation_id = "op-123e4567-e89b-42d3-a456-426614174000";
    std::fs::write(
        log_dir.join("fixture.jsonl"),
        serde_json::json!({
            "timestamp": "2026-08-30T03:04:05Z",
            "level": "ERROR",
            "fields": {
                "operation_id": operation_id,
                "event_name": "tool.resolve",
                "path": morphir_home.join("store/tools").to_string_lossy(),
                "log_path": log_dir.join("fixture.jsonl").to_string_lossy(),
                "diagnostic": format!("failed to open {}", private_workspace.display()),
                "token": "BUNDLE_SECRET_SENTINEL",
                "source_url": "https://alice:hunter2@example.com/artifact"
            }
        })
        .to_string(),
    )
    .unwrap();
    let bundle = temp_dir.path().join("diagnostics.zip");

    let output = morphir_command()
        .args([
            "diagnostics",
            "collect",
            "--operation",
            operation_id,
            "--output",
            bundle.to_str().unwrap(),
        ])
        .env("MORPHIR_HOME", &morphir_home)
        .env("MORPHIR_LOG_DIR", &cli_log_root)
        .output()
        .expect("failed to run morphir binary");

    assert!(
        output.status.success(),
        "diagnostics collect failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let mut archive = zip::ZipArchive::new(std::fs::File::open(&bundle).unwrap()).unwrap();
    let mut entries = std::collections::BTreeMap::new();
    for index in 0..archive.len() {
        let mut entry = archive.by_index(index).unwrap();
        let mut bytes = Vec::new();
        entry.read_to_end(&mut bytes).unwrap();
        entries.insert(entry.name().to_owned(), bytes);
    }
    assert_eq!(
        entries.keys().cloned().collect::<Vec<_>>(),
        ["events.jsonl", "manifest.json", "system.json"]
    );
    let combined = entries.values().flatten().copied().collect::<Vec<_>>();
    let combined = String::from_utf8(combined).unwrap();
    assert!(!combined.contains("BUNDLE_SECRET_SENTINEL"));
    assert!(!combined.contains("alice"));
    assert!(!combined.contains("hunter2"));
    assert!(combined.contains("https://[REDACTED]@example.com/artifact"));
    assert!(!combined.contains(&morphir_home.to_string_lossy().to_string()));
    assert!(combined.contains("$MORPHIR_HOME"));
    assert!(!combined.contains(&cli_log_root.to_string_lossy().to_string()));
    assert!(combined.contains("$MORPHIR_LOG_DIR"));
    assert!(!combined.contains(&private_workspace.to_string_lossy().to_string()));
    assert!(combined.contains("$ABSOLUTE_PATH"));

    let manifest: serde_json::Value = serde_json::from_slice(&entries["manifest.json"]).unwrap();
    assert_eq!(manifest["operationId"], operation_id);
    for included in manifest["includedFiles"].as_array().unwrap() {
        let path = included["path"].as_str().unwrap();
        assert_eq!(
            included["sha256"],
            morphir_distribution::Sha256Digest::of_bytes(&entries[path]).to_string()
        );
    }
    let original = std::fs::read(&bundle).unwrap();
    let second = morphir_command()
        .args([
            "diagnostics",
            "collect",
            "--operation",
            operation_id,
            "--output",
            bundle.to_str().unwrap(),
        ])
        .env("MORPHIR_HOME", &morphir_home)
        .output()
        .unwrap();
    assert!(!second.status.success());
    assert_eq!(std::fs::read(bundle).unwrap(), original);
}

#[test]
fn failed_operation_reports_correlated_id_and_exact_log_path() {
    let temp_dir = TempDir::new().unwrap();
    let morphir_home = temp_dir.path().join("relocated-home");

    let output = morphir_command()
        .args(["tool", "update", "not-installed"])
        .env("MORPHIR_HOME", &morphir_home)
        .env_remove("MORPHIR_LOG_DIR")
        .env("MORPHIR_LOG_FILE", "true")
        .env("MORPHIR_LOGGING__FILE_LEVEL", "error")
        .output()
        .expect("failed to run morphir binary");

    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    let operation_id = stderr
        .lines()
        .find_map(|line| line.strip_prefix("Operation ID: "))
        .expect("failure should report an operation ID");
    let log_path = stderr
        .lines()
        .find_map(|line| line.strip_prefix("Log: "))
        .map(PathBuf::from)
        .expect("failure should report its exact log path");

    assert!(log_path.is_file(), "reported log path should exist");
    let events = std::fs::read_to_string(log_path)
        .unwrap()
        .lines()
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
        .collect::<Vec<_>>();
    assert!(
        events
            .iter()
            .any(|event| event["fields"]["event_name"] == "cli.session.start"),
        "session log should retain its correlation start event at error level"
    );
    let finish = events
        .into_iter()
        .find(|event| event["fields"]["event_name"] == "cli.operation.finish")
        .expect("session log should contain the operation finish event");
    assert_eq!(finish["fields"]["operation_id"], operation_id);
    assert!(finish["fields"]["session_id"].is_string());
    assert_eq!(finish["fields"]["outcome"], "failure");
    assert_eq!(finish["fields"]["exit_code"], 1);
    assert!(
        finish["fields"]["diagnostic"]
            .as_str()
            .is_some_and(|diagnostic| diagnostic.contains("not installed")),
        "finish event should retain the failure diagnostic"
    );
}

#[test]
fn migrate_converts_a_real_v3_file_to_concrete_v4() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let output_path = temp_dir.path().join("greeting-v4.json");

    let output = morphir_command()
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

    let output = morphir_command()
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
        let mut command = morphir_command();
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
    let morphir_home = temp_dir.path().join("home");
    let input = temp_dir.path().join("v2.json");
    let output_path = temp_dir.path().join("result.json");
    let mut source: serde_json::Value = serde_json::from_str(include_str!(
        "../../../website/static/ir/examples/v3/greeting-example.json"
    ))
    .unwrap();
    source["formatVersion"] = 2.into();
    std::fs::write(&input, serde_json::to_vec(&source).unwrap()).unwrap();
    std::fs::write(&output_path, "unchanged").unwrap();

    let output = morphir_command()
        .args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
            "--target-version",
            "v4",
        ])
        .env("MORPHIR_HOME", &morphir_home)
        .env_remove("MORPHIR_LOG_DIR")
        .env("MORPHIR_LOG_FILE", "true")
        .env("MORPHIR_LOGGING__FILE_LEVEL", "error")
        .output()
        .expect("failed to run morphir binary");

    assert!(!output.status.success());
    assert_eq!(std::fs::read_to_string(&output_path).unwrap(), "unchanged");
    let stderr = String::from_utf8_lossy(&output.stderr);
    let operation_id = stderr
        .lines()
        .find_map(|line| line.strip_prefix("Operation ID: "))
        .expect("migration failure should report its operation ID");
    let log_path = stderr
        .lines()
        .find_map(|line| line.strip_prefix("Log: "))
        .map(PathBuf::from)
        .expect("migration failure should report its log path");
    let events = std::fs::read_to_string(log_path).unwrap();
    assert!(events.lines().any(|line| {
        serde_json::from_str::<serde_json::Value>(line).is_ok_and(|event| {
            event["fields"]["operation_id"] == operation_id
                && event["fields"]["event_name"] == "cli.operation.finish"
                && event["fields"]["outcome"] == "failure"
                && event["fields"]["diagnostic"]
                    .as_str()
                    .is_some_and(|diagnostic| !diagnostic.is_empty())
        })
    }));
}

#[test]
fn migrate_reports_unsupported_v4_downgrade_without_replacing_output() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v4/complete-example.json");
    let output_path = temp_dir.path().join("result.json");
    std::fs::write(&output_path, "unchanged").unwrap();

    let output = morphir_command()
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
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(stderr.matches("unsupported_v4_downgrade").count(), 1);
    assert_eq!(std::fs::read_to_string(&output_path).unwrap(), "unchanged");

    let json_output = morphir_command()
        .args([
            "ir",
            "migrate",
            input.to_str().unwrap(),
            "--output",
            output_path.to_str().unwrap(),
            "--target-version",
            "v3",
            "--json",
        ])
        .output()
        .expect("failed to run morphir binary in JSON mode");

    assert!(!json_output.status.success());
    let report: serde_json::Value = serde_json::from_slice(&json_output.stdout).unwrap();
    assert_eq!(report["success"], false);
    assert!(
        report["error"]
            .as_str()
            .is_some_and(|error| error.contains("unsupported_v4_downgrade"))
    );
    assert!(!String::from_utf8_lossy(&json_output.stderr).contains("unsupported_v4_downgrade"));
}

#[test]
fn migrate_writes_and_reads_a_v4_document_tree() {
    let temp_dir = TempDir::new().unwrap();
    let input = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3/greeting-example.json");
    let tree = temp_dir.path().join("greeting.morphir-dist");
    let single_file = temp_dir.path().join("round-trip.json");

    let to_tree = morphir_command()
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

    let to_file = morphir_command()
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

    let output = morphir_command()
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
    let output = morphir_command()
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
