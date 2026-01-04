@examples @workspace
Feature: Workspace loading with real example projects
  Example projects in the examples/ directory serve as both documentation
  and integration tests. Each example includes a test.yaml file that
  declares the expected behavior, making them self-describing.

  Rule: Auto-discovery of all example projects

    # This scenario automatically discovers and tests ALL example projects
    # that have a test.yaml file. Adding a new example with test.yaml
    # automatically includes it in the test suite.

    Scenario: All discovered examples pass their workspace expectations
      Given all discovered example projects
      When I test each example against its workspace expectations
      Then all examples should pass their workspace expectations

  Rule: Individual example workspace loading

    # Use Scenario Outline to test specific examples with custom assertions.
    # This allows for more granular control and different assertion patterns.

    Scenario Outline: Load <example> workspace and verify expectations
      Given the example project "<example>"
      When I load the example workspace
      Then all workspace expectations should pass

      Examples:
        | example              |
        | simple-project       |
        | monorepo-workspace   |
        | morphir-elm-compat   |

  Rule: Granular workspace assertions

    # Individual assertion steps for more specific testing scenarios

    Scenario: Verify simple project workspace loading details
      Given the example project "simple-project"
      When I load the example workspace
      Then the workspace loading expectation should pass
      And the root project expectations should pass

    Scenario: Verify monorepo workspace member loading
      Given the example project "monorepo-workspace"
      When I load the example workspace
      Then the workspace loading expectation should pass
      And the member expectations should pass
