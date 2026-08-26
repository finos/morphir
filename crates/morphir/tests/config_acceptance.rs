use cucumber::{World, given, then, when};
use morphir_common::config::{ExposeSecret, SecretReference, SecretString};
use morphir_devkit::{
    ConfigLoadOptions, SecretResolutionContext, SecretResolutionError, SecretResolver,
    SystemSecretResolver, discover_config, load_effective_config,
};
use serde_json::Value;
use std::collections::BTreeMap;
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use tempfile::TempDir;

const TEST_SECRET: &str = "acceptance-secret-value";
const COMMAND_SECRET: &str = "command-secret";
const COMMAND_STDOUT_SENTINEL: &str = "stdout-secret-sentinel";
const COMMAND_STDERR_SENTINEL: &str = "stderr-secret-sentinel";
const SECRET_ENVIRONMENT_VARIABLE: &str = "MORPHIR_ACCEPTANCE_SECRET";
const SECRET_KEYRING_SERVICE: &str = "morphir-acceptance";
const SECRET_KEYRING_ACCOUNT: &str = "registry-token";
const SECRET_FILE: &str = "secrets/registry-token";
const SECRET_MARKER: &str = "secret-command-marker";

#[derive(Debug, Default, World)]
struct ConfigWorld {
    root: Option<TempDir>,
    working_directory: Option<PathBuf>,
    environment: BTreeMap<String, String>,
    resolved_secret: Option<SecretString>,
    expected_secret: Option<SecretString>,
    resolution_error: Option<SecretResolutionError>,
    secret_environment: BTreeMap<String, SecretString>,
    keyring_values: BTreeMap<(String, String), SecretString>,
    output: Option<Output>,
}

#[derive(Debug)]
struct AcceptanceResolver<'a> {
    secret_environment: &'a BTreeMap<String, SecretString>,
    keyring_values: &'a BTreeMap<(String, String), SecretString>,
}

impl SecretResolver for AcceptanceResolver<'_> {
    fn resolve(
        &self,
        reference: &SecretReference,
        context: SecretResolutionContext<'_>,
    ) -> Result<SecretString, SecretResolutionError> {
        match reference {
            SecretReference::Environment { variable } => self
                .secret_environment
                .get(variable)
                .cloned()
                .ok_or_else(|| SecretResolutionError::EnvironmentMissing {
                    variable: variable.clone(),
                })
                .and_then(|value| non_empty_secret(value, "environment")),
            SecretReference::Keyring { service, account } => self
                .keyring_values
                .get(&(service.clone(), account.clone()))
                .cloned()
                .ok_or_else(|| SecretResolutionError::KeyringLookupFailed {
                    config_key: context.config_key.to_owned(),
                    service: service.clone(),
                    account: account.clone(),
                })
                .and_then(|value| non_empty_secret(value, "keyring")),
            SecretReference::File { .. } | SecretReference::Command { .. } => {
                SystemSecretResolver.resolve(reference, context)
            }
        }
    }
}

fn non_empty_secret(
    value: SecretString,
    backend: &'static str,
) -> Result<SecretString, SecretResolutionError> {
    if value.expose_secret().is_empty() {
        Err(SecretResolutionError::EmptySecret { backend })
    } else {
        Ok(value)
    }
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

fn write_file(world: &ConfigWorld, relative_path: &str, contents: impl AsRef<[u8]>) {
    let path = world.root().join(relative_path);
    std::fs::create_dir_all(path.parent().expect("test file has no parent"))
        .expect("failed to create test file parent");
    std::fs::write(path, contents).expect("failed to write test file");
}

fn command_reference(arguments: impl IntoIterator<Item = OsString>) -> String {
    let command = toml::Value::Array(
        arguments
            .into_iter()
            .map(|argument| {
                toml::Value::String(
                    argument
                        .into_string()
                        .expect("test executable arguments must be Unicode"),
                )
            })
            .collect(),
    );
    format!("[registry]\ntoken = {{ command = {command} }}\n")
}

fn secret_helper_arguments(mode: &str) -> Vec<OsString> {
    vec![
        std::env::current_exe()
            .expect("failed to locate the acceptance test executable")
            .into_os_string(),
        OsString::from("--secret-helper"),
        OsString::from(mode),
    ]
}

#[given(expr = "a file {string} containing the {word} secret reference")]
fn file_containing_secret_reference(
    world: &mut ConfigWorld,
    relative_path: String,
    reference: String,
) {
    let contents = match reference.as_str() {
        "literal" => format!("[registry]\ntoken = {TEST_SECRET:?}\n"),
        "environment" => {
            format!("[registry]\ntoken = {{ env = {SECRET_ENVIRONMENT_VARIABLE:?} }}\n")
        }
        "file" => format!("[registry]\ntoken = {{ file = {SECRET_FILE:?} }}\n"),
        "command" => command_reference(secret_helper_arguments("success")),
        "keyring" => format!(
            "[registry]\ntoken = {{ keyring = {{ service = {SECRET_KEYRING_SERVICE:?}, account = {SECRET_KEYRING_ACCOUNT:?} }} }}\n"
        ),
        _ => panic!("unsupported secret reference fixture"),
    };
    world.expected_secret = Some(SecretString::from(if reference == "command" {
        COMMAND_SECRET
    } else {
        TEST_SECRET
    }));
    write_file(world, &relative_path, contents);
}

#[given(expr = "the {word} secret source contains a test value")]
fn secret_source_contains_test_value(world: &mut ConfigWorld, backend: String) {
    match backend.as_str() {
        "literal" | "command" => {}
        "environment" => {
            world.secret_environment.insert(
                SECRET_ENVIRONMENT_VARIABLE.to_owned(),
                SecretString::from(TEST_SECRET.to_owned()),
            );
        }
        "file" => write_file(world, SECRET_FILE, TEST_SECRET),
        "keyring" => {
            world.keyring_values.insert(
                (
                    SECRET_KEYRING_SERVICE.to_owned(),
                    SECRET_KEYRING_ACCOUNT.to_owned(),
                ),
                SecretString::from(TEST_SECRET.to_owned()),
            );
        }
        _ => panic!("unsupported secret backend fixture"),
    }
}

#[given(expr = "a file {string} containing the {word} failing secret reference")]
fn file_containing_failing_secret_reference(
    world: &mut ConfigWorld,
    relative_path: String,
    reference: String,
) {
    let contents = match reference.as_str() {
        "missing-file" => "[registry]\ntoken = { file = \"missing-secret\" }\n".to_owned(),
        "malformed" => {
            "[registry]\ntoken = { env = \"MORPHIR_ACCEPTANCE_SECRET\", file = \"missing-secret\" }\n".to_owned()
        }
        "empty-environment" => {
            world.secret_environment.insert(
                SECRET_ENVIRONMENT_VARIABLE.to_owned(),
                SecretString::from(String::new()),
            );
            format!(
                "[registry]\ntoken = {{ env = {SECRET_ENVIRONMENT_VARIABLE:?} }}\n"
            )
        }
        "failing-command" => command_reference(secret_helper_arguments("failure")),
        "missing-keyring" => format!(
            "[registry]\ntoken = {{ keyring = {{ service = {SECRET_KEYRING_SERVICE:?}, account = {SECRET_KEYRING_ACCOUNT:?} }} }}\n"
        ),
        _ => panic!("unsupported failing secret reference fixture"),
    };
    write_file(world, &relative_path, contents);
}

#[given(expr = "a file {string} containing a marker command secret reference")]
fn file_containing_marker_command_secret_reference(world: &mut ConfigWorld, relative_path: String) {
    let mut arguments = secret_helper_arguments("marker");
    arguments.push(world.root().join(SECRET_MARKER).into_os_string());
    write_file(world, &relative_path, command_reference(arguments));
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

#[when(expr = "the config secret {string} is resolved")]
fn resolve_config_secret(world: &mut ConfigWorld, key: String) {
    let config_path = discover_config(
        world
            .working_directory
            .as_deref()
            .expect("working directory was not set"),
    )
    .expect("failed to discover configuration")
    .expect("test configuration was not discovered");
    let effective = load_effective_config(Some(&config_path), &ConfigLoadOptions::project_only())
        .expect("failed to load effective configuration");
    let resolver = AcceptanceResolver {
        secret_environment: &world.secret_environment,
        keyring_values: &world.keyring_values,
    };
    match effective.resolve_secret_with(&key, &resolver) {
        Ok(secret) => {
            world.resolved_secret = Some(secret);
            world.resolution_error = None;
        }
        Err(error) => {
            world.resolved_secret = None;
            world.resolution_error = Some(error);
        }
    }
}

#[when("I load the effective configuration directly")]
fn load_effective_configuration_directly(world: &mut ConfigWorld) {
    let project_config = discover_config(
        world
            .working_directory
            .as_deref()
            .expect("working directory was not set"),
    )
    .expect("failed to discover configuration");
    load_effective_config(
        project_config.as_deref(),
        &ConfigLoadOptions::project_only(),
    )
    .expect("failed to load effective configuration");
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

#[then("the protected secret matches the test value")]
fn protected_secret_matches_test_value(world: &mut ConfigWorld) {
    let expected = world
        .expected_secret
        .as_ref()
        .expect("the expected protected test fixture was not set")
        .expose_secret();
    assert!(
        world.resolved_secret.as_ref().unwrap().expose_secret() == expected,
        "protected secret did not match the expected test fixture"
    );
}

#[then(expr = "no command output contains the test value")]
fn no_command_output_contains_test_value(world: &mut ConfigWorld) {
    let expected = world
        .expected_secret
        .as_ref()
        .expect("the expected protected test fixture was not set")
        .expose_secret()
        .as_bytes();
    assert!(
        !world.output.as_ref().is_some_and(|output| output
            .stdout
            .windows(expected.len())
            .any(|value| value == expected)
            || output
                .stderr
                .windows(expected.len())
                .any(|value| value == expected)),
        "command output unexpectedly disclosed a protected fixture"
    );
}

#[then(expr = "no command output contains {string}")]
fn no_command_output_contains(world: &mut ConfigWorld, unexpected: String) {
    assert!(
        !world.output.as_ref().is_some_and(|output| output
            .stdout
            .windows(unexpected.len())
            .any(|value| value == unexpected.as_bytes())
            || output
                .stderr
                .windows(unexpected.len())
                .any(|value| value == unexpected.as_bytes())),
        "command output unexpectedly disclosed a protected fixture"
    );
}

#[then(expr = "the resolution error is classified as {word}")]
fn resolution_error_is_classified_as(world: &mut ConfigWorld, classification: String) {
    let error = world
        .resolution_error
        .as_ref()
        .expect("secret resolution unexpectedly succeeded");
    let matches_classification = match classification.as_str() {
        "file-read" => matches!(error, SecretResolutionError::FileRead { .. }),
        "invalid-secret-value" => matches!(error, SecretResolutionError::InvalidSecretValue { .. }),
        "empty-environment" => matches!(
            error,
            SecretResolutionError::EmptySecret {
                backend: "environment"
            }
        ),
        "command-failed" => matches!(error, SecretResolutionError::CommandFailed { .. }),
        "keyring-lookup-failed" => {
            matches!(error, SecretResolutionError::KeyringLookupFailed { .. })
        }
        _ => false,
    };
    assert!(
        matches_classification,
        "secret resolution had the wrong safe classification"
    );
}

#[then("the resolution diagnostic omits protected backend output")]
fn resolution_diagnostic_omits_protected_backend_output(world: &mut ConfigWorld) {
    let diagnostic = world
        .resolution_error
        .as_ref()
        .expect("secret resolution unexpectedly succeeded")
        .to_string();
    assert!(
        !diagnostic.contains(COMMAND_STDOUT_SENTINEL)
            && !diagnostic.contains(COMMAND_STDERR_SENTINEL),
        "secret resolution diagnostic disclosed protected backend output"
    );
}

#[then("the secret command marker does not exist")]
fn secret_command_marker_does_not_exist(world: &mut ConfigWorld) {
    assert!(
        !world.root().join(SECRET_MARKER).exists(),
        "loading configuration unexpectedly ran the secret command"
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

#[then(expr = "the JSON config string at {string} is {string}")]
fn json_config_string(world: &mut ConfigWorld, pointer: String, expected: String) {
    assert_eq!(
        world.json().pointer(&format!("/config{pointer}")),
        Some(&Value::String(expected))
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

fn run_secret_helper_if_requested() -> bool {
    let mut args = std::env::args_os();
    let _binary = args.next();
    if args.next().as_deref() != Some(OsStr::new("--secret-helper")) {
        return false;
    }
    match args.next().as_deref() {
        Some(mode) if mode == OsStr::new("success") => {
            print!("command-secret\r\n");
            true
        }
        Some(mode) if mode == OsStr::new("failure") => {
            print!("{COMMAND_STDOUT_SENTINEL}");
            eprint!("{COMMAND_STDERR_SENTINEL}");
            std::process::exit(23);
        }
        Some(mode) if mode == OsStr::new("marker") => {
            let marker = PathBuf::from(args.next().expect("marker path"));
            std::fs::write(marker, b"executed").expect("write marker");
            print!("marker-secret");
            true
        }
        _ => std::process::exit(64),
    }
}

#[tokio::main]
async fn main() {
    if run_secret_helper_if_requested() {
        return;
    }
    ConfigWorld::run("tests/features/config.feature").await;
}
