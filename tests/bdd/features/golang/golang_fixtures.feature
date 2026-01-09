@golang @fixtures
Feature: Go Code Generation with IR Fixtures
  Tests code generation using realistic Morphir IR fixtures
  to validate type mappings and code structure.

  Background:
    Given the morphir CLI is available

  Rule: Type alias generation

    Scenario: Generate Go code from IR with type aliases
      Given the type-alias IR fixture
      When I run morphir golang gen
      Then the command should succeed
      And the output directory should contain "go.mod"
      And the output directory should contain a ".go" file

    Scenario: Type aliases map SDK types to Go types
      Given the type-alias IR fixture
      When I run morphir golang gen with --json flag
      Then the command should succeed
      And the JSON output should have "success" equal to true

  Rule: Record type generation

    Scenario: Generate Go code from IR with record types
      Given the record-type IR fixture
      When I run morphir golang gen
      Then the command should succeed
      And the output directory should contain a ".go" file

    Scenario: Record types produce struct definitions
      Given the record-type IR fixture
      When I run morphir golang gen with --json flag
      Then the JSON output should have "success" equal to true
      And the JSON output should have "fileCount" field

  Rule: Multi-module generation

    Scenario: Generate Go code from multi-module IR
      Given the multi-module IR fixture
      When I run morphir golang gen
      Then the command should succeed
      And the output directory should contain "go.mod"

    Scenario: Multi-module IR with workspace mode
      Given the multi-module IR fixture
      When I run morphir golang gen with --workspace flag
      Then the command should succeed
      And the output directory should contain "go.work"
      And the output directory should contain "go.mod"

