use super as support;
use crate::notebook::Notebook;
use serde_json::{Value, json};
use std::{fs, process::Command, time::Duration};

fn notebook() -> Value {
    json!({"nbformat":4,"nbformat_minor":5,"metadata":{"morphir":{"version":1,"itest":{"title":"CLI help","description":"Help exposes supported options","tags":["area:help","kind:positive"],"provider":"rego"}}},"cells":[
        {"id":"help","cell_type":"code","source":"morphir --help","metadata":{"morphir":{"itest":{"kind":"command","name":"Help","timeout_seconds":10,"captures":[]}}},"execution_count":null,"outputs":[]},
        {"id":"check","cell_type":"code","source":"package example\ntest_ok := true","metadata":{"morphir":{"itest":{"kind":"assertion","command":"help","entrypoints":["data.example.test_ok"]}}},"execution_count":null,"outputs":[]}
    ]})
}

fn parse(value: &Value) -> anyhow::Result<(super::model::Metadata, Vec<super::model::Step>)> {
    super::model::parse(&Notebook::parse(&value.to_string())?)
}

#[test]
fn discovers_nested_examples_and_selects_whole_categories_and_all_tags() {
    let temp = tempfile::tempdir().unwrap();
    for name in ["elm/z", "elm/nested/a", "gleam/a", "node_modules/hidden"] {
        let dir = temp.path().join(name);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("scenario.ipynb"), notebook().to_string()).unwrap();
    }
    let found = support::discover(temp.path(), Some("elm")).unwrap();
    assert_eq!(
        found.iter().map(|s| s.id.as_str()).collect::<Vec<_>>(),
        ["elm/nested/a", "elm/z"]
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
            fs::write(directory.join("scenario.ipynb"), notebook().to_string()).unwrap();
        }
        assert!(
            support::discover(temp.path(), None).is_err(),
            "accepted nonportable scenario directory {name:?}"
        );
    }
}

#[test]
fn validates_every_executable_cell_before_running() {
    assert!(parse(&notebook()).is_ok());
    for (pointer, bad) in [
        ("/metadata/morphir/itest/provider", json!("unknown")),
        ("/metadata/morphir/itest/tags", json!([])),
        ("/metadata/morphir/itest/title", json!("")),
        ("/cells/0/metadata/morphir/itest/timeout_seconds", json!(0)),
        ("/cells/0/metadata/morphir/itest/kind", json!("typo")),
        ("/cells/0/source", json!("sh -c 'morphir --help'")),
        ("/cells/0/source", json!("morphir 'unterminated")),
        (
            "/cells/0/metadata/morphir/itest/captures",
            json!([{"name":"escape","path":"../outside","format":"json"}]),
        ),
        ("/cells/1/metadata/morphir/itest/command", json!("missing")),
        ("/cells/1/metadata/morphir/itest/entrypoints", json!([])),
        (
            "/cells/1/metadata/morphir/itest/entrypoints",
            json!(["data.x", "data.x"]),
        ),
    ] {
        let mut value = notebook();
        *value.pointer_mut(pointer).unwrap() = bad;
        assert!(parse(&value).is_err(), "accepted {value}");
    }
    let mut value = notebook();
    value["cells"].as_array_mut().unwrap().swap(0, 1);
    assert!(parse(&value).is_err());
    let mut value = notebook();
    value["cells"].as_array_mut().unwrap().pop();
    assert!(parse(&value).is_err());
}

#[test]
fn accepts_literal_quoted_arguments_without_shell_expansion() {
    let mut value = notebook();
    value["cells"][0]["source"] =
        json!("morphir compile --input 'file with spaces.elm' --package-name '$LITERAL'");
    let (_, steps) = parse(&value).unwrap();
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
    let mut value = notebook();
    value["cells"][0]["metadata"]["morphir"]["itest"]["captures"] =
        json!([{"name":"artifact","path":"result.json","format":"json"}]);
    let (_, steps) = parse(&value).unwrap();
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
    let mut value = notebook();
    value["cells"][0]["metadata"]["morphir"]["itest"]["captures"] =
        json!([{"name":"artifact","path":"outside/file","format":"exists"}]);
    let (_, steps) = parse(&value).unwrap();
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
