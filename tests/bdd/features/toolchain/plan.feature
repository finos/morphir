@toolchain @plan
Feature: Morphir Plan Command
  The morphir plan command generates and displays execution plans
  for workflows defined in morphir.toml configuration files.

  Background:
    Given the morphir CLI is available
    And I am in a temporary directory

  Rule: Plan display and basic functionality

    Scenario: Plan command shows usage when no workflow specified
      When I run morphir plan
      Then the command should fail
      And the output should contain "accepts 1 arg(s), received 0"

    Scenario: Plan command shows help
      When I run morphir plan --help
      Then the command should succeed
      And the output should contain "plan"
      And the output should contain "--mermaid"
      And the output should contain "--show-inputs"

    Scenario: Plan displays execution stages and tasks
      Given a morphir.toml with a build workflow
      When I run morphir plan build
      Then the command should succeed
      And the output should contain "Stage: frontend"
      And the output should contain "morphir-elm/make"

  Rule: Mermaid diagram generation

    Scenario: Generate mermaid diagram with default path
      Given a morphir.toml with a build workflow
      When I run morphir plan build --mermaid
      Then the command should succeed
      And a mermaid file should exist at ".morphir/out/plan/build/plan.mmd"
      And the mermaid file should contain "flowchart TD"

    Scenario: Generate mermaid diagram to custom path
      Given a morphir.toml with a build workflow
      When I run morphir plan build --mermaid custom-plan.mmd
      Then the command should succeed
      And a file should exist at "custom-plan.mmd"
      And the file "custom-plan.mmd" should contain "flowchart TD"

    Scenario: Mermaid diagram contains stages as subgraphs
      Given a morphir.toml with a multi-stage workflow
      When I run morphir plan ci --mermaid output.mmd
      Then the command should succeed
      And the file "output.mmd" should contain "subgraph"
      And the file "output.mmd" should contain "Stage: frontend"
      And the file "output.mmd" should contain "Stage: backend"

    Scenario: Mermaid diagram shows dependencies between tasks
      Given a morphir.toml with dependent tasks
      When I run morphir plan build --mermaid output.mmd
      Then the command should succeed
      And the file "output.mmd" should contain "-->"

  Rule: Show inputs and outputs in mermaid output

    Scenario: Show-inputs and show-outputs flags include inputs and outputs
      Given a morphir.toml with dependent tasks
      When I run morphir plan build --mermaid --mermaid-path output.mmd --show-inputs --show-outputs
      Then the command should succeed
      And the file "output.mmd" should contain "in:"
      And the file "output.mmd" should contain "out:"

    Scenario: Show-inputs flag shows input file patterns
      Given a morphir.toml with tasks having inputs
      When I run morphir plan build --mermaid --mermaid-path output.mmd --show-inputs
      Then the command should succeed
      And the file "output.mmd" should contain "src/**/*.elm"

  Rule: Plan execution with --run flag

    Scenario: Dry run shows what would be executed
      Given a morphir.toml with a build workflow
      When I run morphir plan build --dry-run
      Then the command should succeed
      And the output should contain "DRY RUN"
      And the output should contain "Would execute"

    Scenario: Run with mermaid shows task execution status
      Given a morphir.toml with a simple echo workflow
      When I run morphir plan test --run --mermaid --mermaid-path output.mmd
      Then the command should succeed
      And the output should contain "SUCCESS"
      And the file "output.mmd" should contain "classDef success"

  Rule: Dependency explanation

    Scenario: Explain shows why a task runs
      Given a morphir.toml with dependent tasks
      When I run morphir plan build --explain elm-gen:Scala
      Then the command should succeed
      And the output should contain "depends on"

  Rule: Parallel execution indicator

    Scenario: Mermaid shows parallel stages
      Given a morphir.toml with parallel stages
      When I run morphir plan build --mermaid output.mmd
      Then the command should succeed
      And the file "output.mmd" should contain "(parallel)"

  Rule: Error handling for invalid workflows

    Scenario: Non-existent workflow produces helpful error
      Given a morphir.toml with a build workflow
      When I run morphir plan nonexistent
      Then the command should fail
      And the output should contain "workflow"
      And the output should contain "nonexistent"

    Scenario: Unknown target in workflow produces helpful error
      Given a morphir.toml with an unknown target
      When I run morphir plan build
      Then the command should fail
      And the output should contain "no task fulfills target"

    Scenario: Missing morphir.toml produces helpful error
      When I run morphir plan build
      Then the command should fail
      And the output should contain "no workflows defined in morphir.toml"

    Scenario: Empty workflow produces helpful error
      Given a morphir.toml with an empty workflow
      When I run morphir plan empty
      Then the command should fail
      And the output should contain "no stages defined"

  Rule: Stage conditions

    Scenario: Stage with true condition executes
      Given a morphir.toml with a conditional workflow
      When I run morphir plan build --run
      Then the command should succeed
      And the output should contain "check-stage"
      And the output should contain "completed"

    Scenario: Stage with false condition is skipped
      Given a morphir.toml with a false condition workflow
      When I run morphir plan build --run
      Then the command should succeed
      And the output should contain "skipped"
      And the output should contain "condition"
      And the output should contain "1 skipped"
