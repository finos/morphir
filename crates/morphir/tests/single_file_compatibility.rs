//! Compatibility tests for compiling selected source files, driving the real
//! `morphir` binary. They were written against the CLI's own single-file Elm
//! route before it was removed (finos/morphir#917, step 1) and now run through
//! the one compile route, where the provider synthesizes the project through
//! workspace discovery. Two tests changed on purpose, and each says why:
//! `ir_version_4_on_standalone_single_file_compile` (the CLI no longer refuses
//! a version its provider serves) and
//! `a_lone_gleam_source_compiles_as_a_synthesized_project` (a suffix selects
//! the provider that declares it).
//!
//! ## Deliberate coverage gaps
//!
//! Provider selection has three precedence levels: `--extension`, then
//! `[frontend.<language>] extension` from a loaded configuration, then
//! whatever provider the registry resolves for the language. The last level
//! is not tested here for Elm: the `morphir-elm` process extension is not
//! installed in this test environment. The real-binary checks in
//! `crates/integration-tests/tests/elm_extension.rs` and
//! `real_installed_morphir_elm_is_verified_and_activates_offline` cover it in
//! CI against the pinned release.

use std::{fs, process::Command};

/// Runs the `morphir` binary in `dir` with `args`, returning
/// `(success, stdout, stderr)`.
fn morphir(dir: &std::path::Path, args: &[&str]) -> (bool, String, String) {
    let output = Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args(args)
        .current_dir(dir)
        .env("MORPHIR_HOME", dir.join("home"))
        // The developer's own environment must not reach these runs.
        // `MORPHIR_OUT_DIR` is a supported override, so a shell that sets it
        // would send every task record and IR to that root while the
        // assertions below still read `<temp>/.morphir/out` — the tests would
        // fail while the CLI behaved correctly, and parallel cases would share
        // one external output directory. `MORPHIR_LOG_DIR` and the log file
        // are cleared for the same reason. This mirrors `morphir_command` in
        // `cli_integration.rs`.
        .env_remove("MORPHIR_OUT_DIR")
        .env_remove("MORPHIR_LOG_DIR")
        .env("MORPHIR_LOG_FILE", "false")
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
        &[
            "compile",
            "--input",
            "Widget.elm",
            "--extension",
            "morphir-elm-native",
        ],
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
        &[
            "compile",
            "--input",
            "Gadget.elm",
            "--extension",
            "morphir-elm-native",
        ],
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
        &[
            "compile",
            "--input",
            "not-a-module.elm",
            "--extension",
            "morphir-elm-native",
        ],
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
    fs::write(
        dir.join("src/A.elm"),
        "module A exposing (Alpha)\n\n\ntype alias Alpha =\n    Int\n",
    )
    .unwrap();
    fs::write(
        dir.join("src/B.elm"),
        "module B exposing (Beta)\n\n\ntype alias Beta =\n    Int\n",
    )
    .unwrap();

    // `--config` is required: a standalone `--input` compile does not load an
    // adjacent morphir.toml. It is also what makes this the manifest-origin
    // case at all, since the spec's manifest origin means "selected or loaded".
    let (ok, _out, err) = morphir(
        dir,
        &[
            "compile",
            "--input",
            "src/A.elm",
            "--config",
            "morphir.toml",
        ],
    );
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
    fs::write(
        dir.join("src/B.elm"),
        "module B exposing (Beta)\n\n\ntype alias Beta =\n    Int\n",
    )
    .unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &[
            "compile",
            "--input",
            "src/A.elm",
            "--config",
            "morphir.toml",
        ],
    );
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
        &[
            "compile",
            "--input",
            "Widget.elm",
            "--extension",
            "morphir-elm-native",
        ],
    );
    assert!(ok, "{err}");

    let ir = distribution(dir);
    assert_eq!(
        ir["formatVersion"],
        serde_json::json!(3),
        "expected the standalone single-file route to default to classic IR v3"
    );
}

/// A standalone single-file compile negotiates the IR version with its
/// provider rather than refusing one the provider serves. This test used to
/// pin the CLI's refusal ("Single-file Elm compilation supports only IR v3"),
/// which was a defect: `morphir-elm-native` advertises both 3 and 4, and the
/// CLI refused a version the selected provider could produce. Changing it is
/// the evidence that restrictions now come from declared capabilities.
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
    assert!(ok, "{err}");

    let ir = distribution(dir);
    assert_eq!(ir["formatVersion"], serde_json::json!(4));
}

/// A refusal that comes before any source is compiled still tombstones the
/// previous record. `prepare_dest` runs as soon as the run knows where its
/// output goes, so a selection the provider refuses in discovery — here an
/// explicit package name that is blank — leaves no stale success for
/// `generate` to consume. This keeps the ordering the removed v4 refusal used
/// to pin, through a refusal that still exists.
#[test]
fn a_refusal_before_compiling_tombstones_the_previous_success() {
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
        ],
    );
    assert!(
        ok,
        "prior compile establishing a record must succeed: {err}"
    );

    let (ok, _out, err) = morphir(
        dir,
        &[
            "compile",
            "--input",
            "Widget.elm",
            "--extension",
            "morphir-elm-native",
            "--package-name",
            "   ",
        ],
    );
    assert!(!ok, "a blank package name must be refused");
    assert!(err.contains("workspace.project-name.empty"), "{err}");

    let mut record: serde_json::Value =
        serde_json::from_slice(&fs::read(dir.join(".morphir/out/compile.json")).unwrap()).unwrap();
    record.as_object_mut().unwrap().remove("completedAt");
    assert_eq!(
        record,
        serde_json::json!({
            "schema": 1,
            "task": "compile",
            "module": "",
            "inputs": [],
            "value": [],
            "tombstone": true
        }),
        "expected the prior successful record to be tombstoned, got {record}"
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

/// A lone Gleam source compiles as a synthesized project, with no CLI
/// change for the language. This test used to pin a refusal: the CLI routed
/// only `.elm` files to single-file compilation, so `widget.gleam` fell
/// through to the project path and died looking for a `morphir.toml`. The
/// suffix now selects the provider that declares it, and the provider names
/// the package and its module.
#[test]
fn a_lone_gleam_source_compiles_as_a_synthesized_project() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(dir.join("widget.gleam"), "pub type Size {\n  Size\n}\n").unwrap();

    let (ok, _out, err) = morphir(dir, &["compile", "--input", "widget.gleam"]);
    assert!(ok, "{err}");

    let ir = distribution(dir);
    assert_eq!(ir["formatVersion"], serde_json::json!(3));
    assert_eq!(
        ir["distribution"][1],
        serde_json::json!([["local"], ["widget"]])
    );
    let modules = ir["distribution"][3]["modules"].as_array().unwrap();
    assert_eq!(modules.len(), 1, "expected exactly one exposed module");
    assert_eq!(modules[0][0], serde_json::json!([["widget"]]));
}

/// Several sources from one directory compile together under an explicit
/// name, and every selected module is exposed.
#[test]
fn a_named_multi_file_selection_exposes_every_selected_module() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(dir.join("alpha.gleam"), "pub type Alpha {\n  Alpha\n}\n").unwrap();
    fs::write(dir.join("beta.gleam"), "pub type Beta {\n  Beta\n}\n").unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &[
            "compile",
            "--input",
            "alpha.gleam",
            "--input",
            "beta.gleam",
            "--package-name",
            "acme/pair",
        ],
    );
    assert!(ok, "{err}");

    let ir = distribution(dir);
    assert_eq!(
        ir["distribution"][1],
        serde_json::json!([["acme"], ["pair"]])
    );
    let mut names: Vec<_> = ir["distribution"][3]["modules"]
        .as_array()
        .unwrap()
        .iter()
        .map(|module| module[0].clone())
        .collect();
    names.sort_by_key(ToString::to_string);
    assert_eq!(
        names,
        vec![
            serde_json::json!([["alpha"]]),
            serde_json::json!([["beta"]])
        ]
    );
}

/// Several distinct sources and no name leave nothing to derive a package
/// name from, and the provider says so rather than picking one.
#[test]
fn an_unnamed_multi_file_selection_requires_a_package_name() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(dir.join("alpha.gleam"), "pub type Alpha {\n  Alpha\n}\n").unwrap();
    fs::write(dir.join("beta.gleam"), "pub type Beta {\n  Beta\n}\n").unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &["compile", "--input", "alpha.gleam", "--input", "beta.gleam"],
    );
    assert!(!ok, "expected the selection to be refused");
    assert!(err.contains("workspace.selection.name-required"), "{err}");
}

/// Passing one file twice is one source, so it needs no name.
#[test]
fn a_repeated_input_counts_once() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(dir.join("widget.gleam"), "pub type Size {\n  Size\n}\n").unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &[
            "compile",
            "--input",
            "widget.gleam",
            "--input",
            "./widget.gleam",
        ],
    );
    assert!(ok, "{err}");
}

/// Sources from two directories have no single root to measure module names
/// from, so the selection is refused rather than silently renamed.
#[test]
fn a_selection_spanning_directories_is_refused() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::create_dir_all(dir.join("src")).unwrap();
    fs::create_dir_all(dir.join("lib")).unwrap();
    fs::write(
        dir.join("src/alpha.gleam"),
        "pub type Alpha {\n  Alpha\n}\n",
    )
    .unwrap();
    fs::write(dir.join("lib/beta.gleam"), "pub type Beta {\n  Beta\n}\n").unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &[
            "compile",
            "--input",
            "src/alpha.gleam",
            "--input",
            "lib/beta.gleam",
            "--package-name",
            "acme/pair",
        ],
    );
    assert!(!ok, "expected the selection to be refused");
    assert!(
        err.contains("workspace.selection.spans-directories"),
        "{err}"
    );
}

/// A suffix no provider declares is refused with the suffix and the
/// languages that are available, not with a request for a manifest.
#[test]
fn a_suffix_no_provider_declares_names_the_available_languages() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(dir.join("notes.xyz"), "anything\n").unwrap();

    let (ok, _out, err) = morphir(dir, &["compile", "--input", "notes.xyz"]);
    assert!(!ok, "expected the compile to be refused");
    assert!(err.contains("'.xyz'"), "{err}");
    assert!(err.contains("gleam"), "{err}");
}

/// An implicit generate refuses a compile of an explicit selection: its IR
/// holds only the selected modules, which need not match the project.
/// `--from-partial-compile` acknowledges it.
#[test]
fn generate_refuses_a_partial_compile_unless_acknowledged() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::create_dir_all(dir.join("src")).unwrap();
    fs::write(
        dir.join("morphir.toml"),
        "[project]\nname = 'acme/widgets'\nversion = '1.0.0'\nsource_directory = 'src'\n\n[frontend]\nlanguage = 'gleam'\n\n[codegen]\ntargets = ['gleam']\n",
    )
    .unwrap();
    fs::write(
        dir.join("src/api.gleam"),
        "pub type Answer {\n  Answer\n}\n",
    )
    .unwrap();
    fs::write(
        dir.join("src/other.gleam"),
        "pub type Other {\n  Other\n}\n",
    )
    .unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &[
            "compile",
            "--input",
            "src/api.gleam",
            "--config",
            "morphir.toml",
        ],
    );
    assert!(ok, "{err}");
    let record: serde_json::Value =
        serde_json::from_slice(&fs::read(dir.join(".morphir/out/compile.json")).unwrap()).unwrap();
    assert_eq!(record["compileScope"]["kind"], "explicit-selection");

    let (ok, _out, err) = morphir(dir, &["generate"]);
    assert!(!ok, "an implicit generate must refuse a partial compile");
    assert!(err.contains("--from-partial"), "{err}");

    let (ok, _out, err) = morphir(dir, &["generate", "--from-partial-compile"]);
    assert!(ok, "{err}");

    // A project compile carries no mark, so generate consumes it silently.
    let (ok, _out, err) = morphir(dir, &["compile"]);
    assert!(ok, "{err}");
    let (ok, _out, err) = morphir(dir, &["generate"]);
    assert!(ok, "{err}");
}

/// A standalone roundtrip has no project for its generate half to read, so
/// it is refused before anything compiles.
#[test]
fn a_standalone_roundtrip_is_refused_before_compiling() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(dir.join("widget.gleam"), "pub type Size {\n  Size\n}\n").unwrap();

    let (ok, _out, err) = morphir(dir, &["gleam", "roundtrip", "--input", "widget.gleam"]);
    assert!(!ok, "expected the roundtrip to be refused");
    assert!(err.contains("roundtrip needs a project"), "{err}");
    assert!(!dir.join(".morphir/out/compile.json").exists());
}

/// `--extension morphir-elm-native` alone, with no configuration present at
/// all, selects the built-in provider directly: the highest precedence
/// level.
#[test]
fn provider_selection_by_flag_alone_with_no_configuration() {
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
        ],
    );
    assert!(ok, "{err}");

    // The provider actually ran and produced IR; nothing here pins which
    // provider string was recorded, since the run doesn't surface one
    // anywhere observable (stdout is just "Compilation successful").
    let ir = distribution(dir);
    assert_eq!(
        ir["distribution"][1],
        serde_json::json!([["local"], ["acme", "widget"]])
    );
}

/// A failed compile must not leave the previous successful record intact, or
/// `generate` would consume stale IR. `prepare_dest` writes a tombstone before
/// the source is even read, which is why the failure ordering in the refactor
/// is not free to change.
#[test]
fn a_failed_compile_tombstones_the_previous_success() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(
        dir.join("Widget.elm"),
        "module Widget exposing (Size)\n\n\ntype alias Size =\n    Int\n",
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
        ],
    );
    assert!(ok, "first compile succeeds: {err}");

    // Now make it fail, without changing anything else about the invocation.
    // The body is invalid (a bare `!!!` where a type was expected), so this
    // trips a real parse/compile error rather than the missing-module-
    // declaration error pinned by `a_file_without_a_module_declaration_fails_to_compile`.
    // Observed stderr: "syntax error near `!!! not`".
    fs::write(
        dir.join("Widget.elm"),
        "module Widget exposing (Size)\n\n\ntype alias Size =\n    !!! not elm\n",
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
        ],
    );
    assert!(!ok, "second compile fails");
    assert!(
        err.contains("syntax error"),
        "expected a syntax-error failure, not the missing-declaration one pinned elsewhere: {err}"
    );

    let mut record: serde_json::Value =
        serde_json::from_slice(&fs::read(dir.join(".morphir/out/compile.json")).unwrap()).unwrap();
    // `completedAt` is a wall-clock timestamp and not part of the property
    // under test, so it is excluded before the exact comparison below.
    record.as_object_mut().unwrap().remove("completedAt");

    // Observed: after the failed compile, the record is a tombstone with an
    // empty `value` and no `ir` descriptor at all — nothing here points at
    // consumable IR, so `generate` cannot pick up the previous success. This
    // is the exact record `prepare_dest` writes before the source is even
    // read; the second compile never gets far enough to overwrite it with
    // anything else.
    assert_eq!(
        record,
        serde_json::json!({
            "schema": 1,
            "task": "compile",
            "module": "",
            "inputs": [],
            "value": [],
            "tombstone": true
        }),
        "expected a tombstoned record pointing at no consumable IR, got {record}"
    );
}

/// `[frontend.elm] extension = 'morphir-elm-native'` in a loaded
/// configuration selects the provider when no `--extension` flag is given:
/// the second precedence level. `--config` is mandatory here; without it the
/// file is never read (see `compile.rs:675`) and the run would fall through
/// to the default provider instead, an installed process extension that does
/// not exist in this test environment, failing for an unrelated reason.
#[test]
fn provider_selection_by_configuration_with_no_flag() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(
        dir.join("Widget.elm"),
        "module Acme.Widget exposing (Size)\n\n\ntype alias Size =\n    Int\n",
    )
    .unwrap();
    fs::write(
        dir.join("morphir.toml"),
        "[frontend.elm]\nextension = 'morphir-elm-native'\n",
    )
    .unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &[
            "compile",
            "--input",
            "Widget.elm",
            "--config",
            "morphir.toml",
        ],
    );
    assert!(ok, "{err}");

    let ir = distribution(dir);
    assert_eq!(
        ir["distribution"][1],
        serde_json::json!([["local"], ["acme", "widget"]])
    );
}

/// `--input <file> --project <name>` in a directory tree with a discoverable
/// `morphir.toml` takes the `discover_config` branch (`compile.rs:680-687`):
/// no `--config` is given, so `discover_config` walks up from the current
/// directory, finds the manifest, and loads it with
/// `ProjectSelection::Explicit("acme/widgets")`. The result matches the
/// `--config`-selected case pinned by
/// `a_selection_inside_a_project_keeps_project_identity_and_narrows_exposure`
/// exactly: the project's manifest name becomes the package path, and only
/// the selected module is exposed.
#[test]
fn a_project_flag_discovers_configuration_and_keeps_project_identity() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::create_dir_all(dir.join("src")).unwrap();
    fs::write(
        dir.join("morphir.toml"),
        "[project]\nname = 'acme/widgets'\nversion = '1.0.0'\nsource_directory = 'src'\nexposed_modules = ['A']\n\n[frontend]\nlanguage = 'elm'\n\n[frontend.elm]\nextension = 'morphir-elm-native'\n",
    )
    .unwrap();
    fs::write(
        dir.join("src/A.elm"),
        "module A exposing (Alpha)\n\n\ntype alias Alpha =\n    Int\n",
    )
    .unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &[
            "compile",
            "--input",
            "src/A.elm",
            "--project",
            "acme/widgets",
        ],
    );
    assert!(ok, "{err}");

    let ir = distribution(dir);
    // Observed: the discovered manifest's name (`acme/widgets`), not the
    // selected module's own name, becomes the package path.
    assert_eq!(
        ir["distribution"][1],
        serde_json::json!([["acme"], ["widgets"]])
    );
    let modules = ir["distribution"][3]["modules"].as_array().unwrap();
    let module_names: Vec<_> = modules.iter().map(|m| m[0].clone()).collect();
    assert_eq!(
        module_names,
        vec![serde_json::json!([["a"]])],
        "expected exactly module A, got {module_names:?}"
    );
}

/// `--input <file> --project <name>` with nothing discoverable hits the
/// explicit refusal at `compile.rs:682-687`: `discover_config` walks all the
/// way up from the current directory, finds no `morphir.toml`,
/// `morphir.yaml`, or `morphir.json`, and the run fails before a
/// configuration is ever loaded.
#[test]
fn a_project_flag_with_no_discoverable_configuration_is_refused() {
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
            "--project",
            "acme/widgets",
        ],
    );
    assert!(!ok, "expected the compile to be refused, but it succeeded");
    // This exact sentence is the CLI's own validation message for this one
    // rejection path (`compile.rs:684`); nothing else in the process
    // produces it.
    assert!(
        err.contains("--project requires a Morphir configuration"),
        "unexpected stderr: {err}"
    );
}

/// `elm_module_name` (`compile.rs:185`) recognizes a `port module` header the
/// same as a plain one, stripping the leading `port` keyword before matching
/// `module`. This pins that the CLI-level package-identity derivation for a
/// port module lands the same place a plain declared module does: the
/// derived package name comes from `App.Ports`, lowercased and dotted-to-
/// dashed, under `local/`, with only that one module exposed. `elm_module_name`
/// is deleted by the refactor along with its own unit test
/// (`extracts_plain_port_and_effect_module_declarations_after_nested_comments`,
/// `compile.rs:2499`), so this is the only place this shape stays pinned once
/// that test is gone.
#[test]
fn a_port_module_is_named_like_a_plain_declared_module() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(
        dir.join("Ports.elm"),
        "port module App.Ports exposing (Size, sendMessage)\n\nport sendMessage : String -> Cmd msg\n\n\ntype alias Size =\n    Int\n",
    )
    .unwrap();

    let (ok, _out, err) = morphir(
        dir,
        &[
            "compile",
            "--input",
            "Ports.elm",
            "--extension",
            "morphir-elm-native",
        ],
    );
    assert!(ok, "{err}");

    let ir = distribution(dir);
    // Observed: `App.Ports` is split, lowercased and nested under `local`,
    // exactly as a plain `module App.Ports exposing (...)` header would be.
    // The `port` keyword and the skipped `port sendMessage : ...` value
    // declaration do not change the derived identity.
    assert_eq!(
        ir["distribution"][1],
        serde_json::json!([["local"], ["app", "ports"]])
    );
    let modules = ir["distribution"][3]["modules"].as_array().unwrap();
    assert_eq!(modules.len(), 1, "expected exactly one exposed module");
    assert_eq!(modules[0][0], serde_json::json!([["app"], ["ports"]]));
    assert_eq!(modules[0][1]["access"], "Public");
}

/// `elm_module_name` (`compile.rs:185`) skips leading trivia — including a
/// nested block comment — via `skip_elm_trivia` before it starts matching a
/// declaration keyword. This pins that a nested block comment placed before
/// the `module` line does not change the derived package identity from the
/// plain declared-module case. As with the port-module test above, this
/// covers a shape that only lived in `elm_module_name`'s own unit test
/// (`compile.rs:2499`) before, which the refactor deletes along with the
/// function.
#[test]
fn a_nested_block_comment_before_the_module_declaration_does_not_change_identity() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::write(
        dir.join("Widget.elm"),
        "{- outer {- nested -} comment -}\nmodule Acme.Widget exposing (Size)\n\n\ntype alias Size =\n    Int\n",
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
        ],
    );
    assert!(ok, "{err}");

    let ir = distribution(dir);
    // Observed: identical to `a_synthesized_package_is_named_for_its_declared_module`,
    // which uses the same module name without the leading nested comment —
    // the comment is skipped entirely and has no effect on the derived
    // identity.
    assert_eq!(
        ir["distribution"][1],
        serde_json::json!([["local"], ["acme", "widget"]])
    );
    let modules = ir["distribution"][3]["modules"].as_array().unwrap();
    assert_eq!(modules.len(), 1, "expected exactly one exposed module");
    assert_eq!(modules[0][0], serde_json::json!([["acme"], ["widget"]]));
    assert_eq!(modules[0][1]["access"], "Public");
}

/// A configured extension that nothing names, and that cannot start, does
/// not stop a compile it has nothing to do with: the host skips it with a
/// warning and selects the provider it would have selected anyway.
#[test]
fn an_unavailable_configured_extension_does_not_block_another_provider() {
    let temp = tempfile::tempdir().unwrap();
    let dir = temp.path();
    fs::create_dir_all(dir.join("src")).unwrap();
    fs::write(
        dir.join("morphir.toml"),
        "[project]\nname = 'acme/widgets'\nversion = '1.0.0'\nsource_directory = 'src'\n\n[frontend]\nlanguage = 'gleam'\n\n[extensions.offline-codegen]\ncommand = 'no-such-executable'\nenabled = true\n",
    )
    .unwrap();
    fs::write(dir.join("src/api.gleam"), "pub type Answer { Answer }\n").unwrap();

    let (ok, _out, err) = morphir(dir, &["compile"]);
    assert!(ok, "{err}");
    assert!(
        err.contains("offline-codegen"),
        "expected a skip warning: {err}"
    );

    let (ok, _out, err) = morphir(
        dir,
        &[
            "compile",
            "--input",
            "src/api.gleam",
            "--config",
            "morphir.toml",
        ],
    );
    assert!(ok, "{err}");
}
