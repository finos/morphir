# WIP: CLI integration tests require full CLI functionality
# See: https://github.com/finos/morphir-rust/issues/40
@wip
Feature: CLI Integration
  As a developer
  I want to use the Morphir CLI to compile and generate Gleam code
  So that I can integrate Morphir into my build process

  Background:
    Given I have a temporary test project

  @cli @e2e
  Scenario: Compile single Gleam file via CLI
    Given I have a Gleam source file "src/main.gleam" with:
      """
      pub fn hello() {
        "world"
      }
      """
    When I run CLI command "morphir gleam compile --input src/"
    Then the CLI command should succeed
    And the CLI should create .morphir/out/ structure
    And the output should contain "Compilation successful"

  @cli @e2e
  Scenario: Compile Gleam project via CLI
    Given I have a Gleam project structure:
      | path              | content                    |
      | src/main.gleam    | pub fn main() { "hello" } |
      | src/utils.gleam   | pub fn util() { 42 }      |
      | morphir.toml      | [project]\nname = "test"  |
    When I run CLI command "morphir gleam compile"
    Then the CLI command should succeed
    And the CLI should create .morphir/out/test/compile/gleam/ structure

  @cli @e2e
  Scenario: Generate Gleam code from IR via CLI
    Given I have compiled IR at ".morphir/out/test/compile/gleam/"
    When I run CLI command "morphir gleam generate --input .morphir/out/test/compile/gleam/"
    Then the CLI command should succeed
    And the CLI should create .morphir/out/test/generate/gleam/ structure

  @cli @e2e
  Scenario: Roundtrip via CLI (compile then generate)
    Given I have a Gleam source file "src/main.gleam" with:
      """
      pub fn hello() {
        "world"
      }
      """
    When I run CLI command "morphir gleam roundtrip --input src/"
    Then the CLI command should succeed
    And the CLI should create both compile and generate output structures

  @cli @e2e @config
  Scenario: CLI with morphir.toml configuration
    Given I have a morphir.toml file:
      """
      [project]
      name = "my-package"
      source_directory = "src"

      [frontend]
      language = "gleam"
      """
    And I have a Gleam source file "src/main.gleam" with:
      """
      pub fn main() {
        "hello"
      }
      """
    When I run CLI command "morphir compile"
    Then the CLI command should succeed
    And the CLI should use configuration from morphir.toml

  @cli @json
  Scenario: CLI with JSON output
    Given I have a Gleam source file "src/main.gleam" with:
      """
      pub fn main() {
        "hello"
      }
      """
    When I run CLI command "morphir gleam compile --input src/ --json"
    Then the CLI command should succeed
    And the JSON output should be valid
    And the JSON output should contain "success"

  @cli @json
  Scenario: CLI with JSON Lines output
    Given I have a Gleam source file "src/main.gleam" with:
      """
      pub fn main() {
        "hello"
      }
      """
    When I run CLI command "morphir gleam compile --input src/ --json-lines"
    Then the CLI command should succeed
    And the JSON Lines output should be valid

  @cli @error-handling
  Scenario: CLI error handling (missing files)
    When I run CLI command "morphir gleam compile --input nonexistent/"
    Then the CLI command should fail
    And the error output should contain "not found" or "does not exist"

  @cli @error-handling
  Scenario: CLI error handling (invalid config)
    Given I have an invalid morphir.toml file:
      """
      [project]
      name = invalid syntax
      """
    When I run CLI command "morphir compile"
    Then the CLI command should fail
    And the error output should contain "config" or "parse"

  @cli
  Scenario Outline: CLI commands with various flags and options
    Given I have a Gleam source file "src/main.gleam" with:
      """
      pub fn main() {
        "hello"
      }
      """
    When I run CLI command "<command>"
    Then the CLI command should <result>

    Examples:
      | command                                          | result  |
      | morphir gleam compile --input src/              | succeed |
      | morphir compile --language gleam --input src/   | succeed |
      | morphir gleam compile --input src/ --json       | succeed |
      | morphir gleam roundtrip --input src/            | succeed |
