//! `morphir mck convert` end to end (`spec/mck/cli-contract.md` conventions): writing, and
//! checking, the kit's generated `.feature` twins of its Markdown case files. stdout carries the
//! command's result, 0 is success, 1 a failed check or operational error.

use std::path::{Path, PathBuf};
use std::process::Output;

use tempfile::TempDir;

fn morphir(args: &[&str]) -> Output {
    let mut command = std::process::Command::new(env!("CARGO_BIN_EXE_morphir"));
    command.env("MORPHIR_LOG_FILE", "false");
    command.env_remove("MORPHIR_LOG_DIR");
    command.env_remove("MORPHIR_OUT_DIR");
    command.args(args).output().expect("morphir runs")
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn repository_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn repository_kit() -> PathBuf {
    repository_root().join("spec/ir/mck")
}

const TOPICS: [&str; 8] = [
    "definitions",
    "distributions",
    "document-tree",
    "names",
    "patterns-and-literals",
    "types",
    "values",
    "versions",
];

fn copy_recursive(source: &Path, destination: &Path) {
    std::fs::create_dir_all(destination).unwrap();
    for entry in std::fs::read_dir(source).unwrap() {
        let entry = entry.unwrap();
        let target = destination.join(entry.file_name());
        let kind = entry.file_type().unwrap();
        if kind.is_dir() {
            copy_recursive(&entry.path(), &target);
        } else if kind.is_file() {
            std::fs::copy(entry.path(), &target).unwrap();
        }
    }
}

/// A temp checkout carrying just what the kit needs to load cleanly away from the repository: the
/// kit itself at `spec/ir/mck` (so its repository root is inferred), and the one external fixture
/// `distributions.md`'s `text` fence names.
fn temp_checkout() -> (TempDir, PathBuf) {
    let work = TempDir::new().unwrap();
    let kit = work.path().join("spec").join("ir").join("mck");
    copy_recursive(&repository_kit(), &kit);
    let fixture = work
        .path()
        .join("website")
        .join("static")
        .join("ir")
        .join("examples")
        .join("v4")
        .join("complete-example.json");
    std::fs::create_dir_all(fixture.parent().unwrap()).unwrap();
    std::fs::copy(
        repository_root().join("website/static/ir/examples/v4/complete-example.json"),
        &fixture,
    )
    .unwrap();
    (work, kit)
}

#[test]
fn check_exits_0_on_the_committed_feature_files() {
    let output = morphir(&[
        "mck",
        "convert",
        "--check",
        "--kit",
        repository_kit().to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    assert_eq!(stdout(&output), "");
}

#[test]
fn check_exits_1_and_names_the_feature_file_after_its_markdown_twins_fence_body_changes() {
    let (_work, kit) = temp_checkout();
    let values = kit.join("values.md");
    let text = std::fs::read_to_string(&values).unwrap();
    assert!(
        text.contains("IntegerLiteral: 42"),
        "the fixture this test edits changed underneath it"
    );
    std::fs::write(
        &values,
        text.replace("IntegerLiteral: 42", "IntegerLiteral: 43"),
    )
    .unwrap();

    let output = morphir(&["mck", "convert", "--check", "--kit", kit.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(1), "{}", stderr(&output));
    let report = stdout(&output);
    assert!(
        report.contains("values.feature") && report.contains("out of date with values.md"),
        "{report}"
    );
    // Only the file whose twin actually changed is reported.
    assert_eq!(report.lines().count(), 1, "{report}");
}

#[test]
fn check_exits_1_and_reports_a_missing_twin_when_another_feature_file_still_exists() {
    let (_work, kit) = temp_checkout();
    std::fs::remove_file(kit.join("values.feature")).unwrap();

    let output = morphir(&["mck", "convert", "--check", "--kit", kit.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(1), "{}", stderr(&output));
    let report = stdout(&output);
    assert!(
        report.contains("values.feature: missing; run morphir mck convert"),
        "{report}"
    );
    // Only the missing file is reported; the other seven twins are untouched.
    assert_eq!(report.lines().count(), 1, "{report}");
}

/// A `.feature` file whose Markdown source is gone would keep running retired scenarios under
/// `--engine gherkin`, so it is drift too.
#[test]
fn check_exits_1_and_reports_a_feature_file_with_no_markdown_source() {
    let (_work, kit) = temp_checkout();
    std::fs::copy(kit.join("values.feature"), kit.join("retired.feature")).unwrap();

    let output = morphir(&["mck", "convert", "--check", "--kit", kit.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(1), "{}", stderr(&output));
    let report = stdout(&output);
    assert!(
        report.contains(
            "retired.feature: no retired.md with cases; delete it or restore its Markdown source"
        ),
        "{report}"
    );
    assert_eq!(report.lines().count(), 1, "{report}");
}

/// A Markdown-only kit (no `.feature` files at all) carries no twins yet during the parity
/// window: a missing twin is drift only once the kit directory already has at least one other
/// `.feature` file, so this is not drift.
#[test]
fn check_exits_0_when_the_kit_carries_no_feature_files_at_all() {
    let (_work, kit) = temp_checkout();
    for topic in TOPICS {
        std::fs::remove_file(kit.join(format!("{topic}.feature"))).unwrap();
    }

    let output = morphir(&["mck", "convert", "--check", "--kit", kit.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    assert_eq!(stdout(&output), "");
}

#[test]
fn convert_without_check_regenerates_the_committed_text_byte_for_byte() {
    let (_work, kit) = temp_checkout();
    for topic in TOPICS {
        std::fs::remove_file(kit.join(format!("{topic}.feature"))).unwrap();
    }

    let output = morphir(&["mck", "convert", "--kit", kit.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));

    for topic in TOPICS {
        let generated = std::fs::read(kit.join(format!("{topic}.feature"))).unwrap();
        let committed = std::fs::read(repository_kit().join(format!("{topic}.feature"))).unwrap();
        assert_eq!(generated, committed, "{topic}.feature");
        assert!(
            generated.ends_with(b"\n") && !generated.ends_with(b"\n\n"),
            "{topic}.feature ends with exactly one newline"
        );
    }

    // Regenerating leaves the kit drift-free.
    let checked = morphir(&["mck", "convert", "--check", "--kit", kit.to_str().unwrap()]);
    assert_eq!(checked.status.code(), Some(0), "{}", stderr(&checked));
}
