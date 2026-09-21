//! Characterization tests for single-file compilation's package-name and
//! exposure derivation, as performed by the CLI today. A later refactor moves
//! this derivation out of the CLI and into the language provider; these tests
//! pin today's observed behaviour by driving the real `morphir` binary so
//! that move can be verified against them.

use std::{fs, process::Command};

/// Runs the `morphir` binary in `dir` with `args`, returning
/// `(success, stdout, stderr)`.
fn morphir(dir: &std::path::Path, args: &[&str]) -> (bool, String, String) {
    let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args(args)
        .current_dir(dir)
        .env("MORPHIR_HOME", dir.join("home"))
        .output()
        .unwrap();
    (
        output.status.success(),
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).into_owned(),
    )
}

/// Reads and parses the classic v3 IR written by a compile:
/// `.morphir/out/compile.dest/morphir-ir.json`.
fn distribution(dir: &std::path::Path) -> serde_json::Value {
    let bytes = fs::read(dir.join(".morphir/out/compile.dest/morphir-ir.json")).unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

/// A lone file's package name is derived from its declared module name,
/// lowercased with dots replaced by dashes, under `local/`. Its exposure is
/// exactly that one module. Pinned because the refactor moves this derivation
/// into the language provider.
#[test]
fn a_synthesized_package_is_named_for_its_declared_module() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(
        dir.join("Widget.elm"),
        "module Acme.Widget exposing (Size)\n\n\ntype alias Size =\n    Int\n",
    )
    .unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &["compile", "--input", "Widget.elm", "--extension", "morphir-elm-native"],
    );
    assert!(ok, "{err}");

    let ir = distribution(dir);
    // Observed: the module name `Acme.Widget` is split on `.`, each part
    // lowercased into its own single-word path segment, and the whole thing
    // nested under a `local` package segment:
    //   packagePath = [["local"], ["acme", "widget"]]
    assert_eq!(
        ir["distribution"][1],
        serde_json::json!([["local"], ["acme", "widget"]])
    );

    let modules = ir["distribution"][3]["modules"].as_array().unwrap();
    assert_eq!(modules.len(), 1, "expected exactly one exposed module");
    // The module's own name mirrors the same per-part word-list shape:
    // [["acme"], ["widget"]].
    assert_eq!(modules[0][0], serde_json::json!([["acme"], ["widget"]]));
    assert_eq!(modules[0][1]["access"], "Public");
}

/// A file with no parseable `module` declaration does NOT fall back to the
/// file stem: compilation fails outright with a "missing module declaration"
/// error. Pinned as observed, even though it contradicts the "falls back to
/// the file stem" assumption in the task brief.
#[test]
fn a_file_without_a_module_declaration_fails_to_compile() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(dir.join("Gadget.elm"), "x = 1\n").unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &["compile", "--input", "Gadget.elm", "--extension", "morphir-elm-native"],
    );
    assert!(!ok, "expected compilation to fail, but it succeeded");
    assert!(
        err.contains("missing module declaration"),
        "unexpected stderr: {err}"
    );
}

/// A file whose stem is not a legal module name (`not-a-module.elm`) fails
/// the same way as the missing-declaration case above, for the same reason:
/// the built-in `morphir-elm-native` provider parses the raw source with
/// tree-sitter and requires a real `module ... exposing (...)` declaration
/// regardless of the CLI's own file-stem-based fallback naming. The CLI does
/// have a `fallback_elm_module_name` that would land on `"Main"` for an
/// illegal stem (see `crates/morphir/src/commands/compile.rs`), but that
/// fallback name is only used to build the `--package-name`/exposed-module
/// request sent to the provider; it never gets a chance to matter here
/// because the provider rejects the source before that name is ever used.
/// Pinned as observed, even though the brief's premise ("falls back to
/// `Main`, and compiles") does not hold end-to-end through this provider.
#[test]
fn a_file_with_an_illegal_stem_and_no_module_declaration_fails_to_compile() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(dir.join("not-a-module.elm"), "x = 1\n").unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &["compile", "--input", "not-a-module.elm", "--extension", "morphir-elm-native"],
    );
    assert!(!ok, "expected compilation to fail, but it succeeded");
    assert!(
        err.contains("missing module declaration"),
        "unexpected stderr: {err}"
    );
}

/// `--package-name acme/widgets` overrides the synthesized package path
/// entirely: each `/`-separated part becomes its own single-word path
/// segment (`[["acme"], ["widgets"]]`), independent of the module's own dots.
/// Module exposure is unchanged: still exactly the one declared module,
/// `Acme.Widget`, still `Public`.
#[test]
fn a_package_name_override_replaces_the_path_but_not_the_exposure() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(
        dir.join("Widget.elm"),
        "module Acme.Widget exposing (Size)\n\n\ntype alias Size =\n    Int\n",
    )
    .unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &[
            "compile",
            "--input",
            "Widget.elm",
            "--extension",
            "morphir-elm-native",
            "--package-name",
            "acme/widgets",
        ],
    );
    assert!(ok, "{err}");

    let ir = distribution(dir);
    assert_eq!(
        ir["distribution"][1],
        serde_json::json!([["acme"], ["widgets"]])
    );

    let modules = ir["distribution"][3]["modules"].as_array().unwrap();
    assert_eq!(modules.len(), 1, "expected exactly one exposed module");
    assert_eq!(modules[0][0], serde_json::json!([["acme"], ["widget"]]));
    assert_eq!(modules[0][1]["access"], "Public");
}
