use cucumber::{World, given, then, when};
use serde_json::Value;
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use tempfile::TempDir;

#[derive(Debug, Default, World)]
struct ConfigWorld {
    root: Option<TempDir>,
    working_directory: Option<PathBuf>,
    environment: BTreeMap<String, String>,
    output: Option<Output>,
}

impl ConfigWorld {
    fn root(&self) -> &Path {
        self.root
            .as_ref()
            .expect("test root was not created")
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
}

#[given("an isolated Morphir configuration environment")]
fn isolated_environment(world: &mut ConfigWorld) {
    let root = tempfile::tempdir().expect("failed to create test directory");
    for directory in ["home", "app-data", "program-data", "xdg-config"] {
        std::fs::create_dir_all(root.path().join(directory))
            .expect("failed to create isolated configuration directory");
    }
    world.working_directory = Some(root.path().to_path_buf());
    world.root = Some(root);
}

#[given(expr = "a file {string} containing:")]
fn file_containing(world: &mut ConfigWorld, relative_path: String, step: &cucumber::gherkin::Step) {
    let path = world.root().join(relative_path);
    std::fs::create_dir_all(path.parent().expect("test file has no parent"))
        .expect("failed to create test file parent");
    std::fs::write(
        path,
        step.docstring.as_deref().expect("file content is required"),
    )
    .expect("failed to write test file");
}

#[given(expr = "the working directory is {string}")]
fn working_directory(world: &mut ConfigWorld, relative_path: String) {
    let path = world.root().join(relative_path);
    std::fs::create_dir_all(&path).expect("failed to create working directory");
    world.working_directory = Some(path);
}

#[given(expr = "the environment variable {string} is {string}")]
fn environment_variable(world: &mut ConfigWorld, name: String, value: String) {
    world.environment.insert(name, value);
}

#[when(expr = "I run {string}")]
fn run_command(world: &mut ConfigWorld, command_line: String) {
    let arguments = command_line
        .split_whitespace()
        .skip_while(|argument| *argument == "morphir")
        .collect::<Vec<_>>();
    let root = world.root().to_path_buf();
    let inherited_morphir_variables = std::env::vars_os()
        .filter(|(name, _)| name.to_string_lossy().starts_with("MORPHIR_"))
        .map(|(name, _)| name)
        .collect::<Vec<OsString>>();

    let mut command = Command::new(env!("CARGO_BIN_EXE_morphir"));
    command
        .args(arguments)
        .current_dir(
            world
                .working_directory
                .as_ref()
                .expect("working directory was not set"),
        )
        .env("HOME", root.join("home"))
        .env("USERPROFILE", root.join("home"))
        .env("APPDATA", root.join("app-data"))
        .env("PROGRAMDATA", root.join("program-data"))
        .env("XDG_CONFIG_HOME", root.join("xdg-config"))
        .env("NO_COLOR", "1");

    for name in inherited_morphir_variables {
        command.env_remove(name);
    }
    for (name, value) in &world.environment {
        command.env(name, value);
    }

    world.output = Some(command.output().expect("failed to run morphir CLI"));
}

#[then("the command succeeds")]
fn command_succeeds(world: &mut ConfigWorld) {
    assert!(
        world.output().status.success(),
        "command failed\nstdout:\n{}\nstderr:\n{}",
        world.stdout(),
        world.stderr()
    );
}

#[then("the command fails")]
fn command_fails(world: &mut ConfigWorld) {
    assert!(
        !world.output().status.success(),
        "command unexpectedly succeeded\nstdout:\n{}",
        world.stdout()
    );
}

#[then(expr = "stdout contains {string}")]
fn stdout_contains(world: &mut ConfigWorld, expected: String) {
    assert!(
        world.stdout().contains(&expected),
        "stdout did not contain {expected:?}\nstdout:\n{}",
        world.stdout()
    );
}

#[then(expr = "stdout does not contain {string}")]
fn stdout_does_not_contain(world: &mut ConfigWorld, unexpected: String) {
    assert!(
        !world.stdout().contains(&unexpected),
        "stdout contained {unexpected:?}\nstdout:\n{}",
        world.stdout()
    );
}

#[then(expr = "stdout is exactly {string}")]
fn stdout_is_exactly(world: &mut ConfigWorld, expected: String) {
    assert_eq!(world.stdout().trim_end(), expected);
}

#[then(expr = "stderr contains {string}")]
fn stderr_contains(world: &mut ConfigWorld, expected: String) {
    assert!(
        world.stderr().contains(&expected),
        "stderr did not contain {expected:?}\nstderr:\n{}",
        world.stderr()
    );
}

#[then("stdout is valid JSON")]
fn stdout_is_valid_json(world: &mut ConfigWorld) {
    world.json();
}

#[then(expr = "the JSON project name is {string}")]
fn json_project_name(world: &mut ConfigWorld, expected: String) {
    assert_eq!(
        world.json().pointer("/config/project/name"),
        Some(&Value::String(expected))
    );
}

#[then(expr = "the JSON project config ends with {string}")]
fn json_project_config_ends_with(world: &mut ConfigWorld, expected: String) {
    let json = world.json();
    let actual = json["project_config"]
        .as_str()
        .expect("project_config was not a string");
    assert!(
        Path::new(actual).ends_with(Path::new(&expected)),
        "project config {actual:?} did not end with {expected:?}"
    );
}

#[then(expr = "the JSON config value at {string} is {int}")]
fn json_config_integer(world: &mut ConfigWorld, pointer: String, expected: i64) {
    assert_eq!(
        world.json().pointer(&format!("/config{pointer}")),
        Some(&Value::from(expected))
    );
}

#[then(expr = "the JSON get key is {string}")]
fn json_get_key(world: &mut ConfigWorld, expected: String) {
    assert_eq!(world.json().pointer("/key"), Some(&Value::String(expected)));
}

#[then(expr = "the JSON get value is {int}")]
fn json_get_integer(world: &mut ConfigWorld, expected: i64) {
    assert_eq!(world.json().pointer("/value"), Some(&Value::from(expected)));
}

#[then(expr = "the JSON source {string} has status {string}")]
fn json_source_status(world: &mut ConfigWorld, kind: String, expected_status: String) {
    let json = world.json();
    let source = json["sources"]
        .as_array()
        .expect("sources was not an array")
        .iter()
        .find(|source| source["kind"] == kind)
        .unwrap_or_else(|| panic!("source {kind:?} was not reported"));
    assert_eq!(source["status"], expected_status);
}

#[then("the JSON sources are ordered by ascending priority")]
fn json_sources_are_ordered(world: &mut ConfigWorld) {
    let json = world.json();
    let priorities = json["sources"]
        .as_array()
        .expect("sources was not an array")
        .iter()
        .map(|source| {
            source["priority"]
                .as_u64()
                .expect("priority was not an integer")
        })
        .collect::<Vec<_>>();
    assert!(
        priorities.windows(2).all(|pair| pair[0] <= pair[1]),
        "source priorities were not ascending: {priorities:?}"
    );
}

#[tokio::main]
async fn main() {
    ConfigWorld::run("tests/features/config.feature").await;
}
