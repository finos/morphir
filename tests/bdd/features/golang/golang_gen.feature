@golang @cli
Feature: Go Code Generator CLI
  The morphir golang commands generate Go code from Morphir IR.
  This enables developers to use Morphir models in Go projects.

  Background:
    Given the morphir CLI is available

  Rule: Basic Go code generation from IR

    Scenario: morphir golang gen requires output directory
      When I run morphir golang gen without --output flag
      Then the command should fail
      And the error should mention "output"

    Scenario: morphir golang gen requires module path
      When I run morphir golang gen without --module-path flag
      Then the command should fail
      And the error should mention "module-path"

    Scenario: morphir golang gen requires IR file
      When I run morphir golang gen without an IR file
      Then the command should fail
      And the error should mention "IR file"

  Rule: JSON output mode

    Scenario: morphir golang gen with --json produces valid JSON output
      Given a minimal Morphir IR file
      When I run morphir golang gen with --json flag
      Then the command should succeed
      And the output should be valid JSON
      And the JSON output should have "success" field

    Scenario: morphir golang gen JSON output includes file count
      Given a minimal Morphir IR file
      When I run morphir golang gen with --json flag
      Then the JSON output should have "fileCount" field
      And the JSON output should have "generatedFiles" field

  Rule: Workspace mode generates go.work

    Scenario: morphir golang gen with --workspace generates go.work
      Given a minimal Morphir IR file
      When I run morphir golang gen with --workspace flag
      Then the command should succeed
      And the output directory should contain "go.work"

    Scenario: morphir golang gen without --workspace does not generate go.work
      Given a minimal Morphir IR file
      When I run morphir golang gen without --workspace flag
      Then the command should succeed
      And the output directory should not contain "go.work"
      And the output directory should contain "go.mod"

  Rule: Generated code structure

    Scenario: Generated code includes go.mod with correct module path
      Given a minimal Morphir IR file
      When I run morphir golang gen with module path "example.com/myapp"
      Then the output directory should contain "go.mod"
      And the go.mod should have module path "example.com/myapp"

    Scenario: Generated code includes package file
      Given a minimal Morphir IR file
      When I run morphir golang gen
      Then the output directory should contain a ".go" file

  Rule: Verbose output mode

    @pending
    Scenario: morphir golang gen with --verbose shows generated files
      Given a minimal Morphir IR file
      When I run morphir golang gen with --verbose flag
      Then the command should succeed
      And the output should list generated files
