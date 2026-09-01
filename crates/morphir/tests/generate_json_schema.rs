//! End-to-end coverage for the morphir-openapi extension.
//!
//! Build the guest first:
//!
//! `cargo build --locked --release --manifest-path ecosystem/morphir-rust/Cargo.toml -p morphir-openapi-extension --target wasm32-unknown-unknown`

#[path = "support/mod.rs"]
mod support;

use serde_json::{Value, json};
use std::path::{Path, PathBuf};
use std::process::Output;
use support::{CliMother, ecosystem_target_directory};

struct OpenApiCliMother(CliMother);

impl OpenApiCliMother {
    fn new(guest_path: impl AsRef<Path>) -> Self {
        Self(CliMother::new(
            "morphir-openapi",
            "morphir_openapi_extension.wasm",
            "Morphir OpenAPI",
            json!({ "targets": ["openapi", "json-schema"], "irVersions": ["3", "4"] }),
            guest_path,
        ))
    }

    /// Install the guest, write a default project and IR, and run
    /// `generate` with `arguments` (e.g. `["--target", "json-schema"]`)
    /// appended to the standard `--input`/`--output`/`--config` flags.
    fn generate(&self, arguments: &[&str]) -> Output {
        self.install_verified_wasm();
        let config =
            self.write_config("[project]\nname = \"Acme.Customer\"\nversion = \"1.0.0\"\n");
        let input = self.write_ir("classic-schema-library.json", &classic_schema_library());
        let output_root = self.output_dir();

        let mut command_arguments: Vec<&str> = vec!["generate"];
        command_arguments.extend_from_slice(arguments);
        let input = input.to_str().unwrap();
        let output_root_str = output_root.to_str().unwrap();
        let config = config.to_str().unwrap();
        command_arguments.extend([
            "--input",
            input,
            "--output",
            output_root_str,
            "--config",
            config,
        ]);
        self.run(&command_arguments)
    }

    fn output_dir(&self) -> PathBuf {
        self.project.join("generated")
    }
}

impl std::ops::Deref for OpenApiCliMother {
    type Target = CliMother;

    fn deref(&self) -> &CliMother {
        &self.0
    }
}

/// The Classic-format library `morphir-openapi-extension`'s own golden
/// tests already prove renders cleanly: a record alias, an optional field,
/// a sibling reference, and a nullary custom type. Reusing it here (rather
/// than the Avro suite's IR) keeps this an end-to-end dispatch test, not a
/// fresh exercise of the projection itself. The Avro suite's fixture spells
/// the SDK package non-canonically as `morphir/sdk`, which resolves to a
/// different package identity than the real `morphir/SDK`, so it does not
/// exercise this backend's SDK type mappings the way real IR does.
fn classic_schema_library() -> Value {
    serde_json::from_str(include_str!("fixtures/openapi/classic-schema-library.json")).unwrap()
}

fn openapi_guest_path() -> PathBuf {
    ecosystem_target_directory()
        .join("wasm32-unknown-unknown")
        .join("release")
        .join("morphir_openapi_extension.wasm")
}

#[test]
#[ignore = "requires the release morphir-openapi WASM guest"]
fn generates_json_schema_through_the_installed_extension() {
    let fixture = OpenApiCliMother::new(openapi_guest_path());

    let output = fixture.generate(&["--target", "json-schema"]);

    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let generated = fixture.output_dir();
    let documents: Vec<_> = std::fs::read_dir(&generated)
        .expect("the output directory exists")
        .filter_map(Result::ok)
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| name.ends_with(".schema.json"))
        .collect();
    assert!(
        !documents.is_empty(),
        "no schema documents in {generated:?}"
    );
}

#[test]
#[ignore = "requires the release morphir-openapi WASM guest"]
fn selects_the_extension_by_target_rather_than_by_id() {
    let fixture = OpenApiCliMother::new(openapi_guest_path());

    let output = fixture.generate(&["--target", "not-a-target"]);

    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    // `morphir-openapi` is installed and advertises `openapi` and
    // `json-schema`, not `not-a-target`, so the host must not dispatch to
    // it: it falls through to the legacy-builtin lookup, which also has no
    // match, and reports the target as unresolved.
    assert!(
        stderr.contains("No extension found for target: not-a-target"),
        "{stderr}"
    );
}
