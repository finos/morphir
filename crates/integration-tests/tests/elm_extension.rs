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

const MALFORMED_HEADER_ELM: &str = r#"module Malformed


value = 1
"#;

#[derive(Debug, Deserialize)]
struct CompileOutput {
    success: bool,
    ir: Option<serde_json::Value>,
    diagnostics: Vec<CompileDiagnostic>,
    modules: Vec<String>,
    output_path: String,
    /// Absolute install target, present only when `-o` was given and the
    /// compile succeeded.
    installed_path: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CompileDiagnostic {
    level: String,
    code: Option<String>,
    file: Option<String>,
    uri: Option<String>,
    range: Option<serde_json::Value>,
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

/// The task's canonical output, which is where compile always writes its IR:
/// `-o` only installs a copy of it afterwards.
fn canonical_ir_path(directory: &Path) -> PathBuf {
    directory.join(".morphir/out/compile.dest/morphir-ir.json")
}

/// The task's result record, beside that `.dest` directory.
fn result_record_path(directory: &Path) -> PathBuf {
    directory.join(".morphir/out/compile.json")
}

fn run_elm_compile(
    directory: &Path,
    extension: &Path,
    source_name: &str,
    source: &str,
) -> (Output, PathBuf) {
    run_elm_compile_with_output_flag(directory, extension, source_name, source, "--json")
}

/// Run `morphir compile` on one Elm file, returning the process output and the
/// directory `-o` pointed at.
///
/// `-o` names an install DIRECTORY, not an output file: the task always runs to
/// `.morphir/out/compile.dest/`, and `-o` copies its product into the directory
/// afterwards.
fn run_elm_compile_with_output_flag(
    directory: &Path,
    extension: &Path,
    source_name: &str,
    source: &str,
    output_flag: &str,
) -> (Output, PathBuf) {
    let input_path = directory.join(source_name);
    let install_target = directory.join("out");
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
            install_target.to_str().expect("UTF-8 install target"),
            output_flag,
        ])
        .current_dir(directory)
        .env("MORPHIR_HOME", directory.join(".morphir-home"))
        .output()
        .expect("run morphir compile");

    (output, install_target)
}

/// A failed compile writes no IR anywhere: not to the canonical location under
/// the out root, and not to the `-o` install target, which install never even
/// reaches.
fn assert_no_ir_was_written(directory: &Path, install_target: &Path) {
    assert!(
        !canonical_ir_path(directory).exists(),
        "failed compile should not write canonical IR"
    );
    assert!(
        !install_target.join("morphir-ir.json").exists(),
        "failed compile should not install IR"
    );
}

/// `std::fs::canonicalize`, falling back to the path itself when it does not
/// exist, so a failing assertion still names something readable.
fn canonicalize(path: &Path) -> PathBuf {
    std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
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
    let (process, install_target) =
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

    // `output_path` reports the task's canonical `.dest` directory, not the
    // IR file inside it — the same thing `generate` reports — which is under
    // the out root and not the `-o` target.
    let reported = PathBuf::from(&output.output_path);
    assert!(
        reported.ends_with(Path::new(".morphir/out/compile.dest")),
        "output_path should name the canonical task .dest directory, got {}",
        output.output_path
    );
    assert!(
        canonicalize(&reported).starts_with(canonicalize(temp_dir.path())),
        "output_path should sit under the project, got {}",
        output.output_path
    );
    assert!(
        canonical_ir_path(temp_dir.path()).is_file(),
        "the canonical IR file should exist under the out root"
    );
    let ir_via_output_path: serde_json::Value = serde_json::from_slice(
        &std::fs::read(reported.join("morphir-ir.json")).expect("read IR via output_path"),
    )
    .expect("IR under output_path should be JSON");
    assert_eq!(
        Some(ir_via_output_path),
        output.ir,
        "the IR reachable via output_path should be the same IR the CLI reported inline"
    );

    // `installed_path` reports where `-o` put the copy. The CLI canonicalizes
    // the target, so both sides are canonicalized before comparing: on macOS a
    // temporary directory's /var resolves to /private/var.
    let installed_path = output
        .installed_path
        .as_deref()
        .expect("compile with -o should report installed_path");
    assert_eq!(
        canonicalize(Path::new(installed_path)),
        canonicalize(&install_target)
    );

    // The result record survives the run and is a real result, not a tombstone.
    let record: serde_json::Value = serde_json::from_slice(
        &std::fs::read(result_record_path(temp_dir.path())).expect("read compile.json"),
    )
    .expect("compile.json should be JSON");
    assert!(
        record.get("tombstone").is_none(),
        "a successful run leaves no tombstone flag: {record}"
    );
    assert!(
        record.get("ir").is_some(),
        "a successful compile record names its IR: {record}"
    );

    // The installed copy is the one a user consumes, so validate that one.
    let installed_ir = install_target.join("morphir-ir.json");
    let distribution: Distribution = serde_json::from_slice(
        &std::fs::read(&installed_ir).expect("read installed morphir-ir.json"),
    )
    .expect("installed file should contain classic Morphir IR");
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
    let (process, install_target) =
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
    assert_no_ir_was_written(temp_dir.path(), &install_target);
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

#[test]
#[ignore = "requires the independently built morphir-elm-extension executable"]
fn elm_extension_diagnoses_a_malformed_module_header_in_structured_output() {
    let extension = elm_extension_binary();

    for output_flag in ["--json", "--json-lines"] {
        let temp_dir = TempDir::new().expect("create temporary project");
        let (process, install_target) = run_elm_compile_with_output_flag(
            temp_dir.path(),
            &extension,
            "Malformed.elm",
            MALFORMED_HEADER_ELM,
            output_flag,
        );

        assert!(
            !process.status.success(),
            "malformed Elm unexpectedly compiled with {output_flag}\nstdout:\n{}",
            String::from_utf8_lossy(&process.stdout)
        );
        let output = parse_compile_output(&process);
        assert!(!output.success, "CompileOutput should report failure");
        assert!(output.ir.is_none(), "failed compile should not contain IR");
        assert!(
            output.modules.is_empty(),
            "failed compile should not contain modules"
        );
        assert_no_ir_was_written(temp_dir.path(), &install_target);

        let diagnostic = output
            .diagnostics
            .iter()
            .find(|diagnostic| diagnostic.level == "error")
            .expect("an Elm error diagnostic");
        assert_eq!(diagnostic.code.as_deref(), Some("elm.parser"));
        assert!(
            diagnostic
                .file
                .as_deref()
                .or(diagnostic.uri.as_deref())
                .is_some_and(|location| location.contains("Malformed.elm")),
            "the parser diagnostic should identify Malformed.elm"
        );
        assert!(
            diagnostic.range.is_some(),
            "the parser diagnostic should retain its source range"
        );
    }
}
