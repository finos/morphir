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

/// `--input` inside a project keeps the project's package name while exposing
/// only the submitted module. This is the "isolated compile borrowing the
/// project's identity" case: the project's other sources are NOT compiled and
/// NOT available for import resolution.
#[test]
fn a_selection_inside_a_project_keeps_project_identity_and_narrows_exposure() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::create_dir_all(dir.join("src")).unwrap();
    fs::write(
        dir.join("morphir.toml"),
        "[project]\nname = 'acme/widgets'\nversion = '1.0.0'\nsource_directory = 'src'\nexposed_modules = ['A', 'B']\n\n[frontend]\nlanguage = 'elm'\n\n[frontend.elm]\nextension = 'morphir-elm-native'\n",
    )
    .unwrap();
    fs::write(dir.join("src/A.elm"), "module A exposing (Alpha)\n\n\ntype alias Alpha =\n    Int\n").unwrap();
    fs::write(dir.join("src/B.elm"), "module B exposing (Beta)\n\n\ntype alias Beta =\n    Int\n").unwrap();

    // `--config` is required: a standalone `--input` compile does not load an
    // adjacent morphir.toml. It is also what makes this the manifest-origin
    // case at all, since the spec's manifest origin means "selected or loaded".
    let (ok, _out, err) = morphir(dir, &["compile", "--input", "src/A.elm", "--config", "morphir.toml"]);
    assert!(ok, "{err}");

    let ir = distribution(dir);
    // Observed: the package path comes from the project's manifest name
    // (`acme/widgets`, split on `/`), NOT from the selected module's own
    // dotted name — this is the "borrows the project's identity" behaviour.
    assert_eq!(
        ir["distribution"][1],
        serde_json::json!([["acme"], ["widgets"]])
    );

    let modules = ir["distribution"][3]["modules"].as_array().unwrap();
    let module_names: Vec<_> = modules.iter().map(|m| m[0].clone()).collect();
    // Observed: exactly the selected module `A` (word-list `[["a"]]`) is
    // exposed. The negative assertion matters more than the positive one:
    // `B`, though listed in the manifest's `exposed_modules` and present on
    // disk in the same source directory, is NOT compiled or exposed, because
    // only the module named by `--input` was ever submitted.
    assert_eq!(
        module_names,
        vec![serde_json::json!([["a"]])],
        "expected exactly module A, got {module_names:?}"
    );
    assert!(
        !module_names.contains(&serde_json::json!([["b"]])),
        "unselected sibling module B must not appear in exposure, got {module_names:?}"
    );
}

/// A selected file's `import` of an unselected sibling module from the same
/// project must NOT resolve: the project's other sources are never submitted
/// to the provider for a single-file `--input` compile, even though the
/// manifest lists them and they sit right next to the selected file on disk.
#[test]
fn a_selection_cannot_import_an_unselected_sibling_module() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::create_dir_all(dir.join("src")).unwrap();
    fs::write(
        dir.join("morphir.toml"),
        "[project]\nname = 'acme/widgets'\nversion = '1.0.0'\nsource_directory = 'src'\nexposed_modules = ['A', 'B']\n\n[frontend]\nlanguage = 'elm'\n\n[frontend.elm]\nextension = 'morphir-elm-native'\n",
    )
    .unwrap();
    fs::write(
        dir.join("src/A.elm"),
        "module A exposing (Alpha)\n\nimport B exposing (Beta)\n\n\ntype alias Alpha =\n    Beta\n",
    )
    .unwrap();
    fs::write(dir.join("src/B.elm"), "module B exposing (Beta)\n\n\ntype alias Beta =\n    Int\n").unwrap();

    let (ok, _out, err) = morphir(dir, &["compile", "--input", "src/A.elm", "--config", "morphir.toml"]);
    // Observed: compilation fails. The provider treats the unsubmitted `B` as
    // absent and reports `Beta` unresolved from it, rather than resolving the
    // sibling file that sits right next to `A.elm` on disk. This confirms the
    // design's decision that a single-file `--input` compile submits only the
    // selected module; the project's other sources are never available for
    // import resolution even though the manifest lists them.
    assert!(!ok, "expected the compile to fail, but it succeeded: {err}");
    // Pin the *cause* of the failure, not just that something named `Beta`
    // went unfound: "in module `B`" can only come from the resolver naming
    // module B as the place the lookup failed, so a future change that fails
    // for an unrelated reason (e.g. `` `Beta` not found: <other reason> ``)
    // would not satisfy this.
    assert!(
        err.contains("in module `B`"),
        "expected an unresolved-import error citing module `B` as the cause, got: {err}"
    );
}

/// A standalone single-file Elm compile with no `--ir-version` flag always
/// emits classic IR v3, regardless of the project route's v4 default (see
/// `ir_version_default_for_whole_project_compile` below). Observed via
/// `cargo test ... -- --nocapture`: `formatVersion = Number(3)`.
#[test]
fn ir_version_default_for_standalone_single_file_compile() {
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
    assert_eq!(
        ir["formatVersion"],
        serde_json::json!(3),
        "expected the standalone single-file route to default to classic IR v3"
    );
}

/// A standalone single-file Elm compile with `--ir-version 4` is rejected
/// outright: this route only ever produces classic IR v3, so it never even
/// reaches the frontend before failing. Observed stderr: `Validation error:
/// Single-file Elm compilation supports only IR v3`.
#[test]
fn ir_version_4_on_standalone_single_file_compile() {
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
            "--ir-version",
            "4",
        ],
    );
    assert!(!ok, "expected --ir-version 4 to be rejected on the standalone single-file route");
    // This exact sentence is the CLI's own validation message for this one
    // rejection path; nothing else in the process produces it, so it cannot
    // be satisfied by an unrelated failure the way a short substring could.
    assert!(
        err.contains("Single-file Elm compilation supports only IR v3"),
        "unexpected stderr: {err}"
    );
}

/// A whole-project compile (built-in Gleam provider) with no `--ir-version`
/// defaults to IR v4 — the opposite of the standalone single-file route
/// above, which always emits v3. This is the divergence a later refactor
/// merging the two compile routes must confront rather than silently erase.
/// Observed via `cargo test ... -- --nocapture`: `formatVersion = Number(4)`.
#[test]
fn ir_version_default_for_whole_project_compile() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::create_dir_all(dir.join("src")).unwrap();
    fs::write(
        dir.join("morphir.toml"),
        "[project]\nname = 'acme/widgets'\nversion = '1.0.0'\nsource_directory = 'src'\nexposed_modules = ['api']\n\n[frontend]\nlanguage = 'gleam'\n",
    )
    .unwrap();
    fs::write(dir.join("src/api.gleam"), "pub type Answer { Answer }\n").unwrap();

    let (ok, _out, err) = morphir(dir, &["compile"]);
    assert!(ok, "{err}");

    let ir = distribution(dir);
    assert_eq!(
        ir["formatVersion"],
        serde_json::json!(4),
        "expected the whole-project Gleam route to default to IR v4"
    );
}
