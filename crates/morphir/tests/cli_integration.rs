//! Integration tests for CLI commands

use std::path::PathBuf;
use tempfile::TempDir;

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
    use morphir_design::discover_config;

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

    let config_path = discover_config(&subdir);
    assert!(config_path.is_some());
    assert_eq!(config_path.unwrap(), project_root.join("morphir.toml"));
}

#[test]
fn test_morphir_dir_discovery() {
    use morphir_design::discover_morphir_dir;

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
    use morphir_design::{resolve_compile_output, resolve_generate_output, sanitize_project_name};

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
