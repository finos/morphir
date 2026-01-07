@config @tasks
Feature: Task Configuration
  As a Morphir CLI user
  I want to define tasks in morphir.toml
  So that I can configure build pipelines with intrinsic actions and external commands

  Background:
    Given a clean config test environment

  # Basic task configuration
  @intrinsic
  Scenario: Intrinsic task is loaded from config
    Given a project config file with:
      """
      [tasks.compile]
      kind = "intrinsic"
      action = "morphir.pipeline.compile"
      """
    When I load configuration
    Then the configuration should load successfully
    And task "compile" should exist
    And task "compile" kind should be "intrinsic"
    And task "compile" action should be "morphir.pipeline.compile"

  @command
  Scenario: Command task is loaded from config
    Given a project config file with:
      """
      [tasks.codegen]
      kind = "command"
      cmd = ["morphir", "gen", "--target", "Scala"]
      """
    When I load configuration
    Then the configuration should load successfully
    And task "codegen" should exist
    And task "codegen" kind should be "command"
    And task "codegen" cmd should have 4 items
    And task "codegen" cmd[0] should be "morphir"

  # Task dependencies and hooks
  @dependencies
  Scenario: Task with dependencies is loaded
    Given a project config file with:
      """
      [tasks.build]
      kind = "intrinsic"
      action = "morphir.build"
      depends_on = ["compile", "analyze"]
      pre = ["setup"]
      post = ["summarize"]
      """
    When I load configuration
    Then the configuration should load successfully
    And task "build" depends_on should have 2 items
    And task "build" depends_on[0] should be "compile"
    And task "build" pre should have 1 items
    And task "build" post should have 1 items

  # Task with inputs and outputs
  @io
  Scenario: Task with inputs and outputs is loaded
    Given a project config file with:
      """
      [tasks.compile]
      kind = "intrinsic"
      action = "morphir.pipeline.compile"
      inputs = ["workspace:/src/**/*.elm"]
      outputs = ["workspace:/build/**"]
      """
    When I load configuration
    Then the configuration should load successfully
    And task "compile" inputs should have 1 items
    And task "compile" inputs[0] should be "workspace:/src/**/*.elm"
    And task "compile" outputs should have 1 items
    And task "compile" outputs[0] should be "workspace:/build/**"

  # Task with environment variables
  @env
  Scenario: Task with environment variables is loaded
    Given a project config file with:
      """
      [tasks.build]
      kind = "command"
      cmd = ["go", "build", "./..."]

      [tasks.build.env]
      GOFLAGS = "-mod=mod"
      CGO_ENABLED = "0"
      """
    When I load configuration
    Then the configuration should load successfully
    And task "build" env "GOFLAGS" should be "-mod=mod"
    And task "build" env "CGO_ENABLED" should be "0"

  # Task with mount permissions
  @mounts
  Scenario: Task with mount permissions is loaded
    Given a project config file with:
      """
      [tasks.compile]
      kind = "intrinsic"
      action = "morphir.pipeline.compile"

      [tasks.compile.mounts]
      workspace = "rw"
      config = "ro"
      env = "ro"
      """
    When I load configuration
    Then the configuration should load successfully
    And task "compile" mount "workspace" should be "rw"
    And task "compile" mount "config" should be "ro"
    And task "compile" mount "env" should be "ro"

  # Task with parameters
  @params
  Scenario: Task with parameters is loaded
    Given a project config file with:
      """
      [tasks.compile]
      kind = "intrinsic"
      action = "morphir.pipeline.compile"

      [tasks.compile.params]
      profile = "dev"
      optimize = false
      """
    When I load configuration
    Then the configuration should load successfully
    And task "compile" param "profile" should be "dev"

  # Multiple tasks
  @multiple
  Scenario: Multiple tasks are loaded
    Given a project config file with:
      """
      [tasks.setup]
      kind = "command"
      cmd = ["./scripts/setup.sh"]

      [tasks.compile]
      kind = "intrinsic"
      action = "morphir.pipeline.compile"
      depends_on = ["setup"]

      [tasks.test]
      kind = "command"
      cmd = ["go", "test", "./..."]
      depends_on = ["compile"]

      [tasks.build]
      kind = "intrinsic"
      action = "morphir.build"
      depends_on = ["compile", "test"]
      pre = ["setup"]
      """
    When I load configuration
    Then the configuration should load successfully
    And 4 tasks should be defined
    And task "setup" should exist
    And task "compile" should exist
    And task "test" should exist
    And task "build" should exist

  # No tasks defined
  @empty
  Scenario: No tasks section results in empty tasks
    Given a project config file with:
      """
      [ir]
      format_version = 3
      """
    When I load configuration
    Then the configuration should load successfully
    And 0 tasks should be defined

  # Scenario Outline for task kinds
  @outline @kinds
  Scenario Outline: Task kind "<kind>" with <config_type> is parsed correctly
    Given a project config file with:
      """
      [tasks.example]
      kind = "<kind>"
      <config>
      """
    When I load configuration
    Then the configuration should load successfully
    And task "example" kind should be "<kind>"
    And task "example" <field> should be "<value>"

    Examples: Intrinsic tasks
      | kind      | config_type | config                                  | field  | value                      |
      | intrinsic | action      | action = "morphir.pipeline.compile"     | action | morphir.pipeline.compile   |
      | intrinsic | action      | action = "morphir.analyzer.run"         | action | morphir.analyzer.run       |
      | intrinsic | action      | action = "morphir.report.summary"       | action | morphir.report.summary     |

    Examples: Command tasks
      | kind    | config_type | config                    | field  | value  |
      | command | cmd         | cmd = ["echo", "hello"]   | cmd[0] | echo   |
      | command | cmd         | cmd = ["go", "build"]     | cmd[0] | go     |
      | command | cmd         | cmd = ["npm", "install"]  | cmd[0] | npm    |

  # Scenario Outline for mount permissions
  @outline @mounts
  Scenario Outline: Mount permission "<permission>" is parsed for "<mount_name>"
    Given a project config file with:
      """
      [tasks.test]
      kind = "command"
      cmd = ["test"]

      [tasks.test.mounts]
      <mount_name> = "<permission>"
      """
    When I load configuration
    Then the configuration should load successfully
    And task "test" mount "<mount_name>" should be "<permission>"

    Examples:
      | mount_name | permission |
      | workspace  | rw         |
      | workspace  | ro         |
      | config     | ro         |
      | env        | ro         |
      | cache      | rw         |

  # Scenario Outline for dependency configurations
  @outline @dependencies
  Scenario Outline: Task with <dep_count> dependencies is loaded
    Given a project config file with:
      """
      [tasks.build]
      kind = "intrinsic"
      action = "morphir.build"
      <deps_config>
      """
    When I load configuration
    Then the configuration should load successfully
    And task "build" depends_on should have <dep_count> items

    Examples:
      | dep_count | deps_config                          |
      | 0         |                                      |
      | 1         | depends_on = ["compile"]             |
      | 2         | depends_on = ["compile", "analyze"]  |
      | 3         | depends_on = ["a", "b", "c"]         |

  # Scenario Outline for complete task configurations
  @outline @complete
  Scenario Outline: Complete <task_type> task configuration
    Given a project config file with:
      """
      <toml_config>
      """
    When I load configuration
    Then the configuration should load successfully
    And task "<task_name>" kind should be "<expected_kind>"
    And task "<task_name>" <primary_field> should be "<primary_value>"

    Examples:
      | task_type    | task_name | expected_kind | primary_field | primary_value              | toml_config                                                                                                                                                   |
      | pipeline     | compile   | intrinsic     | action        | morphir.pipeline.compile   | [tasks.compile]\nkind = "intrinsic"\naction = "morphir.pipeline.compile"\ninputs = ["workspace:/src/**/*.elm"]\noutputs = ["workspace:/build/**"]            |
      | analyzer     | analyze   | intrinsic     | action        | morphir.analyzer.run       | [tasks.analyze]\nkind = "intrinsic"\naction = "morphir.analyzer.run"\ninputs = ["workspace:/build/**"]\noutputs = ["workspace:/reports/analyzer.json"]       |
      | codegen      | codegen   | command       | cmd[0]        | morphir                    | [tasks.codegen]\nkind = "command"\ncmd = ["morphir", "gen", "--target", "Scala"]\ninputs = ["workspace:/morphir-ir.json"]\noutputs = ["workspace:/dist/**"] |
      | shell_script | setup     | command       | cmd[0]        | ./scripts/setup.sh         | [tasks.setup]\nkind = "command"\ncmd = ["./scripts/setup.sh"]\n[tasks.setup.mounts]\nworkspace = "rw"\nenv = "ro"                                            |
