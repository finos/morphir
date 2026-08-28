//! Acceptance tests for the `morphir kb` subcommand tree.
//!
//! Each scenario drives the real binary end to end inside a temporary
//! repository, mirroring the style of `config_acceptance.rs`.

use cucumber::{World, given, then, when};
use serde_json::Value;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Output, Stdio};
use tempfile::TempDir;

#[derive(Debug, Default, World)]
struct KbWorld {
    root: Option<TempDir>,
    output: Option<Output>,
    /// What the next command reads on stdin, for the scenarios that pass `-`.
    /// `None` leaves stdin closed, which is what every other scenario wants.
    stdin: Option<String>,
}

impl KbWorld {
    fn root(&self) -> &Path {
        self.root
            .as_ref()
            .expect("test repository was not created")
            .path()
    }

    fn output(&self) -> &Output {
        self.output.as_ref().expect("the command was not run")
    }

    fn stdout(&self) -> String {
        String::from_utf8_lossy(&self.output().stdout).into_owned()
    }

    fn stderr(&self) -> String {
        String::from_utf8_lossy(&self.output().stderr).into_owned()
    }

    fn json(&self) -> Value {
        serde_json::from_slice(&self.output().stdout).unwrap_or_else(|error| {
            panic!(
                "stdout was not valid JSON: {error}\nstdout:\n{}",
                self.stdout()
            )
        })
    }

    fn run_cli(&mut self, command_line: &str) {
        let arguments: Vec<String> = split_command_line(command_line)
            .into_iter()
            .skip_while(|argument| argument == "morphir")
            .collect();
        let mut command = Command::new(env!("CARGO_BIN_EXE_morphir"));
        command
            .args(&arguments)
            .current_dir(self.root())
            .env("NO_COLOR", "1");
        let output = match self.stdin.take() {
            None => command.output().expect("failed to run morphir CLI"),
            Some(text) => {
                // Spawned rather than `output()`ed because the pipe has to be
                // written and closed before the child can finish reading it.
                command.stdin(Stdio::piped());
                command.stdout(Stdio::piped());
                command.stderr(Stdio::piped());
                let mut child = command.spawn().expect("failed to run morphir CLI");
                child
                    .stdin
                    .take()
                    .expect("stdin was piped")
                    .write_all(text.as_bytes())
                    .expect("failed to write stdin");
                child.wait_with_output().expect("failed to run morphir CLI")
            }
        };
        self.output = Some(output);
    }
}

/// A knowledge base with one sync bundle, a reference checkout it mirrors, an
/// import already done, and one local edit on top — the state every `sync diff`
/// scenario needs before it can ask anything interesting.
///
/// Built in Rust rather than out of `Given a file ... containing:` steps because
/// it is six files plus a `kb sync pull`, and repeating that in every scenario
/// would bury the one line each of them is actually about.
const MIRROR_INDEX: &str = "\
---
okf_version: \"0.2\"
title: Vendored
description: Mirrored upstream material.
sync: true
---

# Vendored

Mirrored upstream material.

## Orientation
";

const MIRROR_MANIFEST: &str = "\
upstream:
  repo: acme/spec
  refs_path: acme/spec
root: sources
mappings:
  - \"docs/**\"
  - \"schemas/**\"
type_map:
  \"docs/**\": Specification Source
";

/// Splits a command line on whitespace, keeping double-quoted spans together
/// (the feature file quotes multi-word flag values).
fn split_command_line(line: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    let mut has_token = false;
    for c in line.chars() {
        match c {
            '"' => {
                in_quotes = !in_quotes;
                has_token = true;
            }
            c if c.is_whitespace() && !in_quotes => {
                if has_token {
                    out.push(std::mem::take(&mut current));
                    has_token = false;
                }
            }
            c => {
                current.push(c);
                has_token = true;
            }
        }
    }
    if has_token {
        out.push(current);
    }
    out
}

#[given("an empty repository")]
fn empty_repository(world: &mut KbWorld) {
    world.root = Some(tempfile::tempdir().expect("failed to create test directory"));
}

#[given(expr = "a knowledge base at {string}")]
fn knowledge_base_at(world: &mut KbWorld, relative_path: String) {
    std::fs::create_dir_all(world.root().join(relative_path).join("bundles"))
        .expect("failed to create knowledge base root");
}

#[given(expr = "a file {string} containing:")]
fn file_containing(world: &mut KbWorld, relative_path: String, step: &cucumber::gherkin::Step) {
    let path = world.root().join(relative_path);
    std::fs::create_dir_all(path.parent().expect("test file has no parent"))
        .expect("failed to create test file parent");
    let mut contents = step
        .docstring
        .as_deref()
        .expect("file content is required")
        .trim_start_matches('\n')
        .to_string();
    if !contents.ends_with('\n') {
        contents.push('\n');
    }
    std::fs::write(path, contents).expect("failed to write test file");
}

#[given("a mirror whose local copy of \"docs/types.md\" has been edited")]
fn edited_mirror(world: &mut KbWorld) {
    world.root = Some(tempfile::tempdir().expect("failed to create test directory"));
    let root = world.root().to_path_buf();
    let bundle = root.join("kb/bundles/vendored");
    let upstream = root.join(".refs/acme/spec");
    write(&bundle.join("index.md"), MIRROR_INDEX);
    write(&bundle.join("sync.yaml"), MIRROR_MANIFEST);
    write(
        &upstream.join("docs/types.md"),
        "---\ntitle: Types\ndescription: The types.\n---\n\n# Types\n",
    );
    write(
        &upstream.join("docs/index.md"),
        "---\ntitle: Docs\ndescription: The docs.\n---\n\n# Docs\n",
    );
    write(
        &upstream.join("schemas/thing.yaml"),
        "$id: thing\ntype: object\n",
    );
    world.run_cli("morphir kb sync pull --kb kb");
    assert!(
        world.output().status.success(),
        "seeding the mirror failed\nstdout:\n{}\nstderr:\n{}",
        world.stdout(),
        world.stderr()
    );
    let mirrored = bundle.join("sources/docs/types.md");
    let mut text = std::fs::read_to_string(&mirrored).expect("the pull wrote docs/types.md");
    text.push_str("\nLocal edit.\n");
    std::fs::write(&mirrored, text).expect("failed to edit the mirrored file");
}

fn write(path: &Path, contents: &str) {
    std::fs::create_dir_all(path.parent().expect("fixture file has no parent"))
        .expect("failed to create fixture parent");
    std::fs::write(path, contents).expect("failed to write fixture file");
}

#[given("stdin holds:")]
fn stdin_holds(world: &mut KbWorld, step: &cucumber::gherkin::Step) {
    world.stdin = Some(
        step.docstring
            .as_deref()
            .expect("stdin content is required")
            .trim_start_matches('\n')
            .to_string(),
    );
}

/// The same list, joined with NUL instead of newline — the shape `find -print0`
/// hands over, which no docstring can hold literally.
#[given("stdin holds NUL-delimited:")]
fn stdin_holds_nul(world: &mut KbWorld, step: &cucumber::gherkin::Step) {
    let body = step
        .docstring
        .as_deref()
        .expect("stdin content is required")
        .trim_start_matches('\n');
    world.stdin = Some(body.replace('\n', "\0"));
}

#[when(expr = "I run {string}")]
fn run_command(world: &mut KbWorld, command_line: String) {
    world.run_cli(&command_line);
}

#[when("I run the command:")]
fn run_command_docstring(world: &mut KbWorld, step: &cucumber::gherkin::Step) {
    let command_line = step
        .docstring
        .as_deref()
        .expect("command docstring is required")
        .trim()
        .to_string();
    world.run_cli(&command_line);
}

#[then("the command succeeds")]
fn command_succeeds(world: &mut KbWorld) {
    assert!(
        world.output().status.success(),
        "command failed\nstdout:\n{}\nstderr:\n{}",
        world.stdout(),
        world.stderr()
    );
}

#[then("the command fails")]
fn command_fails(world: &mut KbWorld) {
    assert!(
        !world.output().status.success(),
        "command unexpectedly succeeded\nstdout:\n{}",
        world.stdout()
    );
}

#[then(expr = "stdout contains {string}")]
fn stdout_contains(world: &mut KbWorld, expected: String) {
    assert!(
        world.stdout().contains(&expected),
        "stdout did not contain {expected:?}\nstdout:\n{}",
        world.stdout()
    );
}

#[then(expr = "stderr contains {string}")]
fn stderr_contains(world: &mut KbWorld, expected: String) {
    assert!(
        world.stderr().contains(&expected),
        "stderr did not contain {expected:?}\nstderr:\n{}",
        world.stderr()
    );
}

#[then(expr = "stdout does not contain {string}")]
fn stdout_does_not_contain(world: &mut KbWorld, unexpected: String) {
    assert!(
        !world.stdout().contains(&unexpected),
        "stdout unexpectedly contained {unexpected:?}\nstdout:\n{}",
        world.stdout()
    );
}

#[then(expr = "stdout is exactly {string}")]
fn stdout_is_exactly(world: &mut KbWorld, expected: String) {
    assert_eq!(world.stdout().trim_end(), expected);
}

#[then("stdout is valid JSON")]
fn stdout_is_valid_json(world: &mut KbWorld) {
    world.json();
}

#[then(expr = "the JSON value at {string} is {int}")]
fn json_value_at_is(world: &mut KbWorld, pointer: String, expected: i64) {
    assert_eq!(world.json().pointer(&pointer), Some(&Value::from(expected)));
}

#[tokio::main]
async fn main() {
    KbWorld::run("tests/features/kb.feature").await;
}
