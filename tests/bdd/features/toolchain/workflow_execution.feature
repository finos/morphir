@toolchain @workflow @integration @pending
Feature: Workflow Execution with Built-in Toolchains
  # NOTE: These scenarios are pending implementation of the toolchain enablement design.
  # See docs/design/toolchain-enablement.md for the design specification.
  The morphir toolchain executes workflows that invoke built-in toolchains
  like morphir-elm to compile source code and generate artifacts.

  Background:
    Given the morphir CLI is available
    And npx is available
    And the morphir-elm-compat example project exists

  Rule: Workflow execution invokes morphir-elm make

    @slow
    Scenario: Build workflow executes morphir-elm make task
      Given I am in the morphir-elm-compat example directory
      And no morphir-ir.json file exists
      And a morphir.toml using the built-in morphir-elm toolchain:
        """
        [workflows.build]
        description = "Build workflow"

        [[workflows.build.stages]]
        name = "compile"
        targets = ["morphir-elm/make"]
        """
      When I run morphir plan build --run
      Then the command should succeed
      And the output should contain "morphir-elm/make"
      And the output should contain "SUCCESS"
      And a file should exist at "morphir-ir.json"

    @slow
    Scenario: Build workflow shows progress events
      Given I am in the morphir-elm-compat example directory
      And no morphir-ir.json file exists
      And a morphir.toml using the built-in morphir-elm toolchain:
        """
        [workflows.build]
        description = "Build workflow"

        [[workflows.build.stages]]
        name = "compile"
        targets = ["morphir-elm/make"]
        """
      When I run morphir plan build --run
      Then the command should succeed
      And the output should contain "Starting workflow"
      And the output should contain "compile"
      And the output should contain "completed"

    @slow
    Scenario: Build workflow produces valid Morphir IR
      Given I am in the morphir-elm-compat example directory
      And no morphir-ir.json file exists
      And a morphir.toml using the built-in morphir-elm toolchain:
        """
        [workflows.build]
        description = "Build workflow"

        [[workflows.build.stages]]
        name = "compile"
        targets = ["morphir-elm/make"]
        """
      When I run morphir plan build --run
      Then the command should succeed
      And the morphir-ir.json should be valid JSON
      And the morphir-ir.json should have format version 3

  Rule: Built-in toolchains require minimal configuration

    @slow
    Scenario: morphir-elm toolchain works with explicit task reference
      Given I am in the morphir-elm-compat example directory
      And no morphir-ir.json file exists
      And a minimal morphir.toml for build workflow:
        """
        [workflows.build]
        description = "Minimal build workflow"

        [[workflows.build.stages]]
        name = "compile"
        targets = ["morphir-elm/make"]
        """
      When I run morphir plan build --run
      Then the command should succeed
      And a file should exist at "morphir-ir.json"

  Rule: Workflow failure handling

    Scenario: Ambiguous target produces clear error
      Given I am in a temporary directory
      And a minimal morphir.toml for build workflow:
        """
        [workflows.build]
        description = "Build workflow"

        [[workflows.build.stages]]
        name = "compile"
        targets = ["make"]
        """
      When I run morphir plan build --run
      Then the command should fail
      And the output should contain "multiple tasks fulfill target"

  Rule: Workflow with multiple stages

    @slow
    Scenario: Multi-stage workflow executes in order
      Given I am in the morphir-elm-compat example directory
      And no morphir-ir.json file exists
      And a morphir.toml with make and gen stages:
        """
        [workflows.build]
        description = "Multi-stage build workflow"

        [[workflows.build.stages]]
        name = "compile"
        targets = ["morphir-elm/make"]

        [[workflows.build.stages]]
        name = "generate"
        targets = ["morphir-elm/gen:Scala"]
        """
      When I run morphir plan build --run
      Then the command should succeed
      And the output should contain "compile"
      And the output should contain "generate"
      And the output should contain "morphir-elm/make"
      And the output should contain "morphir-elm/gen"
