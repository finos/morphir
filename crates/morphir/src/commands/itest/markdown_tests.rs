use super::{Scenario, discover, workspace};
use std::fs;

const EXAMPLE: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../examples/cli/basics/scenarios.md"
));

fn load(text: &str) -> anyhow::Result<Vec<Scenario>> {
    let root = tempfile::tempdir()?;
    fs::write(root.path().join("scenarios.md"), text)?;
    discover(root.path(), None)
}

#[test]
fn markdown_headings_metadata_and_prose_preserve_scenario_boundaries() {
    let text = EXAMPLE.replace(
        "```\n\n```sh",
        "```\n\nSome **explanation**.\n\n- A note\n\n### Details\n\n```sh",
    );
    let scenarios = load(&text).unwrap();
    assert_eq!(
        scenarios.iter().map(|s| s.id.as_str()).collect::<Vec<_>>(),
        [".#command-help", ".#version"]
    );
    assert_eq!(scenarios[1].metadata.title, "Report version");
    assert_eq!(scenarios[1].steps.len(), 1);
    assert_eq!(scenarios[1].steps[0].args, ["--version"]);
    let super::model::AssertionKind::Rego { entrypoints, .. } =
        &scenarios[1].steps[0].assertions[0].kind
    else {
        panic!("expected Rego assertion");
    };
    assert_eq!(entrypoints, &["data.version_test.reports_version"]);
}

#[test]
fn markdown_rejects_invalid_metadata_pairs_and_scenario_boundaries() {
    for (text, diagnostic) in [
        (EXAMPLE.replacen("version: 1", "version: 2", 1), "version"),
        (
            EXAMPLE.replacen("title: CLI basics", "title: ''", 1),
            "title",
        ),
        (
            EXAMPLE.replacen("version: 1", "version: 1\nversion: 1", 1),
            "duplicate",
        ),
        (
            EXAMPLE.replacen("provider: rego", "provider: rego\nunknown: true", 1),
            "unknown",
        ),
        (
            EXAMPLE.replacen("timeout_seconds: 10", "timeout_second: 10", 1),
            "timeout_second",
        ),
        (
            EXAMPLE.replacen("id: run", "id: run\nid: other", 1),
            "duplicate",
        ),
        (
            EXAMPLE.replacen("morphir:command", "morphir:commmand", 1),
            "unknown Morphir fence",
        ),
        (
            EXAMPLE.replacen("yaml morphir:command", "json morphir:command", 1),
            "yaml",
        ),
        (EXAMPLE.replacen("```sh", "```", 1), "source language"),
        (
            EXAMPLE.replacen("```sh", "```yaml morphir:command", 1),
            "source fence",
        ),
        (
            EXAMPLE.replacen("```sh", "## Interrupted\n\n```sh", 1),
            "source fence",
        ),
        (
            EXAMPLE.replacen("## Report version {#version}", "# Report version", 1),
            "scenario heading",
        ),
        (
            EXAMPLE.replace("## Command help", "## Other {#version}"),
            "duplicate scenario",
        ),
        (
            EXAMPLE
                .replace("{#version}", "")
                .replace("## Command help", "## Report version"),
            "duplicate scenario",
        ),
        (EXAMPLE.replace("{#version}", "{#../escape}"), "scenario id"),
        (EXAMPLE.replacen("```rego", "```sh", 1), "rego"),
        (
            EXAMPLE.replacen("id: check", "id: run", 1),
            "duplicate Morphir block id",
        ),
        (
            EXAMPLE.replacen("command: run", "command: future", 1),
            "missing or forward",
        ),
        (
            EXAMPLE.trim_end().trim_end_matches("```").to_owned(),
            "unclosed",
        ),
        (
            format!("{EXAMPLE}\n```yaml morphir:file\nid: dangling\npath: data.txt\n```\n"),
            "source fence",
        ),
    ] {
        let error = load(&text).unwrap_err();
        let error = format!("{error:#}");
        assert!(
            error.to_lowercase().contains(&diagnostic.to_lowercase()),
            "expected {diagnostic:?}: {error}"
        );
    }
}

#[test]
fn markdown_does_not_treat_an_indented_content_line_as_a_closing_fence() {
    for indentation in ["    ", "\t", " \t"] {
        let text = format!(
            "{}{indentation}```",
            EXAMPLE.trim_end().trim_end_matches("```")
        );
        let error = format!("{:#}", load(&text).unwrap_err());
        assert!(error.contains("unclosed"), "{error}");
    }
}

#[test]
fn markdown_file_fences_preserve_literal_language_contents_and_line_endings() {
    let root = tempfile::tempdir().unwrap();
    let prefix = "---\nversion: 1\ntitle: Files\ndescription: Preserve literal code.\ntags: [area:files]\nprovider: rego\nworkspace: {kind: inline}\n---\n\n## Files\n\n";
    let file = "~~~yaml morphir:file\nid: source\npath: src/Example.elm\n~~~\n\nProse between metadata and source.\n\n~~~elm\nmodule Example exposing (..)\n\n-- ## This is not a scenario\nvalue = \"```\"\n~~~\n\n";
    let commands = EXAMPLE.split("```yaml morphir:command").nth(1).unwrap();
    let commands = commands.split("## Command help").next().unwrap();
    let text = format!("{prefix}{file}```yaml morphir:command{commands}").replace('\n', "\r\n");
    fs::write(root.path().join("scenarios.md"), text).unwrap();
    // Explicit inline mode ignores neighboring disk inputs.
    fs::write(root.path().join("unrelated.txt"), "not copied").unwrap();
    let scenarios = discover(root.path(), None).unwrap();
    let target = tempfile::tempdir().unwrap();
    workspace::materialize(&scenarios[0], target.path()).unwrap();
    assert_eq!(
        fs::read_to_string(target.path().join("src/Example.elm")).unwrap(),
        "module Example exposing (..)\r\n\r\n-- ## This is not a scenario\r\nvalue = \"```\"\r\n"
    );
    assert!(!target.path().join("unrelated.txt").exists());
}

#[test]
fn markdown_rejects_non_top_level_executable_blocks() {
    let text = EXAMPLE.replacen("```yaml morphir:command\nid: run\nname: Report CLI version\ntimeout_seconds: 10\n```", "> ```yaml morphir:command\n> id: run\n> name: Report CLI version\n> timeout_seconds: 10\n> ```", 1);
    let error = format!("{:#}", load(&text).unwrap_err());
    assert!(error.contains("top-level"), "{error}");
}
