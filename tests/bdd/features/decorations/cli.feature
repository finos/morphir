Feature: Decoration CLI Commands
  As a developer
  I want to use CLI commands to manage decorations
  So that I can configure and validate decorations efficiently

  Background:
    Given I have a workspace with decoration configuration

  Scenario: Set up decoration using registered type
    Given a registered decoration type "testFlag" with IR "test-ir.json" and entry point "Test:Types:Flag"
    When I run "morphir decoration setup myFlag --type testFlag"
    Then the command should succeed
    And the project configuration should contain decoration "myFlag"
    And decoration "myFlag" should reference type "testFlag"

  Scenario: Set up decoration using direct paths
    Given a decoration IR file "test-ir.json" exists
    When I run "morphir decoration setup myDecoration -i test-ir.json -e 'Test:Types:Flag' --display-name 'Test Flag'"
    Then the command should succeed
    And the project configuration should contain decoration "myDecoration"
    And decoration "myDecoration" should have entry point "Test:Types:Flag"

  Scenario: Validate decorations successfully
    Given a project with valid decoration values
    When I run "morphir decoration validate"
    Then the command should succeed
    And the output should indicate all decorations are valid

  Scenario: Validate decorations with errors
    Given a project with invalid decoration values
    When I run "morphir decoration validate"
    Then the command should fail
    And the output should indicate validation errors

  Scenario: List decorated nodes
    Given a project with decorations attached to nodes
    When I run "morphir decoration list"
    Then the command should succeed
    And the output should list decorated nodes

  Scenario: Get decorations for a node
    Given a project with decorations
    When I run "morphir decoration get 'Test.Package:Foo:bar'"
    Then the command should succeed
    And the output should show decorations for the node

  Scenario: Show decoration statistics
    Given a project with decorations
    When I run "morphir decoration stats"
    Then the command should succeed
    And the output should show decoration statistics

  Scenario: Register a decoration type
    Given a decoration IR file "test-ir.json" exists
    When I run "morphir decoration type register testFlag -i test-ir.json -e 'Test:Types:Flag' --display-name 'Test Flag'"
    Then the command should succeed
    And the decoration type "testFlag" should be registered

  Scenario: List registered decoration types
    Given registered decoration types exist
    When I run "morphir decoration type list"
    Then the command should succeed
    And the output should list registered types

  Scenario: Show decoration type details
    Given a registered decoration type "testFlag"
    When I run "morphir decoration type show testFlag"
    Then the command should succeed
    And the output should show type details

  Scenario: Unregister a decoration type
    Given a registered decoration type "testFlag"
    When I run "morphir decoration type unregister testFlag"
    Then the command should succeed
    And the decoration type "testFlag" should not be registered
