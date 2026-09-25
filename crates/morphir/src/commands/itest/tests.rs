use super as support;
use serde_json::json;
use std::{fs, process::Command, time::Duration};

/// A `scenarios.md` document with one section: a `morphir --help` command and a Rego assertion.
const SCENARIO: &str = r#"---
version: 1
title: CLI help
description: Help exposes supported options
tags: [area:help, kind:positive]
provider: rego
---

## Help

```yaml morphir:command
id: help
name: Help
timeout_seconds: 10
captures: []
```

```sh
morphir --help
```

```yaml morphir:assertion
id: check
command: help
entrypoints: [data.example.test_ok]
```

```rego
package example
test_ok := true
```
"#;

/// The command block of [`SCENARIO`], from its metadata fence to its source fence.
const COMMAND: &str = "```yaml morphir:command\nid: help\nname: Help\ntimeout_seconds: 10\ncaptures: []\n```\n\n```sh\nmorphir --help\n```\n";

/// The assertion block of [`SCENARIO`], from its metadata fence to its source fence.
const ASSERTION: &str = "```yaml morphir:assertion\nid: check\ncommand: help\nentrypoints: [data.example.test_ok]\n```\n\n```rego\npackage example\ntest_ok := true\n```\n";

/// [`SCENARIO`] with `from` replaced by `to` once. Panics when `from` is not in it, so that a
/// test never checks an unchanged document by mistake.
fn with(from: &str, to: &str) -> String {
    assert!(SCENARIO.contains(from), "{from:?} is not in the scenario");
    SCENARIO.replacen(from, to, 1)
}

fn parse(text: &str) -> anyhow::Result<(super::model::Metadata, Vec<super::model::Step>)> {
    let document = super::markdown::parse_sections(text)?;
    super::model::parse(&document.sections[0])
}

#[test]
fn discovers_nested_examples_and_selects_whole_categories_and_all_tags() {
    let temp = tempfile::tempdir().unwrap();
    for name in ["elm/z", "elm/nested/a", "gleam/a", "node_modules/hidden"] {
        let dir = temp.path().join(name);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("scenarios.md"), SCENARIO).unwrap();
    }
    let found = support::discover(temp.path(), Some("elm")).unwrap();
    assert_eq!(
        found.iter().map(|s| s.id.as_str()).collect::<Vec<_>>(),
        ["elm/nested/a#help", "elm/z#help"]
    );
    for filter in ["el", "missing", ""] {
        assert!(support::discover(temp.path(), Some(filter)).is_err());
    }
    assert_eq!(
        support::select_tags(&found, &["area:help".into(), "kind:positive".into()])
            .unwrap()
            .len(),
        2
    );
    assert!(support::select_tags(&found, &["area:help".into(), "kind:negative".into()]).is_err());
}

#[test]
#[cfg(unix)]
fn discovery_rejects_ambiguous_and_nonportable_directory_names() {
    use std::ffi::OsString;
    #[cfg(target_os = "linux")]
    use std::os::unix::ffi::OsStringExt;

    for name in [
        OsString::from("a\\b"),
        // APFS refuses invalid UTF-8 before discovery; Linux permits it.
        #[cfg(target_os = "linux")]
        OsString::from_vec(b"invalid-\xff".to_vec()),
        OsString::from("trailing."),
        OsString::from("CON"),
    ] {
        let temp = tempfile::tempdir().unwrap();
        for directory in [temp.path().join(&name), temp.path().join("a/b")] {
            fs::create_dir_all(&directory).unwrap();
            fs::write(directory.join("scenarios.md"), SCENARIO).unwrap();
        }
        assert!(
            support::discover(temp.path(), None).is_err(),
            "accepted nonportable scenario directory {name:?}"
        );
    }
}

#[test]
fn validates_every_executable_cell_before_running() {
    assert!(parse(SCENARIO).is_ok());
    for (from, to) in [
        ("provider: rego", "provider: unknown"),
        ("tags: [area:help, kind:positive]", "tags: []"),
        ("title: CLI help", "title: ''"),
        ("timeout_seconds: 10", "timeout_seconds: 0"),
        ("yaml morphir:command", "yaml morphir:typo"),
        ("morphir --help", "sh -c 'morphir --help'"),
        ("morphir --help", "morphir 'unterminated"),
        (
            "captures: []",
            "captures: [{name: escape, path: ../outside, format: json}]",
        ),
        ("command: help", "command: missing"),
        ("entrypoints: [data.example.test_ok]", "entrypoints: []"),
        (
            "entrypoints: [data.example.test_ok]",
            "entrypoints: [data.x, data.x]",
        ),
    ] {
        let text = with(from, to);
        assert!(parse(&text).is_err(), "accepted {text}");
    }
    // The assertion before its command, and the command without an assertion.
    let swapped = with(COMMAND, "").replacen(ASSERTION, &format!("{ASSERTION}\n{COMMAND}"), 1);
    assert!(parse(&swapped).is_err(), "accepted {swapped}");
    let unchecked = with(ASSERTION, "");
    assert!(parse(&unchecked).is_err(), "accepted {unchecked}");
}

#[test]
fn workspace_metadata_rejects_invalid_paths_and_unknown_modes() {
    for workspace in [
        "{kind: directory, path: ../outside}",
        "{kind: directory, path: /outside}",
        "{kind: directory, path: ., exclude: [../outside]}",
        "{kind: directory}",
        "{kind: inline, path: .}",
        "{kind: typo}",
    ] {
        let text = with(
            "provider: rego",
            &format!("provider: rego\nworkspace: {workspace}"),
        );
        assert!(parse(&text).is_err(), "accepted {text}");
    }
}

#[test]
fn disk_workspace_copies_inputs_and_preserves_config_without_build_outputs() {
    let source = tempfile::tempdir().unwrap();
    let target = tempfile::tempdir().unwrap();
    let text = with(
        "provider: rego",
        "provider: rego\nworkspace: {kind: directory, path: ., exclude: [installed]}",
    );
    fs::write(source.path().join("scenarios.md"), text).unwrap();
    for path in [
        ".morphir/morphir.toml",
        ".morphir/out/stale",
        "installed/stale",
        ".git/config",
        "node_modules/cache",
        "src/input.bin",
    ] {
        let file = source.path().join(path);
        fs::create_dir_all(file.parent().unwrap()).unwrap();
        fs::write(file, [0, 255, 1]).unwrap();
    }
    fs::create_dir(source.path().join("empty")).unwrap();
    let scenarios = support::discover(source.path(), None).unwrap();
    super::workspace::materialize(&scenarios[0], target.path()).unwrap();
    for path in [".morphir/morphir.toml", "src/input.bin"] {
        assert_eq!(fs::read(target.path().join(path)).unwrap(), [0, 255, 1]);
    }
    assert!(target.path().join("empty").is_dir());
    for path in [
        ".morphir/out",
        "installed",
        ".git",
        "node_modules",
        "scenarios.md",
    ] {
        assert!(!target.path().join(path).exists(), "copied excluded {path}");
    }
}

#[cfg(unix)]
#[test]
fn disk_workspace_refuses_symlinks() {
    let source = tempfile::tempdir().unwrap();
    let target = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    fs::write(source.path().join("scenarios.md"), SCENARIO).unwrap();
    std::os::unix::fs::symlink(outside.path(), source.path().join("linked")).unwrap();
    let scenarios = support::discover(source.path(), None).unwrap();
    let error = super::workspace::materialize(&scenarios[0], target.path()).unwrap_err();
    assert!(error.to_string().contains("symlink"), "{error:#}");
}

#[test]
fn disk_workspace_checks_directory_aliases_across_file_cells() {
    for (directory, inline, accepted) in [
        ("ＦＯＯ", "foo", false),
        ("SRC", "src/extra.txt", false),
        ("src", "src/extra.txt", true),
    ] {
        let source = tempfile::tempdir().unwrap();
        let target = tempfile::tempdir().unwrap();
        fs::create_dir(source.path().join(directory)).unwrap();
        let text = with(
            COMMAND,
            &format!(
                "```yaml morphir:file\nid: extra\npath: {inline}\n```\n\n```text\ninline\n```\n\n{COMMAND}"
            ),
        );
        fs::write(source.path().join("scenarios.md"), text).unwrap();
        let scenarios = support::discover(source.path(), None).unwrap();
        let result = super::workspace::materialize(&scenarios[0], target.path());
        assert_eq!(
            result.is_ok(),
            accepted,
            "{directory:?} + {inline:?}: {result:?}"
        );
    }
}

#[test]
fn accepts_literal_quoted_arguments_without_shell_expansion() {
    let text = with(
        "morphir --help",
        "morphir compile --input 'file with spaces.elm' --package-name '$LITERAL'",
    );
    let (_, steps) = parse(&text).unwrap();
    assert_eq!(
        steps[0].args,
        [
            "compile",
            "--input",
            "file with spaces.elm",
            "--package-name",
            "$LITERAL"
        ]
    );
}

#[test]
fn empty_suites_and_legacy_markdown_are_not_coverage() {
    let root = tempfile::tempdir().unwrap();
    fs::write(root.path().join("scenario.md"), "# old scenario").unwrap();
    assert!(support::discover(root.path(), None).is_err());
}

#[test]
fn evaluator_reports_must_match_every_requested_rule_and_only_true_passes() {
    use super::runner::check_report;
    for (status, value, passes) in [
        ("value", json!(true), true),
        ("value", json!(false), false),
        ("value", json!(1), false),
        ("undefined", json!(null), false),
        ("error", json!(true), false),
    ] {
        let report = json!({"version":1,"provider":"rego","results":[{"entrypoint":"data.test","status":status,"value":value}]});
        assert_eq!(
            check_report(
                &report.to_string(),
                morphir_evaluator::ProviderId::Rego,
                &["data.test".into()]
            )
            .is_ok(),
            passes
        );
    }
    for report in [
        json!({"version":1,"provider":"rego","results":[]}),
        json!({"version":1,"provider":"rego","results":[{"entrypoint":"data.wrong","status":"value","value":true}]}),
    ] {
        assert!(
            check_report(
                &report.to_string(),
                morphir_evaluator::ProviderId::Rego,
                &["data.test".into()]
            )
            .is_err()
        );
    }
}

#[test]
fn captures_distinguish_json_null_missing_files_and_invalid_json() {
    use super::runner::{ProcessOutput, observation};
    let root = tempfile::tempdir().unwrap();
    let text = with(
        "captures: []",
        "captures: [{name: artifact, path: result.json, format: json}]",
    );
    let (_, steps) = parse(&text).unwrap();
    let output = ProcessOutput {
        code: Some(0),
        stdout: "".into(),
        stderr: "".into(),
    };
    assert_eq!(
        observation(&steps[0], &output, root.path()).unwrap()["artifacts"]["artifact"],
        json!({"kind":"missing"})
    );
    fs::write(root.path().join("result.json"), "null").unwrap();
    assert_eq!(
        observation(&steps[0], &output, root.path()).unwrap()["artifacts"]["artifact"],
        json!({"kind":"json","value":null})
    );
    fs::write(root.path().join("result.json"), "invalid").unwrap();
    assert!(observation(&steps[0], &output, root.path()).is_err());
}

#[cfg(unix)]
#[test]
fn captures_refuse_symlinks() {
    use super::runner::{ProcessOutput, observation};
    let root = tempfile::tempdir().unwrap();
    std::os::unix::fs::symlink("/tmp", root.path().join("outside")).unwrap();
    let text = with(
        "captures: []",
        "captures: [{name: artifact, path: outside/file, format: exists}]",
    );
    let (_, steps) = parse(&text).unwrap();
    let output = ProcessOutput {
        code: Some(0),
        stdout: "".into(),
        stderr: "".into(),
    };
    assert!(observation(&steps[0], &output, root.path()).is_err());
}
#[test]
fn process_timeout_and_expected_failure_are_observable() {
    let temp = tempfile::tempdir().unwrap();
    let mut command = Command::new(std::env::current_exe().unwrap());
    command
        .args([
            "--exact",
            "commands::itest::tests::timeout_child",
            "--nocapture",
        ])
        .env("EXAMPLE_DRIVER_TIMEOUT_CHILD", "1");
    assert!(
        support::execute(command, temp.path(), Duration::from_millis(100))
            .unwrap_err()
            .to_string()
            .contains("timed out")
    );
    let mut command = Command::new(std::env::current_exe().unwrap());
    command.arg("--not-a-real-option");
    let result = support::execute(command, temp.path(), Duration::from_secs(10)).unwrap();
    assert!(!matches!(result.code, Some(0)));
    assert!(
        result.stderr.contains("Unrecognized option"),
        "{}",
        result.stderr
    );
}

#[test]
#[expect(
    clippy::zombie_processes,
    reason = "the timeout test requires the driver to terminate this helper's descendant"
)]
fn timeout_child() {
    if std::env::var_os("EXAMPLE_DRIVER_TIMEOUT_CHILD").is_some() {
        if let Some(marker) = std::env::var_os("EXAMPLE_DRIVER_MARKER") {
            let _child = Command::new(std::env::current_exe().unwrap())
                .args(["--exact", "commands::itest::tests::timeout_grandchild"])
                .env("EXAMPLE_DRIVER_GRANDCHILD", marker)
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .spawn()
                .unwrap();
            std::thread::sleep(Duration::from_secs(20));
        }
        std::thread::sleep(Duration::from_secs(20));
    }
}

#[test]
fn timeout_terminates_descendant_processes() {
    let temp = tempfile::tempdir().unwrap();
    let marker = temp.path().join("survived");
    let mut command = Command::new(std::env::current_exe().unwrap());
    command
        .args([
            "--exact",
            "commands::itest::tests::timeout_child",
            "--nocapture",
        ])
        .env("EXAMPLE_DRIVER_TIMEOUT_CHILD", "1")
        .env("EXAMPLE_DRIVER_MARKER", &marker);
    assert!(support::execute(command, temp.path(), Duration::from_millis(100)).is_err());
    std::thread::sleep(Duration::from_millis(500));
    assert!(!marker.exists(), "descendant survived the timeout");
}

#[test]
fn timeout_grandchild() {
    if let Some(marker) = std::env::var_os("EXAMPLE_DRIVER_GRANDCHILD") {
        std::thread::sleep(Duration::from_millis(300));
        fs::write(marker, "survived").unwrap();
    }
}

#[test]
fn recognizes_case_insensitive_morphir_environment_names() {
    for name in ["MORPHIR_OUT_DIR", "morphir_out_dir", "Morphir_Home"] {
        assert!(super::runner::is_morphir_environment(std::ffi::OsStr::new(
            name
        )));
    }
    assert!(!super::runner::is_morphir_environment(
        std::ffi::OsStr::new("PATH")
    ));
}

#[test]
fn normal_exit_also_terminates_descendants() {
    let temp = tempfile::tempdir().unwrap();
    let marker = temp.path().join("survived");
    let mut command = Command::new(std::env::current_exe().unwrap());
    command
        .args([
            "--exact",
            "commands::itest::tests::exiting_parent",
            "--nocapture",
        ])
        .env("EXAMPLE_DRIVER_MARKER", &marker);
    let result = support::execute(command, temp.path(), Duration::from_secs(10)).unwrap();
    assert_eq!(result.code, Some(0));
    std::thread::sleep(Duration::from_millis(500));
    assert!(!marker.exists(), "descendant outlived successful CLI exit");
}

#[test]
#[expect(
    clippy::zombie_processes,
    reason = "the normal-exit test requires the driver to terminate the surviving descendant"
)]
fn exiting_parent() {
    if let Some(marker) = std::env::var_os("EXAMPLE_DRIVER_MARKER") {
        let _child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "commands::itest::tests::timeout_grandchild"])
            .env("EXAMPLE_DRIVER_GRANDCHILD", marker)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .unwrap();
        // The driver, not this exiting parent, must own descendant cleanup.
    }
}

#[test]
fn suite_file_errors_under_excluded_directories_are_recognized() {
    let root = std::path::Path::new("/r/examples");
    for (message, excluded) in [
        ("/r/examples/node_modules/pkg/a.feature:1:1: bad", true),
        ("/r/examples/elm/out/a.feature: no Feature heading", true),
        ("/r/examples/elm/a.feature:1:1: bad", false),
        ("/r/examples/elm/scenarios.md: out of order", false),
        // The three discovery-error forms morphir-bdd writes, under an excluded directory…
        (
            "the directory /r/examples/target cannot be read: denied",
            true,
        ),
        (
            "an entry in /r/examples/elm/node_modules/pkg cannot be read: denied",
            true,
        ),
        ("/r/examples/elm/out/a.feature cannot be read: denied", true),
        ("/r/examples/.git cannot be read: denied", true),
        // …and under a directory that is not excluded.
        (
            "the directory /r/examples/elm cannot be read: denied",
            false,
        ),
        (
            "an entry in /r/examples/elm/pkg cannot be read: denied",
            false,
        ),
        ("/r/examples/elm/a.feature cannot be read: denied", false),
        // A message about a path outside the root.
        (
            "the directory /elsewhere/target cannot be read: denied",
            false,
        ),
    ] {
        assert_eq!(
            support::under_excluded_dir(root, message),
            excluded,
            "{message}"
        );
    }
}

#[test]
fn listed_scenarios_count_outline_rows_and_wip_skips() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("x.feature");
    fs::write(
        &path,
        "Feature: F\n  Scenario: Plain\n    When I run \"morphir x\"\n\n  @wip\n  Scenario: Skipped\n    When I run \"morphir x\"\n\n  Scenario Outline: Rows <n>\n    When I run \"morphir x\"\n\n    Examples:\n      | n |\n      | 1 |\n      | 2 |\n\n    @wip\n    Examples:\n      | n |\n      | 3 |\n",
    )
    .unwrap();
    let listed = support::read_listed(&path, ".").unwrap();
    let counts: Vec<_> = listed
        .iter()
        .map(|scenario| (scenario.id.as_str(), scenario.runs, scenario.will_run))
        .collect();
    assert_eq!(
        counts,
        [(".#plain", 1, 1), (".#skipped", 1, 0), (".#rows-n", 3, 2)]
    );
}
