//! CLI integration tests for Morphir
//!
//! These tests require the morphir binary to be pre-built and available.
//! Run `mise run build:release` before running these tests.

use cucumber::{World, given, then, when};
use integration_tests::{CliTestContext, cli_tests_available};

/// World state for CLI cucumber tests
#[derive(Debug, Default, World)]
pub struct CliWorld {
    context: Option<CliTestContext>,
    last_result: Option<integration_tests::CommandResult>,
}

#[given("the morphir CLI is built and available")]
fn given_morphir_cli_is_available(_world: &mut CliWorld) {
    assert!(
        CliTestContext::get_morphir_binary().is_some(),
        "build the morphir CLI before running integration tests"
    );
}

#[given("I have a temporary test directory")]
fn given_temp_directory(world: &mut CliWorld) {
    world.context = Some(CliTestContext::new().expect("create temporary test directory"));
}

#[given(regex = r#"I have a Classic IR file from fixture "([^"]+)""#)]
fn given_classic_ir_fixture(world: &mut CliWorld, name: String) {
    let fixture = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../website/static/ir/examples/v3")
        .join(&name);
    let contents = std::fs::read_to_string(&fixture)
        .unwrap_or_else(|error| panic!("read {}: {error}", fixture.display()));
    world
        .context
        .as_ref()
        .expect("temporary test directory")
        .write_source_file(&name, &contents)
        .expect("copy Classic IR fixture");
}

#[given(regex = r#"I have a file "([^"]+)" with:"#)]
fn given_file_with_contents(world: &mut CliWorld, name: String, step: &cucumber::gherkin::Step) {
    let contents = step.docstring().expect("file contents docstring");
    world
        .context
        .as_ref()
        .expect("temporary test directory")
        .write_source_file(&name, contents)
        .expect("write test file");
}

#[when(regex = r#"I run "([^"]+)""#)]
fn when_run_morphir(world: &mut CliWorld, command: String) {
    let args: Vec<&str> = command.split_whitespace().collect();
    assert_eq!(args.first(), Some(&"morphir"), "expected a morphir command");
    world.last_result = Some(
        world
            .context
            .as_ref()
            .expect("temporary test directory")
            .execute_cli_command(&args[1..])
            .expect("execute morphir command"),
    );
}

#[then("the command should succeed")]
fn then_command_should_succeed(world: &mut CliWorld) {
    world
        .last_result
        .as_ref()
        .expect("CLI result")
        .assert_success();
}

#[then("the command should fail")]
fn then_command_should_fail(world: &mut CliWorld) {
    world
        .last_result
        .as_ref()
        .expect("CLI result")
        .assert_failure();
}

#[then(regex = r#"the file "([^"]+)" should have V4 Library package "([^"]+)""#)]
fn then_file_has_v4_library_package(world: &mut CliWorld, file: String, package: String) {
    let path = world
        .context
        .as_ref()
        .expect("temporary test directory")
        .project_root
        .join(&file);
    let document: serde_json::Value = serde_json::from_slice(
        &std::fs::read(&path).unwrap_or_else(|error| panic!("read {}: {error}", path.display())),
    )
    .expect("output must be valid JSON");
    assert_eq!(document["formatVersion"], 4);
    assert_eq!(document["distribution"]["Library"]["packageName"], package);
    assert!(document["distribution"]["Library"]["def"]["modules"].is_object());
}

#[then(regex = r#"the stderr should contain "([^"]+)""#)]
fn then_stderr_contains(world: &mut CliWorld, expected: String) {
    let stderr = &world.last_result.as_ref().expect("CLI result").stderr;
    assert!(
        stderr.contains(&expected),
        "stderr did not contain {expected:?}: {stderr}"
    );
}

// Background step
#[given("I have a temporary test project")]
fn given_temp_project(world: &mut CliWorld) {
    if !cli_tests_available() {
        // Skip test if CLI binary not available
        return;
    }

    let context = CliTestContext::new().expect("Failed to create test context");
    context
        .create_test_project()
        .expect("Failed to create test project");
    world.context = Some(context);
}

// Source file step
#[given(regex = r#"I have a Gleam source file "([^"]+)" with:"#)]
fn given_gleam_source_file(world: &mut CliWorld, path: String, step: &cucumber::gherkin::Step) {
    if let Some(context) = &world.context {
        let content = step
            .docstring()
            .expect("Expected docstring with file content");
        context
            .write_source_file(&path, content)
            .expect("Failed to write source file");
    }
}

// CLI command step
#[when(regex = r#"I run CLI command "([^"]+)""#)]
fn when_run_cli_command(world: &mut CliWorld, command: String) {
    if let Some(context) = &world.context {
        // Parse the command string into args
        let args: Vec<&str> = command.split_whitespace().collect();
        // Skip the "morphir" part if present
        let args = if args.first() == Some(&"morphir") {
            &args[1..]
        } else {
            &args[..]
        };

        match context.execute_cli_command(args) {
            Ok(result) => world.last_result = Some(result),
            Err(e) => panic!("Failed to execute CLI command: {}", e),
        }
    }
}

// Success assertion
#[then("the CLI command should succeed")]
fn then_cli_should_succeed(world: &mut CliWorld) {
    if let Some(result) = &world.last_result {
        result.assert_success();
    }
}

// Failure assertion
#[then("the CLI command should fail")]
fn then_cli_should_fail(world: &mut CliWorld) {
    if let Some(result) = &world.last_result {
        result.assert_failure();
    }
}

// Output contains assertion
#[then(regex = r#"the output should contain "([^"]+)""#)]
fn then_output_contains(world: &mut CliWorld, text: String) {
    if let Some(result) = &world.last_result {
        result.assert_output_contains(&text);
    }
}

#[tokio::main]
async fn main() {
    CliWorld::cucumber()
        .fail_on_skipped()
        .filter_run_and_exit("tests/features", |feature, rule, scenario| {
            !feature.tags.iter().any(|tag| tag == "wip")
                && !rule.is_some_and(|rule| rule.tags.iter().any(|tag| tag == "wip"))
                && !scenario.tags.iter().any(|tag| tag == "wip")
        })
        .await;
}
