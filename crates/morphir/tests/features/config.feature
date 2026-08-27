Feature: Inspect Morphir configuration
  As a Morphir user
  I want to inspect the effective configuration and its sources
  So that I can understand the values the CLI will use

  Background:
    Given an isolated Morphir configuration environment

  Scenario: Discover the config subcommands from command help
    When I run "morphir config --help"
    Then the command succeeds
    And stdout contains "show"
    And stdout contains "path"
    And stdout contains "get"

  Scenario: Get a configuration value by dotted key
    Given a file "morphir.toml" containing:
      """
      [project]
      name = "acceptance-project"
      version = "1.0.0"
      """
    When I run "morphir config get project.name --isolated"
    Then the command succeeds
    And stdout is exactly "acceptance-project"

  Scenario: Get a typed configuration value as JSON
    Given a file "morphir.toml" containing:
      """
      [ir]
      format_version = 3
      """
    And the environment variable "MORPHIR_IR__FORMAT_VERSION" is "4"
    When I run "morphir config get ir.format_version --json --isolated"
    Then the command succeeds
    And stdout is valid JSON
    And the JSON get key is "ir.format_version"
    And the JSON get value is 4

  Scenario: Get redacts a secret value
    Given a file "morphir.toml" containing:
      """
      [registry]
      token = "top-secret-token"
      """
    When I run "morphir config get registry.token --json --isolated"
    Then the command succeeds
    And stdout contains "<redacted>"
    And stdout does not contain "top-secret-token"

  Scenario: Get fails when the key does not exist
    Given a file "morphir.toml" containing:
      """
      [project]
      name = "acceptance-project"
      version = "1.0.0"
      """
    When I run "morphir config get project.missing --isolated"
    Then the command fails
    And stderr contains "Configuration key not found: project.missing"

  Scenario: Show a discovered project configuration
    Given a file "morphir.toml" containing:
      """
      [project]
      name = "acceptance-project"
      version = "1.0.0"

      [ir]
      format_version = 3
      """
    And the working directory is "src/nested"
    When I run "morphir config show --isolated"
    Then the command succeeds
    And stdout contains "acceptance-project"
    And stdout contains "format_version = 3"

  Scenario: Show an explicitly selected configuration as JSON
    Given a file "configs/project.yaml" containing:
      """
      project:
        name: explicit-project
        version: 2.0.0
      """
    And the working directory is "elsewhere"
    When I run "morphir config show --config ../configs/project.yaml --json --isolated"
    Then the command succeeds
    And stdout is valid JSON
    And the JSON project name is "explicit-project"
    And the JSON project config ends with "configs/project.yaml"

  Scenario: Environment values override project values
    Given a file "morphir.toml" containing:
      """
      [ir]
      format_version = 3
      """
    And the environment variable "MORPHIR_IR__FORMAT_VERSION" is "4"
    When I run "morphir config show --json --isolated"
    Then the command succeeds
    And the JSON config value at "/ir/format_version" is 4

  Scenario: Show redacts secrets in JSON output
    Given a file "morphir.toml" containing:
      """
      [registry]
      token = "top-secret-token"
      endpoint = "https://registry.example.test"
      """
    When I run "morphir config show --json --isolated"
    Then the command succeeds
    And stdout contains "<redacted>"
    And stdout contains "https://registry.example.test"
    And stdout does not contain "top-secret-token"

  Scenario: List configuration sources for a discovered project
    Given a file "morphir.toml" containing:
      """
      [project]
      name = "source-project"
      version = "1.0.0"
      """
    When I run "morphir config path --isolated"
    Then the command succeeds
    And stdout contains "Configuration sources (in priority order):"
    And stdout contains "[✓] project"
    And stdout contains "Status: loaded"
    And stdout contains "[✓] defaults"

  Scenario: List configuration sources as JSON
    Given a file "morphir.toml" containing:
      """
      [project]
      name = "json-source-project"
      version = "1.0.0"
      """
    And the environment variable "MORPHIR_UI__COLOR" is "false"
    When I run "morphir config path --json --isolated"
    Then the command succeeds
    And stdout is valid JSON
    And the JSON source "project" has status "loaded"
    And the JSON source "environment" has status "loaded"
    And the JSON sources are ordered by ascending priority

  Scenario: Reject malformed configuration
    Given a file "morphir.toml" containing:
      """
      [project
      name = "broken"
      """
    When I run "morphir config show --isolated"
    Then the command fails
    And stderr contains "Configuration error"

  Scenario: Reject ambiguous project configuration
    Given a file "morphir.toml" containing:
      """
      [project]
      name = "toml-project"
      version = "1.0.0"
      """
    And a file "morphir.yaml" containing:
      """
      project:
        name: yaml-project
        version: 1.0.0
      """
    When I run "morphir config path --isolated"
    Then the command fails
    And stderr contains "Ambiguous Morphir configuration"

  Scenario: Discover project configuration in the dot-config layout
    Given a file ".config/morphir/config.toml" containing:
      """
      [project]
      name = "dot-config-project"
      version = "1.0.0"
      """
    When I run "morphir config path --isolated --json"
    Then the command succeeds
    And the JSON project config ends with ".config/morphir/config.toml"

  Scenario: Discover YAML project configuration in the dot-config layout
    Given a file ".config/morphir/config.yaml" containing:
      """
      project:
        name: dot-config-yaml-project
        version: 1.0.0
      """
    When I run "morphir config path --isolated --json"
    Then the command succeeds
    And the JSON project config ends with ".config/morphir/config.yaml"

  Scenario: An adjacent user override wins
    Given a file "morphir.toml" containing:
      """
      [ui]
      theme = "shared"
      """
    And a file "morphir.user.toml" containing:
      """
      [ui]
      theme = "personal"
      """
    When I run "morphir config show --json"
    Then the command succeeds
    And the JSON config string at "/ui/theme" is "personal"

  Scenario: An adjacent .morphir user override wins
    Given a file ".morphir/morphir.toml" containing:
      """
      [ui]
      theme = "shared"
      """
    And a file ".morphir/morphir.user.toml" containing:
      """
      [ui]
      theme = "personal"
      """
    When I run "morphir config show --json"
    Then the command succeeds
    And the JSON config string at "/ui/theme" is "personal"

  Scenario: An adjacent dot-config user override wins
    Given a file ".config/morphir/config.toml" containing:
      """
      [ui]
      theme = "shared"
      """
    And a file ".config/morphir/config.user.toml" containing:
      """
      [ui]
      theme = "personal"
      """
    When I run "morphir config show --json"
    Then the command succeeds
    And the JSON config string at "/ui/theme" is "personal"

  Scenario: Member user overrides win after workspace user overrides
    Given a file "morphir.toml" containing:
      """
      [workspace]
      members = ["members/alpha"]
      default_member = "members/alpha"

      [ui]
      theme = "workspace"
      """
    And a file "members/alpha/morphir.toml" containing:
      """
      [ui]
      theme = "member"
      """
    And a file "morphir.user.toml" containing:
      """
      [ui]
      theme = "workspace-user"
      """
    And a file "members/alpha/morphir.user.toml" containing:
      """
      [ui]
      theme = "member-user"
      """
    When I run "morphir config show --json"
    Then the command succeeds
    And the JSON config string at "/ui/theme" is "member-user"

  Scenario: Reject multiple primary configurations across layouts
    Given a file "morphir.toml" containing:
      """
      [project]
      name = "root-project"
      version = "1.0.0"
      """
    And a file ".morphir/morphir.toml" containing:
      """
      [project]
      name = "directory-project"
      version = "1.0.0"
      """
    When I run "morphir config path --isolated"
    Then the command fails
    And stderr contains "Ambiguous Morphir configuration"

  Scenario: Reject sibling user override serializations
    Given a file "morphir.toml" containing:
      """
      [ui]
      theme = "shared"
      """
    And a file "morphir.user.toml" containing:
      """
      [ui]
      theme = "toml-personal"
      """
    And a file "morphir.user.yaml" containing:
      """
      ui:
        theme: yaml-personal
      """
    When I run "morphir config show --json"
    Then the command fails
    And stderr contains "Ambiguous Morphir configuration"

  Scenario Outline: Resolve a protected secret from configuration
    Given a file "morphir.toml" containing the <reference> secret reference
    And the <backend> secret source contains a test value
    When the config secret "registry.token" is resolved
    Then the protected secret matches the test value
    And no resolution observation contains the test value

    Examples:
      | reference   | backend     |
      | literal     | literal     |
      | environment | environment |
      | file        | file        |
      | command     | command     |
      | keyring     | keyring     |

  Scenario: Command secret references preserve a shell-sensitive argument
    Given a file "morphir.toml" containing the command-argv secret reference
    When the config secret "registry.token" is resolved
    Then the protected secret matches the test value
    And no resolution observation contains the test value

  Scenario Outline: Secret resolution failures do not disclose backend output
    Given a file "morphir.toml" containing the <reference> failing secret reference
    When the config secret "registry.token" is resolved
    Then the resolution error is classified as <classification>
    And the resolution diagnostic omits protected backend output

    Examples:
      | reference       | classification        |
      | missing-key     | missing-config-key     |
      | missing-file    | file-read             |
      | malformed       | invalid-secret-value  |
      | empty-environment | empty-environment   |
      | failing-command | command-failed        |
      | missing-keyring | keyring-lookup-failed |

  Scenario: Error observations scan both formatted streams
    Then an error observation with backend stdout in stderr is rejected

  Scenario: CLI configuration inspection does not resolve command references
    Given a file "morphir.toml" containing a marker command secret reference
    When I run "morphir config get registry.token --isolated"
    Then the command succeeds
    And the secret command marker does not exist
    When I run "morphir config show --isolated"
    Then the command succeeds
    And the secret command marker does not exist
    When I run "morphir config path --isolated"
    Then the command succeeds
    And the secret command marker does not exist
    When I load the effective configuration directly
    Then the secret command marker does not exist
