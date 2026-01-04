@project @list
Feature: Project List Command
  As a Morphir developer
  I want to list all projects in my workspace
  So that I can see an overview of my project structure

  Background:
    Given a clean workspace test environment

  @text-output
  Scenario: List projects in text format
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a member project at "packages/core" with:
      """
      [project]
      name = "core"
      source_directory = "src"
      exposed_modules = ["Main", "Types"]
      module_prefix = "Core"
      version = "1.0.0"
      """
    And a member project at "packages/utils" with:
      """
      [project]
      name = "utils"
      source_directory = "lib"
      exposed_modules = ["Helpers"]
      """
    When I load the workspace
    Then the project list should contain "core"
    And the project list should contain "utils"
    And the project list should show 2 projects

  @json-output
  Scenario: List projects in JSON format
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a member project at "packages/mylib" with:
      """
      [project]
      name = "mylib"
      source_directory = "src"
      exposed_modules = ["Lib"]
      version = "0.1.0"
      """
    When I load the workspace
    Then the project list JSON should have 1 items
    And the project list JSON item 0 should have "name" equal to "mylib"
    And the project list JSON item 0 should have "version" equal to "0.1.0"
    And the project list JSON item 0 should have "config_format" equal to "toml"

  @json-properties
  Scenario: List projects with filtered JSON properties
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a member project at "packages/app" with:
      """
      [project]
      name = "my-app"
      source_directory = "src"
      exposed_modules = ["Main"]
      version = "2.0.0"
      """
    When I load the workspace
    Then the filtered project list JSON with properties "name,version" should have 1 items
    And the filtered project list JSON item 0 should have key "name"
    And the filtered project list JSON item 0 should have key "version"
    And the filtered project list JSON item 0 should not have key "path"
    And the filtered project list JSON item 0 should not have key "config_format"

  @root-project
  Scenario: List projects including root project
    Given a workspace config with:
      """
      [workspace]
      members = ["libs/*"]

      [project]
      name = "root-app"
      source_directory = "src"
      exposed_modules = ["App"]
      module_prefix = "RootApp"
      version = "1.5.0"
      """
    And a member project at "libs/helper" with:
      """
      [project]
      name = "helper"
      source_directory = "src"
      exposed_modules = ["Help"]
      """
    When I load the workspace
    Then the project list should show 2 projects
    And the project list JSON item 0 should have "is_root" equal to true
    And the project list JSON item 0 should have "name" equal to "root-app"
    And the project list JSON item 1 should have "is_root" equal to false

  @empty-workspace
  Scenario: List projects in empty workspace
    Given a workspace config with:
      """
      [morphir]
      version = "^3.0.0"
      """
    When I load the workspace
    Then the project list should show 0 projects

  @exposed-modules-count
  Scenario: JSON output includes exposed modules count
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a member project at "packages/big" with:
      """
      [project]
      name = "big-lib"
      source_directory = "src"
      exposed_modules = ["A", "B", "C", "D", "E"]
      """
    When I load the workspace
    Then the project list JSON item 0 should have "exposed_modules_count" equal to 5
    And the project list JSON item 0 should have "exposed_modules" with 5 elements
