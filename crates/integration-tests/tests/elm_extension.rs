use integration_tests::CliTestContext;
use morphir_core::ir::classic::{Distribution, DistributionBody};
use serde::Deserialize;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use tempfile::TempDir;

const VALID_ELM: &str = r#"module Example exposing (add)


add : Int -> Int -> Int
add left right =
    left + right
"#;

const INVALID_ELM: &str = r#"module Invalid exposing (broken)


broken : Int
broken =
"#;

#[derive(Debug, Deserialize)]
struct CompileOutput {
    success: bool,
    ir: Option<serde_json::Value>,
    diagnostics: Vec<CompileDiagnostic>,
    modules: Vec<String>,
    output_path: String,
}

#[derive(Debug, Deserialize)]
struct CompileDiagnostic {
    level: String,
    file: Option<String>,
    uri: Option<String>,
}

fn elm_extension_binary() -> PathBuf {
    std::env::var_os("MORPHIR_ELM_EXTENSION_BIN")
        .map(PathBuf::from)
        .expect("MORPHIR_ELM_EXTENSION_BIN should point at morphir-elm-extension")
}

fn write_elm_extension_config(directory: &Path, extension: &Path) -> PathBuf {
    let config_path = directory.join("morphir.toml");
    let command = toml::Value::String(extension.to_string_lossy().into_owned());
    std::fs::write(
        &config_path,
        format!("[extensions.morphir-elm]\ncommand = {command}\nenabled = true\n"),
    )
    .expect("write morphir.toml");
    config_path
}

fn run_elm_compile(
    directory: &Path,
    extension: &Path,
    source_name: &str,
    source: &str,
) -> (Output, PathBuf) {
    let input_path = directory.join(source_name);
    let output_path = directory.join("morphir-ir.json");
    let config_path = write_elm_extension_config(directory, extension);
    std::fs::write(&input_path, source).expect("write Elm input");
    let cli = CliTestContext::get_morphir_binary().expect("find pre-built morphir CLI");

    let output = Command::new(cli)
        .args([
            "compile",
            "--input",
            input_path.to_str().expect("UTF-8 input path"),
            "--language",
            "elm",
            "--config",
            config_path.to_str().expect("UTF-8 config path"),
            "--output",
            output_path.to_str().expect("UTF-8 output path"),
            "--json",
        ])
        .current_dir(directory)
        .output()
        .expect("run morphir compile");

    (output, output_path)
}

fn parse_compile_output(output: &Output) -> CompileOutput {
    serde_json::from_slice(&output.stdout).unwrap_or_else(|error| {
        panic!(
            "stdout was not CompileOutput JSON: {error}\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        )
    })
}

#[test]
#[ignore = "requires the independently built morphir-elm-extension executable"]
fn elm_extension_compiles_a_single_file_to_classic_ir() {
    let extension = elm_extension_binary();
    let temp_dir = TempDir::new().expect("create temporary project");
    let (process, output_path) =
        run_elm_compile(temp_dir.path(), &extension, "Example.elm", VALID_ELM);

    assert!(
        process.status.success(),
        "compile failed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&process.stdout),
        String::from_utf8_lossy(&process.stderr)
    );
    let output = parse_compile_output(&process);
    assert!(output.success, "CompileOutput reported failure");
    assert!(
        output.ir.is_some(),
        "CompileOutput should contain classic IR"
    );
    assert!(output.diagnostics.iter().all(|item| item.level != "error"));
    assert!(output.modules.iter().any(|module| module == "Example"));
    assert_eq!(Path::new(&output.output_path), output_path);

    let distribution: Distribution = serde_json::from_slice(
        &std::fs::read(&output_path).expect("read generated morphir-ir.json"),
    )
    .expect("output file should contain classic Morphir IR");
    let DistributionBody::Library(_, _, package) = distribution.distribution;
    assert!(
        package.modules.iter().any(|module| {
            module.path.segments.len() == 1
                && module.path.segments[0]
                    .to_string()
                    .eq_ignore_ascii_case("Example")
        }),
        "classic IR should contain module Example"
    );
}

#[test]
#[ignore = "requires the independently built morphir-elm-extension executable"]
fn elm_extension_reports_structured_diagnostics_for_invalid_source() {
    let extension = elm_extension_binary();
    let temp_dir = TempDir::new().expect("create temporary project");
    let (process, output_path) =
        run_elm_compile(temp_dir.path(), &extension, "Invalid.elm", INVALID_ELM);

    assert!(
        !process.status.success(),
        "invalid Elm unexpectedly compiled\nstdout:\n{}",
        String::from_utf8_lossy(&process.stdout)
    );
    let output = parse_compile_output(&process);
    assert!(!output.success, "CompileOutput should report failure");
    assert!(output.ir.is_none(), "failed compile should not contain IR");
    assert!(
        output.modules.is_empty(),
        "failed compile should not contain modules"
    );
    assert!(!output_path.exists(), "failed compile should not write IR");
    assert!(
        output.diagnostics.iter().any(|diagnostic| {
            diagnostic.level == "error"
                && diagnostic
                    .file
                    .as_deref()
                    .or(diagnostic.uri.as_deref())
                    .is_some_and(|location| location.contains("Invalid.elm"))
        }),
        "an error diagnostic should identify Invalid.elm"
    );
}
