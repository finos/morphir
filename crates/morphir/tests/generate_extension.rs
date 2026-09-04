//! End-to-end generation through installed backend extensions.
//!
//! Build the release guest before running the real Avro cases:
//!
//! `cargo build --locked --release --manifest-path ecosystem/morphir-rust/Cargo.toml -p morphir-avro-extension --target wasm32-unknown-unknown`
//! `cargo test -p morphir --test generate_extension -- --ignored`

#[path = "support/mod.rs"]
mod support;

use morphir_distribution::Sha256Digest;
use serde_json::{Value, json};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use support::{
    CliMother, assert_success, ecosystem_crate_version, ecosystem_target_directory, v3_library,
    v4_library,
};

struct AvroCliMother(CliMother);

impl AvroCliMother {
    fn new(guest_path: impl AsRef<Path>) -> Self {
        Self(CliMother::new(
            "morphir-avro",
            "morphir_avro_extension.wasm",
            "Morphir Avro",
            &ecosystem_crate_version("morphir-avro-extension"),
            json!({ "targets": ["avro"], "irVersions": ["3", "4"] }),
            guest_path,
        ))
    }
}

impl std::ops::Deref for AvroCliMother {
    type Target = CliMother;

    fn deref(&self) -> &CliMother {
        &self.0
    }
}

fn avro_guest_path() -> PathBuf {
    ecosystem_target_directory()
        .join("wasm32-unknown-unknown")
        .join("release")
        .join("morphir_avro_extension.wasm")
}

/// The canonical task destination that `output_path` reports. `-o` installs
/// the declared outputs into the requested directory after the run.
fn avro_dest(fixture: &CliMother) -> PathBuf {
    fixture.project.join(".morphir/out/generate/avro.dest")
}

fn assert_generate_shape(value: &Value, success: bool, dest: &Path, installed: Option<&Path>) {
    assert_eq!(value["success"], success);
    assert!(value["artifacts"].is_array(), "{value}");
    assert!(value["diagnostics"].is_array(), "{value}");
    assert_eq!(value["output_path"], dest.to_string_lossy().as_ref());
    match installed {
        Some(installed) => {
            assert_eq!(
                value["installed_path"],
                installed.to_string_lossy().as_ref()
            );
            assert_eq!(value.as_object().unwrap().len(), 5, "{value}");
        }
        None => assert_eq!(value.as_object().unwrap().len(), 4, "{value}"),
    }
}

fn compile_traversal_provider(directory: &Path) -> io::Result<PathBuf> {
    let source = directory.join("traversal_provider.rs");
    let executable = directory.join(format!(
        "traversal-provider{}",
        std::env::consts::EXE_SUFFIX
    ));
    fs::write(&source, include_str!("fixtures/traversal_provider.rs"))?;
    let rustc = std::env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
    let compiled = Command::new(rustc)
        .args(["--edition=2024", "-O"])
        .arg(&source)
        .arg("-o")
        .arg(&executable)
        .output()?;
    if !compiled.status.success() {
        return Err(io::Error::other(format!(
            "failed to compile traversal provider: {}",
            String::from_utf8_lossy(&compiled.stderr)
        )));
    }
    Ok(executable)
}

#[test]
#[ignore = "requires the release Avro WASM guest"]
fn generate_avro_merges_config_and_repeated_cli_options() {
    let fixture = AvroCliMother::new(avro_guest_path());
    let config = fixture.write_config(
        r#"
[project]
name = "Acme.Customer"
version = "1.0.0"

[codegen]
targets = ["avro"]

[codegen.avro]
representation = "json"
projection = "schemas"
unsupported = "warn-and-skip"
"#,
    );
    let input = fixture.write_ir("v4.json", &v4_library());
    let output_root = fixture.project.join("idl-output");
    fixture.install_verified_wasm();

    let generated = fixture.run(&[
        "generate",
        "--target",
        "avro",
        "--input",
        input.to_str().unwrap(),
        "--output",
        output_root.to_str().unwrap(),
        "--config",
        config.to_str().unwrap(),
        "--option",
        "representation=json",
        "--option",
        "representation=idl",
        "--option",
        "projection=protocol-public",
        "--option",
        r#"type_mappings={"morphir/sdk:string#string":{"type":"bytes"},"morphir/sdk:basics#int":{"type":"double"}}"#,
        "--json",
    ]);

    assert_success(&generated, "generate v4 Avro IDL");
    let report: Value = serde_json::from_slice(&generated.stdout).unwrap();
    assert_generate_shape(&report, true, &avro_dest(&fixture), Some(&output_root));
    assert_eq!(
        report["artifacts"],
        json!([
            "example/v4Test/Domain.avdl",
            "example/v4Test/domain/UserIdSchemas.avdl"
        ])
    );
    let artifact = output_root.join("example/v4Test/Domain.avdl");
    assert!(artifact.exists(), "reported artifact should be published");
    assert!(
        output_root
            .join("example/v4Test/domain/UserIdSchemas.avdl")
            .exists(),
        "standalone named roots should be published alongside protocols"
    );
    let idl = fs::read_to_string(artifact).unwrap();
    assert!(idl.contains("bytes getUserName("), "{idl}");
    assert!(idl.contains("double nativeAdd("), "{idl}");

    let human_output_root = fixture.project.join("human-idl-output");
    let human = fixture.run(&[
        "generate",
        "--target",
        "avro",
        "--input",
        input.to_str().unwrap(),
        "--output",
        human_output_root.to_str().unwrap(),
        "--config",
        config.to_str().unwrap(),
        "--option",
        "representation=idl",
        "--option",
        "projection=protocol-public",
    ]);
    assert_success(&human, "generate human-reported v4 Avro IDL");
    let stdout = String::from_utf8(human.stdout).unwrap();
    assert!(stdout.contains("example/v4Test/Domain.avdl"), "{stdout}");
}

#[test]
#[ignore = "requires the release Avro WASM guest"]
fn generate_avro_supports_v3_json_and_json_lines_reporting() {
    let fixture = AvroCliMother::new(avro_guest_path());
    let config = fixture.write_config(
        "[project]\nname = \"Greeting\"\nversion = \"1.0.0\"\n\n[codegen]\ntargets = [\"avro\"]\n",
    );
    let input = fixture.write_ir("v3.json", &v3_library());
    let output_root = fixture.project.join("json-output");
    fixture.install_verified_wasm();

    let generated = fixture.run(&[
        "generate",
        "--target",
        "avro",
        "--input",
        input.to_str().unwrap(),
        "--output",
        output_root.to_str().unwrap(),
        "--config",
        config.to_str().unwrap(),
        "--option",
        "representation=json",
        "--option",
        "projection=schemas",
        "--option",
        "unsupported=warn-and-skip",
        "--json-lines",
    ]);

    assert_success(&generated, "generate v3 Avro JSON");
    let stdout = String::from_utf8(generated.stdout).unwrap();
    assert_eq!(stdout.lines().count(), 1, "{stdout}");
    let report: Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_generate_shape(&report, true, &avro_dest(&fixture), Some(&output_root));
    let paths = report["artifacts"].as_array().unwrap();
    assert!(!paths.is_empty(), "{report}");
    assert!(
        paths
            .iter()
            .all(|path| path.as_str().unwrap().ends_with(".avsc")),
        "{report}"
    );
    assert!(
        paths
            .iter()
            .all(|path| output_root.join(path.as_str().unwrap()).is_file())
    );
}

#[test]
#[ignore = "requires the release Avro WASM guest"]
fn generate_avro_reports_typed_failure_without_artifact_writes() {
    let fixture = AvroCliMother::new(avro_guest_path());
    let config = fixture.write_config(
        "[project]\nname = \"Acme.Customer\"\nversion = \"1.0.0\"\n\n[codegen]\ntargets = [\"avro\"]\n",
    );
    let input = fixture.write_ir("v4.json", &v4_library());
    let output_root = fixture.project.join("must-not-exist");
    fixture.install_verified_wasm();

    let failed = fixture.run(&[
        "generate",
        "--target",
        "avro",
        "--input",
        input.to_str().unwrap(),
        "--output",
        output_root.to_str().unwrap(),
        "--config",
        config.to_str().unwrap(),
        "--option",
        "decimal_precision=0",
        "--json",
    ]);

    assert!(!failed.status.success());
    let report: Value = serde_json::from_slice(&failed.stdout).unwrap();
    assert_generate_shape(&report, false, &avro_dest(&fixture), None);
    assert_eq!(report["artifacts"], json!([]));
    assert_eq!(report["diagnostics"][0]["level"], "error");
    assert_eq!(report["diagnostics"][0]["code"], "AVRO004");
    assert!(
        report["diagnostics"][0]["message"]
            .as_str()
            .unwrap()
            .contains("decimal_precision")
    );
    assert!(
        !output_root.exists(),
        "failed generation must not create output"
    );

    let human = fixture.run(&[
        "generate",
        "--target",
        "avro",
        "--input",
        input.to_str().unwrap(),
        "--output",
        output_root.to_str().unwrap(),
        "--config",
        config.to_str().unwrap(),
        "--option",
        "decimal_precision=0",
    ]);
    assert!(!human.status.success());
    let stderr = String::from_utf8(human.stderr).unwrap();
    assert!(stderr.contains("AVRO004"), "{stderr}");
    assert!(stderr.contains("decimal_precision"), "{stderr}");
    assert!(
        !output_root.exists(),
        "failed generation must not create output"
    );
}

#[test]
#[ignore = "requires the release Avro WASM guest"]
fn generate_avro_partial_output_reports_warnings_and_validated_paths() {
    let fixture = AvroCliMother::new(avro_guest_path());
    let config = fixture.write_config(
        "[project]\nname = \"Acme.Customer\"\nversion = \"1.0.0\"\n\n[codegen]\ntargets = [\"avro\"]\n",
    );
    let mut ir = v4_library();
    ir["distribution"]["Library"]["def"]["modules"]["domain"]["value"]["types"]["incomplete-user"]
        ["access"] = json!("Public");
    let input = fixture.write_ir("partial-v4.json", &ir);
    let output_root = fixture.project.join("partial-output");
    fixture.install_verified_wasm();

    let generated = fixture.run(&[
        "generate",
        "--target",
        "avro",
        "--input",
        input.to_str().unwrap(),
        "--output",
        output_root.to_str().unwrap(),
        "--config",
        config.to_str().unwrap(),
        "--option",
        "projection=schemas",
        "--option",
        "unsupported=warn-and-skip",
        "--option",
        r#"type_mappings={"morphir/sdk:string#string":{"type":"string"}}"#,
        "--json",
    ]);

    assert_success(&generated, "generate partial v4 output");
    let report: Value = serde_json::from_slice(&generated.stdout).unwrap();
    assert_generate_shape(&report, true, &avro_dest(&fixture), Some(&output_root));
    assert!(
        !report["artifacts"].as_array().unwrap().is_empty(),
        "{report}"
    );
    let incomplete_warning = report["diagnostics"]
        .as_array()
        .unwrap()
        .iter()
        .find(|diagnostic| {
            diagnostic["uri"] == "morphir-fqname:example/v4-test:domain#incomplete-user"
        })
        .unwrap_or_else(|| panic!("missing incomplete-user warning: {report}"));
    assert_eq!(incomplete_warning["level"], "warning");
    assert_eq!(incomplete_warning["code"], "AVRO001");
    assert_eq!(
        incomplete_warning["message"],
        "unsupported Morphir type: example/v4-test:domain#incomplete-user"
    );
    for path in report["artifacts"].as_array().unwrap() {
        let artifact = output_root.join(path.as_str().unwrap());
        assert!(artifact.is_file());
        let content = fs::read_to_string(artifact).unwrap();
        assert!(!content.contains("incomplete-user"), "{content}");
        assert!(!content.contains("IncompleteUser"), "{content}");
    }
}

#[test]
fn generate_rejects_traversal_from_an_installed_provider_without_writing()
-> Result<(), Box<dyn std::error::Error>> {
    let root = tempfile::tempdir().unwrap();
    let project = root.path().join("project");
    let home = root.path().join("home");
    let index = root.path().join("index");
    fs::create_dir_all(&project).unwrap();
    let compiled = compile_traversal_provider(root.path())?;
    let filename = compiled.file_name().unwrap().to_string_lossy().into_owned();
    let relative_source = format!("artifacts/{filename}");
    let artifact = index.join(&relative_source);
    fs::create_dir_all(artifact.parent().unwrap()).unwrap();
    fs::create_dir_all(index.join("extensions")).unwrap();
    fs::copy(&compiled, &artifact).unwrap();
    let bytes = fs::read(&artifact).unwrap();
    let record = json!({
        "schemaVersion": "1.0",
        "id": "traversal-provider",
        "name": "Traversal Provider",
        "version": "1.0.0",
        "channels": ["stable"],
        "mepVersions": ["0.1"],
        "capabilities": ["backend"],
        "backend": { "targets": ["unsafe-test"], "irVersions": ["4"] },
        "artifacts": [{
            "runtime": "process",
            "platform": { "os": std::env::consts::OS, "arch": std::env::consts::ARCH },
            "source": { "kind": "local-file", "path": relative_source },
            "sha256": Sha256Digest::of_bytes(&bytes),
            "filename": filename,
            "args": [],
            "executable": true
        }]
    });
    fs::write(
        index.join("extensions/traversal-provider.jsonl"),
        format!("{record}\n"),
    )
    .unwrap();
    let run = |arguments: &[&str]| {
        Command::new(env!("CARGO_BIN_EXE_morphir"))
            .args(arguments)
            .env("MORPHIR_HOME", &home)
            .current_dir(&project)
            .output()
            .unwrap()
    };
    let add = run(&[
        "extension",
        "repository",
        "add",
        "local-dev",
        "--directory",
        index.to_str().unwrap(),
    ]);
    assert_success(&add, "add traversal provider repository");
    let install = run(&[
        "extension",
        "install",
        "traversal-provider",
        "--repository",
        "local-dev",
    ]);
    assert_success(&install, "install traversal provider");
    let config = project.join("morphir.toml");
    fs::write(
        &config,
        "[project]\nname = \"Containment\"\nversion = \"1.0.0\"\n\n[codegen]\ntargets = [\"unsafe-test\"]\n",
    )
    .unwrap();
    let input = project.join("v4.json");
    fs::write(&input, serde_json::to_vec(&v4_library()).unwrap()).unwrap();
    let output_root = project.join("output");
    let escaped = project.join("escape.avsc");

    let generated = run(&[
        "generate",
        "--target",
        "unsafe-test",
        "--input",
        input.to_str().unwrap(),
        "--output",
        output_root.to_str().unwrap(),
        "--config",
        config.to_str().unwrap(),
        "--json",
    ]);

    assert!(!generated.status.success());
    assert!(
        !escaped.exists(),
        "provider path must not escape output root"
    );
    assert!(
        !output_root.exists(),
        "rejected artifact set must write nothing"
    );
    let stderr = String::from_utf8(generated.stderr).unwrap();
    assert!(stderr.contains("Generated artifact path"), "{stderr}");
    assert!(stderr.contains("escape.avsc"), "{stderr}");
    assert!(stderr.contains("normalized relative path"), "{stderr}");
    Ok(())
}
