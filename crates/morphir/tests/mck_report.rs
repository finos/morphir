use std::path::Path;
use std::process::{Command, Output};

fn run(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_morphir"))
        .env("MORPHIR_LOG_FILE", "false")
        .env_remove("MORPHIR_LOG_DIR")
        .env_remove("MORPHIR_OUT_DIR")
        .args(args)
        .output()
        .unwrap()
}

fn fixture() -> &'static str {
    include_str!("../../../spec/ir/mck/report-draft.example.json")
}

#[test]
fn render_a_saved_report_without_an_adapter_or_kit() {
    let work = tempfile::tempdir().unwrap();
    let input = work.path().join("report.json");
    let output = work.path().join("out/report.html");
    std::fs::write(&input, fixture()).unwrap();
    let result = run(&[
        "mck",
        "report",
        "render",
        input.to_str().unwrap(),
        "--format",
        "html",
        "--output",
        output.to_str().unwrap(),
    ]);
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    let html = std::fs::read_to_string(output).unwrap();
    assert!(html.contains("types-0001"));
    assert!(html.contains("2.0.0-draft.1"));
    assert_eq!(std::fs::read_to_string(input).unwrap(), fixture());
}

#[test]
fn invalid_reports_preserve_existing_output_and_input_cannot_be_overwritten() {
    let work = tempfile::tempdir().unwrap();
    let input = work.path().join("report.json");
    let output = work.path().join("report.html");
    std::fs::write(&input, "{\"contractVersion\":1}").unwrap();
    std::fs::write(&output, "previous report").unwrap();
    let result = run(&[
        "mck",
        "report",
        "render",
        input.to_str().unwrap(),
        "--output",
        output.to_str().unwrap(),
    ]);
    assert_eq!(result.status.code(), Some(1));
    assert_eq!(std::fs::read_to_string(&output).unwrap(), "previous report");
    std::fs::write(&input, fixture()).unwrap();
    let alias = work.path().join("alias.json");
    std::fs::hard_link(&input, &alias).unwrap();
    for path in [&input, &alias] {
        let result = run(&[
            "mck",
            "report",
            "render",
            input.to_str().unwrap(),
            "--output",
            path.to_str().unwrap(),
        ]);
        assert_eq!(result.status.code(), Some(2));
        assert_eq!(std::fs::read_to_string(&input).unwrap(), fixture());
    }
}

#[test]
fn report_check_does_not_certify_an_example_without_a_kit_digest() {
    let work = tempfile::tempdir().unwrap();
    let input = work.path().join("report.json");
    let allowed = work.path().join("allowed.json");
    std::fs::write(&input, fixture()).unwrap();
    std::fs::write(&allowed, "{\"cases\":[]}").unwrap();
    let kit = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/ir/mck");
    let result = run(&[
        "mck",
        "report",
        "check",
        input.to_str().unwrap(),
        allowed.to_str().unwrap(),
        "--kit",
        kit.to_str().unwrap(),
    ]);
    assert_eq!(result.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&result.stderr).contains("digest"));
}

#[test]
fn publication_replaces_old_output_and_cleans_temporary_files_on_failure() {
    let work = tempfile::tempdir().unwrap();
    let input = work.path().join("report.json");
    let output = work.path().join("report.html");
    std::fs::write(&input, fixture()).unwrap();
    std::fs::write(&output, "old output").unwrap();
    let render = |destination: &Path| {
        run(&[
            "mck",
            "report",
            "render",
            input.to_str().unwrap(),
            "--output",
            destination.to_str().unwrap(),
        ])
    };
    assert!(render(&output).status.success());
    assert!(
        std::fs::read_to_string(&output)
            .unwrap()
            .contains("types-0001")
    );
    let blocked = work.path().join("blocked.html");
    std::fs::create_dir(&blocked).unwrap();
    std::fs::write(blocked.join("preserve"), "existing contents").unwrap();
    let result = render(&blocked);
    assert_eq!(result.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&result.stderr).contains("cannot write"));
    assert_eq!(
        std::fs::read_to_string(blocked.join("preserve")).unwrap(),
        "existing contents"
    );
    assert_eq!(
        std::fs::read_dir(work.path()).unwrap().count(),
        3,
        "temporary output was cleaned up"
    );
}
