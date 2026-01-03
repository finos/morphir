@config @loader
Feature: Configuration Loading
  As a Morphir CLI user
  I want configuration to be loaded from multiple sources
  So that I can customize behavior at different levels

  Background:
    Given a clean config test environment

  # Default values
  @defaults
  Scenario: Default values are used when no config exists
    Given no configuration files exist
    When I load configuration
    Then the configuration should load successfully
    And config "ir.format_version" should be 3
    And config "logging.level" should be "info"
    And config "ui.color" should be true
    And config "workspace.output_dir" should be ".morphir"

  # Single source loading
  @project
  Scenario: Project config is loaded from morphir.toml
    Given a project config file with:
      """
      [ir]
      format_version = 4
      strict_mode = true

      [logging]
      level = "debug"
      """
    When I load configuration
    Then the configuration should load successfully
    And config "ir.format_version" should be 4
    And config "ir.strict_mode" should be true
    And config "logging.level" should be "debug"

  # Priority ordering - env vars override project
  @priority @env
  Scenario: Environment variables override project config
    Given a project config file with:
      """
      [ir]
      format_version = 2
      """
    And environment variable "MORPHIR_IR__FORMAT_VERSION" is set to "5"
    When I load configuration
    Then the configuration should load successfully
    And config "ir.format_version" should be 5

  # Priority ordering - project overrides global
  @priority @global
  Scenario: Project config overrides global config
    Given a global config file with:
      """
      [logging]
      level = "warn"
      format = "json"
      """
    And a project config file with:
      """
      [logging]
      level = "debug"
      """
    When I load configuration
    Then the configuration should load successfully
    And config "logging.level" should be "debug"
    And config "logging.format" should be "json"

  # Nested map merging
  @merge
  Scenario: Nested maps are merged recursively
    Given a global config file with:
      """
      [codegen]
      output_format = "pretty"

      [codegen.go]
      package = "base"
      """
    And a project config file with:
      """
      [codegen.go]
      module = "github.com/example/project"
      """
    When I load configuration
    Then the configuration should load successfully
    And config "codegen.output_format" should be "pretty"
    And config "codegen.go.package" should be "base"
    And config "codegen.go.module" should be "github.com/example/project"

  # Slice replacement
  @merge @slices
  Scenario: Slices are replaced not appended
    Given a global config file with:
      """
      [codegen]
      targets = ["go", "scala"]
      """
    And a project config file with:
      """
      [codegen]
      targets = ["typescript"]
      """
    When I load configuration
    Then the configuration should load successfully
    And config "codegen.targets" should have 1 items
    And config "codegen.targets[0]" should be "typescript"

  # User override
  @user
  Scenario: User override file takes precedence over project config
    Given a project config file with:
      """
      [logging]
      level = "info"
      """
    And a user override config file with:
      """
      [logging]
      level = "trace"
      """
    When I load configuration
    Then the configuration should load successfully
    And config "logging.level" should be "trace"

  # Source tracking
  @sources
  Scenario: Loaded sources are tracked
    Given a project config file with:
      """
      [ir]
      format_version = 3
      """
    When I load configuration with details
    Then the configuration should load successfully
    And source "defaults" should be marked as loaded
    And source "project" should be marked as loaded
    And source "system" should be marked as not loaded
    And source "global" should be marked as not loaded

  # Missing sources handled gracefully
  @missing
  Scenario: Missing config files are gracefully skipped
    Given only a project config file exists with:
      """
      [ir]
      format_version = 3
      """
    When I load configuration
    Then the configuration should load successfully
    And no errors should be reported

  # Full priority chain
  @priority @full
  Scenario: Full priority chain is respected
    Given a system config file with:
      """
      [logging]
      level = "error"
      """
    And a global config file with:
      """
      [logging]
      level = "warn"
      """
    And a project config file with:
      """
      [logging]
      level = "info"
      """
    And a user override config file with:
      """
      [logging]
      level = "debug"
      """
    And environment variable "MORPHIR_LOGGING__LEVEL" is set to "trace"
    When I load configuration
    Then the configuration should load successfully
    And config "logging.level" should be "trace"
