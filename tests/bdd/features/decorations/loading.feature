Feature: Decoration Loading
  As a developer
  I want to load decorations from configuration files
  So that I can attach metadata to IR nodes

  Background:
    Given I have a workspace with decoration configuration

  Scenario: Load decorations from TOML configuration
    Given a project configuration file "project-with-decorations.toml" with decorations
    When I load the project configuration
    Then the project should have 2 decorations configured
    And decoration "simpleFlag" should have display name "Simple Flag"
    And decoration "documentation" should have entry point "Documentation.Decoration:Types:Documentation"

  Scenario: Load decorations from JSON configuration
    Given a project configuration file "project-with-decorations.json" with decorations
    When I load the project configuration
    Then the project should have 2 decorations configured
    And decoration "simpleFlag" should have display name "Simple Flag"

  Scenario: Load decoration values from file
    Given a decoration values file "simple-flag-values.json"
    When I load the decoration values
    Then the values should contain 3 entries
    And the value for "Test.Package:Foo:bar" should be true
    And the value for "Test.Package:Foo:baz" should be false

  Scenario: Load empty decoration values file
    Given a decoration values file "empty.json"
    When I load the decoration values
    Then the values should be empty
