@golang @acceptance
Feature: Go Code Generation Acceptance Tests
  Acceptance tests validate that generated Go code
  is syntactically correct and compiles successfully.

  Background:
    Given the morphir CLI is available
    And Go toolchain is available

  Rule: Generated code compiles

    @slow
    Scenario: Generated Go module compiles successfully
      Given a minimal Morphir IR file
      When I run morphir golang gen
      And I run go build in the output directory
      Then the go build should succeed

    @slow
    Scenario: Generated Go workspace compiles successfully
      Given a minimal Morphir IR file
      When I run morphir golang gen with --workspace flag
      And I run go build in the output directory
      Then the go build should succeed

  Rule: Generated code is valid Go

    Scenario: Generated go.mod has valid syntax
      Given a minimal Morphir IR file
      When I run morphir golang gen
      Then the output directory should contain "go.mod"
      And the go.mod should be valid

    Scenario: Generated .go files have valid syntax
      Given a minimal Morphir IR file
      When I run morphir golang gen
      Then the output directory should contain a ".go" file
      And all .go files should have valid syntax

  Rule: Diagnostics for unsupported constructs

    @pending
    Scenario: Unsupported IR constructs produce warnings
      Given an IR with unsupported constructs
      When I run morphir golang gen with --json flag
      Then the JSON output should have "diagnostics" field
      And the diagnostics should contain warnings

