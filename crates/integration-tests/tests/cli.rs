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
    // All CLI tests are currently @wip - skip them
    CliWorld::cucumber()
        .filter_run("tests/features", |feature, _rule, _scenario| {
            // Skip features with @wip tag
            let feature_has_wip = feature.tags.iter().any(|t| t == "wip");
            !feature_has_wip
        })
        .await;
}
