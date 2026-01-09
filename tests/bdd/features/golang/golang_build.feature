@golang @cli @build
Feature: Go Build Pipeline CLI
  The morphir golang build command executes the full pipeline
  from IR to generated Go code in a single step.

  Background:
    Given the morphir CLI is available

  Rule: Build command validation

    Scenario: morphir golang build requires IR file
      When I run morphir golang build without an IR file
      Then the command should fail
      And the error should mention "IR file"

    Scenario: morphir golang build requires output directory
      When I run morphir golang build without --output flag
      Then the command should fail
      And the error should mention "output"

    Scenario: morphir golang build requires module path
      When I run morphir golang build without --module-path flag
      Then the command should fail
      And the error should mention "module-path"

  Rule: Build command execution

    Scenario: morphir golang build generates Go module
      Given a minimal Morphir IR file
      When I run morphir golang build with valid arguments
      Then the command should succeed
      And the output directory should contain "go.mod"
      And the output directory should contain a ".go" file

    Scenario: morphir golang build with --json outputs JSON
      Given a minimal Morphir IR file
      When I run morphir golang build with --json flag
      Then the command should succeed
      And the output should be valid JSON
      And the JSON output should have "success" field
      And the JSON output should have "fileCount" field

    Scenario: morphir golang build with --workspace generates workspace
      Given a minimal Morphir IR file
      When I run morphir golang build with --workspace flag
      Then the command should succeed
      And the output directory should contain "go.work"

  Rule: JSONL batch mode

    Scenario: morphir golang build supports JSONL batch input
      Given a JSONL file with multiple IR inputs
      When I run morphir golang build with --jsonl-input flag
      Then the command should process all inputs
      And the output should contain JSONL results

